// SPDX-License-Identifier: MIT
pragma solidity 0.8.14;

import { BitMaps }       from "@openzeppelin/contracts/utils/structs/BitMaps.sol";
import { EnumerableSet } from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import { console }     from "@std/console.sol";

import { IBuckets } from "../interfaces/IBuckets.sol";

import "../libraries/Maths.sol";

abstract contract Buckets is IBuckets {
    uint256 public constant SECONDS_PER_DAY = 3600 * 24;
    uint256 public constant PENALTY_BPS = 0.001 * 10**18;

    /***********************/
    /*** State Variables ***/
    /***********************/

    using EnumerableSet for EnumerableSet.UintSet;

    mapping(uint256 => uint256) internal _bip;

    /**
     *  @notice Mapping of buckets for a given pool
     *  @dev price [WAD] -> bucket
     */
    mapping(uint256 => Buckets.Bucket) internal _buckets;

    /**
     *  @notice Mapping of NFT buckets for a given pool
     *  @dev price [WAD] -> nftBucket
     */
    mapping(uint256 => Buckets.NFTBucket) internal _nftBuckets;

    BitMaps.BitMap internal _bitmap;

    uint256 public override hpb;
    uint256 public override lup;
    uint256 public override pdAccumulator;

    /**********************************/
    /*** Internal Utility Functions ***/
    /**********************************/

    /**
     *  @notice Called by a lender to add quote tokens to a bucket
     *  @dev    Bucket.collateral is used to keep track of the total collateral in the bucket
     *  @dev    All NFT collateral is accounted for in WAD terms
     *  @param  bucket               The base bucket information
     *  @param  collateralDeposited  Set of NFT Token Ids that have been deposited into the bucket
     */
    struct NFTBucket {
        Bucket bucket;
        uint256 price;
        EnumerableSet.UintSet collateralDeposited;
    }

    /**
     *  @notice Called by a lender to add quote tokens to a bucket
     *  @param  price_      The price bucket to which quote tokens should be added.
     *  @param  amount_     The amount of quote tokens to be added.
     *  @param  totalDebt_  The amount of total debt.
     *  @param  inflator_   The current pool inflator rate.
     *  @return lpTokens_   The amount of lpTokens received by the lender for the added quote tokens.
     */
    function _addQuoteTokenToBucket(
        uint256 price_, uint256 amount_, uint256 totalDebt_, uint256 inflator_
    ) internal returns (uint256 lpTokens_) {
        // initialize bucket if required and get new HPB
        uint256 newHpb = !BitMaps.get(_bitmap, price_) ? initializeBucket(hpb, price_) : hpb;

        Bucket memory bucket    = _buckets[price_];
        bucket.debt             = accumulateBucketInterest(bucket.debt, bucket.inflatorSnapshot, inflator_);
        bucket.inflatorSnapshot = inflator_;

        lpTokens_ = Maths.rdiv(Maths.wadToRay(amount_), getExchangeRate(bucket));

        // bucket accounting
        bucket.lpOutstanding += lpTokens_;
        bucket.onDeposit     += amount_;
        pdAccumulator        += Maths.wmul(amount_, price_);

        // debt reallocation
        bool reallocate = totalDebt_ != 0 && price_ > lup;
        uint256 newLup = reallocate ? reallocateUp(bucket, amount_, inflator_) : lup;

        _buckets[price_] = bucket;

        // HPB and LUP management
        if (lup != newLup) lup = newLup;
        if (hpb != newHpb) hpb = newHpb;
    }

    /**
     *  @notice Called by a borrower to borrow from a given bucket
     *  @param  amount_   The amount of quote tokens to borrow from the bucket, WAD
     *  @param  fee_      The amount of quote tokens to pay as origination fee, WAD
     *  @param  limit_    The lowest price desired to borrow at, WAD
     *  @param  inflator_ The current pool inflator rate, RAY
     */
    function _borrowFromBucket(uint256 amount_, uint256 fee_, uint256 limit_, uint256 inflator_) internal {
        // if first loan then borrow at HPB price, otherwise at LUP
        uint256 price = lup == 0 ? hpb : lup;
        uint256 curPrice = price;
        uint256 pdRemove;

        while (true) {
            require(curPrice >= limit_, "B:B:PRICE_LT_LIMIT");

            Bucket storage curLup   = _buckets[curPrice];
            uint256 curDebt         = accumulateBucketInterest(curLup.debt, curLup.inflatorSnapshot, inflator_);
            uint256 deposit         = curLup.onDeposit;
            curLup.inflatorSnapshot = inflator_;

            if (amount_ > deposit) {
                // take all on deposit from this bucket
                curLup.debt      = curDebt + deposit;
                amount_         -= deposit;
                pdRemove         += Maths.wmul(deposit, curPrice);
                curLup.onDeposit = 0;
            } else {
                // take all remaining amount for loan from this bucket and exit
                curLup.onDeposit -= amount_;
                pdRemove         += Maths.wmul(amount_, curPrice);
                curLup.debt      = curDebt + amount_ + fee_;
                break;
            }

            curPrice = curLup.down; // move to next bucket
        }

        // HPB and LUP management
        lup = (price > curPrice|| price == 0) ? curPrice : price;
        pdAccumulator -= pdRemove;
    }

    /**
     *  @notice Called by a lender to claim accumulated collateral
     *  @param  price_        The price bucket from which collateral should be claimed
     *  @param  amount_       The amount of collateral tokens to be claimed, WAD
     *  @param  lpBalance_    The claimers current LP balance, RAY
     *  @return lpRedemption_ The amount of LP tokens that will be redeemed
     */
    function _claimCollateralFromBucket(
        uint256 price_, uint256 amount_, uint256 lpBalance_
    ) internal returns (uint256 lpRedemption_) {
        Bucket memory bucket = _buckets[price_];

        require(amount_ <= bucket.collateral, "B:CC:AMT_GT_COLLAT");

        lpRedemption_ = Maths.wrdivr(Maths.wmul(amount_, bucket.price), getExchangeRate(bucket));

        require(lpRedemption_ <= lpBalance_, "B:CC:INSUF_LP_BAL");

        // bucket accounting
        bucket.collateral    -= amount_;
        bucket.lpOutstanding -= lpRedemption_;

        // bucket management
        bool isEmpty = bucket.onDeposit == 0 && bucket.debt == 0;
        bool noClaim = bucket.lpOutstanding == 0 && bucket.collateral == 0;
        if (isEmpty && noClaim) {
            deactivateBucket(bucket); // cleanup if bucket no longer used
        } else {
            _buckets[price_] = bucket; // save bucket to storage
        }
    }

    /**
     *  @notice Liquidate a given position's collateral
     *  @param  debt_               The amount of debt to cover, WAD
     *  @param  collateral_         The amount of collateral deposited, WAD
     *  @param  inflator_           The current pool inflator rate, RAY
     *  @return requiredCollateral_ The amount of collateral to be liquidated
     */
    function _liquidateAtBucket(
        uint256 debt_, uint256 collateral_, uint256 inflator_
    ) internal returns (uint256 requiredCollateral_) {
        uint256 curPrice = hpb;

        while (true) {
            Bucket storage bucket   = _buckets[curPrice];
            uint256 curDebt         = accumulateBucketInterest(bucket.debt, bucket.inflatorSnapshot, inflator_);
            bucket.inflatorSnapshot = inflator_;

            uint256 bucketDebtToPurchase     = Maths.min(debt_, curDebt);
            uint256 bucketRequiredCollateral = Maths.min(Maths.wdiv(debt_, bucket.price), collateral_);

            debt_               -= bucketDebtToPurchase;
            collateral_         -= bucketRequiredCollateral;
            requiredCollateral_ += bucketRequiredCollateral;

            // bucket accounting
            curDebt           -= bucketDebtToPurchase;
            bucket.collateral += bucketRequiredCollateral;

            // forgive the debt when borrower has no remaining collateral but still has debt
            if (debt_ != 0 && collateral_ == 0) {
                bucket.debt = 0;
                break;
            }

            bucket.debt = curDebt;

            if (debt_ == 0) break; // stop if all debt reconciliated

            curPrice = bucket.down;
        }

        // HPB and LUP management
        uint256 newHpb = getHpb();
        if (hpb != newHpb) hpb = newHpb;
    }

    /**
     *  @notice Called by a lender to remove quote tokens from a bucket
     *  @param  fromPrice_    The price bucket from where quote tokens should be moved
     *  @param  toPrice_      The price bucket where quote tokens should be moved
     *  @param  maxAmount_    The max amount of quote tokens to be moved, WAD
     *  @param  lpBalance_    The LP balance for current lender, RAY
     *  @param  lpTimer_      The timestamp of the last lender deposit in bucket
     *  @param  inflator_     The current pool inflator rate, RAY
     *  @return lpRedemption_ The amount of lpTokens moved from bucket
     *  @return lpAward_      The amount of lpTokens moved to bucket
     *  @return amount_       The amount of quote tokens moved to bucket
     */
    function _moveQuoteTokenFromBucket(
        uint256 fromPrice_, uint256 toPrice_, uint256 maxAmount_, uint256 lpBalance_, uint256 lpTimer_, uint256 inflator_
    ) internal returns (uint256 lpRedemption_, uint256 lpAward_, uint256 amount_) {
        uint256 newHpb = !BitMaps.get(_bitmap, toPrice_) ? initializeBucket(hpb, toPrice_) : hpb;
        uint256 newLup = lup;

        Bucket memory fromBucket    = _buckets[fromPrice_];
        fromBucket.debt             = accumulateBucketInterest(fromBucket.debt, fromBucket.inflatorSnapshot, inflator_);
        fromBucket.inflatorSnapshot = inflator_;

        uint256 exchangeRate = getExchangeRate(fromBucket);                 // RAY
        uint256 claimable    = Maths.rmul(lpBalance_, exchangeRate);       // RAY

        amount_       = Maths.min(Maths.wadToRay(maxAmount_), claimable); // RAY
        lpRedemption_ = Maths.rdiv(amount_, exchangeRate);                // RAY
        amount_       = Maths.rayToWad(amount_);

        Bucket memory toBucket    = _buckets[toPrice_];
        toBucket.debt             = accumulateBucketInterest(toBucket.debt, toBucket.inflatorSnapshot, inflator_);
        toBucket.inflatorSnapshot = inflator_;

        // apply bid penalty if deposit happened less than 24h ago
        if (fromBucket.price > toBucket.price && block.timestamp - lpTimer_ < SECONDS_PER_DAY) {
            uint256 penalty        = Maths.wmul(PENALTY_BPS, fromBucket.price - toBucket.price);
            amount_                -= penalty;
            _bip[fromBucket.price] += penalty;
        }

        lpAward_ = Maths.rdiv(Maths.wadToRay(amount_), getExchangeRate(toBucket));

        // move LP tokens
        fromBucket.lpOutstanding -= lpRedemption_;
        toBucket.lpOutstanding   += lpAward_;

        bool atLup  = newLup != 0 && fromBucket.price == newLup;
        if (atLup) {
            newLup = moveQuoteTokenAtLup(fromBucket, toBucket, amount_, inflator_);
        } else {
            newLup = moveQuoteTokenAtPrice(fromBucket, toBucket, amount_, inflator_, newLup);
        }

        bool isEmpty = fromBucket.onDeposit == 0 && fromBucket.debt == 0;
        bool noClaim = fromBucket.lpOutstanding == 0 && fromBucket.collateral == 0;

        _buckets[fromBucket.price] = fromBucket;
        _buckets[toBucket.price]   = toBucket;

        // HPB and LUP management
        if (newLup != lup) lup = newLup;
        newHpb = (isEmpty && fromBucket.price == newHpb) ? getHpb() : newHpb;
        if (newHpb != hpb) hpb = newHpb;

        // bucket management
        if (isEmpty && noClaim) deactivateBucket(fromBucket); // cleanup if bucket no longer used
    }

    /**
     *  @notice Puchase a given amount of quote tokens for given collateral tokens
     *  @param  price_      The price bucket at which the exchange will occur, WAD
     *  @param  amount_     The amount of quote tokens to receive, WAD
     *  @param  collateral_ The amount of collateral to exchange, WAD
     *  @param  inflator_   The current pool inflator rate, RAY
     */
    function _purchaseBidFromBucket(
        uint256 price_, uint256 amount_, uint256 collateral_, uint256 inflator_
    ) internal {
        Bucket memory bucket    = _buckets[price_];
        bucket.debt             = accumulateBucketInterest(bucket.debt, bucket.inflatorSnapshot, inflator_);
        bucket.inflatorSnapshot = inflator_;

        uint256 available = bucket.onDeposit + bucket.debt;

        require(amount_ <= available, "B:PB:INSUF_BUCKET_LIQ");

        // Exchange collateral for quote token on deposit
        uint256 purchaseFromDeposit = Maths.min(amount_, bucket.onDeposit);

        amount_          -= purchaseFromDeposit;
        // bucket accounting
        bucket.onDeposit -= purchaseFromDeposit;
        bucket.collateral += collateral_;

        // debt reallocation
        uint256 newLup = reallocateDown(bucket, amount_, inflator_);

        _buckets[price_] = bucket;

        uint256 newHpb = (bucket.onDeposit == 0 && bucket.debt == 0) ? getHpb() : hpb;

        // HPB and LUP management
        if (lup != newLup) lup = newLup;
        if (hpb != newHpb) hpb = newHpb;

        pdAccumulator -= Maths.wmul(purchaseFromDeposit, bucket.price);
    }

    /**
     *  @notice Called by a lender to claim accumulated NFT collateral
     *  @param  price_        The price bucket from which collateral should be claimed
     *  @param  tokenId_      The tokenId of the collateral to claim
     *  @param  lpBalance_    The claimers current LP balance, RAY
     *  @return lpRedemption_ The amount of LP tokens that will be redeemed
     */
    function _claimNFTCollateralFromBucket(uint256 price_, uint256 tokenId_, uint256 lpBalance_) internal returns (uint256 lpRedemption_) {
        Bucket storage bucket = _buckets[price_];
        NFTBucket storage nftBucket = _nftBuckets[price_];

        // TODO: check if this is right approach...?
        // check available collateral given removal of the NFT
        require(Maths.ONE_WAD <= bucket.collateral, "B:CC:AMT_GT_COLLAT");

        // nft collateral is account for in WAD units
        lpRedemption_ = Maths.wrdivr(Maths.wmul(Maths.ONE_WAD, bucket.price), getExchangeRate(bucket));

        // update bucket accounting
        bucket.collateral -= Maths.ONE_WAD;
        bucket.lpOutstanding -= lpRedemption_;
        nftBucket.collateralDeposited.remove(tokenId_);

        // bucket management
        bool isEmpty = bucket.onDeposit == 0 && bucket.debt == 0;
        bool noClaim = bucket.lpOutstanding == 0 && bucket.collateral == 0;
        if (isEmpty && noClaim) deactivateBucket(bucket); // cleanup if bucket no longer used
    }

    /**
     *  @notice Called by a lender to remove quote tokens from a bucket
     *  @param  price_     The price bucket from which quote tokens should be removed
     *  @param  maxAmount_ The maximum amount of quote tokens to be removed, WAD
     *  @param  lpBalance_ The LP balance for current lender, RAY
     *  @param  lpTimer_   The timestamp of the last lender deposit in bucket
     *  @param  inflator_  The current pool inflator rate, RAY
     *  @return amount_    The actual amount being removed
     *  @return lpTokens_  The amount of lpTokens removed equivalent to the quote tokens removed
     */
    function _removeQuoteTokenFromBucket(
        uint256 price_, uint256 maxAmount_, uint256 lpBalance_, uint256 lpTimer_, uint256 inflator_
    ) internal returns (uint256 amount_, uint256 lpTokens_) {
        Bucket memory bucket    = _buckets[price_];
        bucket.debt             = accumulateBucketInterest(bucket.debt, bucket.inflatorSnapshot, inflator_);
        bucket.inflatorSnapshot = inflator_;

        uint256 exchangeRate = getExchangeRate(bucket);                // RAY
        uint256 claimable    = Maths.rmul(lpBalance_, exchangeRate);   // RAY
        amount_             = Maths.min(Maths.wadToRay(maxAmount_), claimable); // RAY
        lpTokens_           = Maths.rdiv(amount_, exchangeRate);                // RAY
        amount_             = Maths.rayToWad(amount_);

        // bucket accounting
        uint256 removeFromDeposit = Maths.min(amount_, bucket.onDeposit); // Remove from deposit first
        bucket.onDeposit     -= removeFromDeposit;
        bucket.lpOutstanding -= lpTokens_;

        // debt reallocation
        uint256 newLup = reallocateDown(bucket, amount_ - removeFromDeposit, inflator_);
        pdAccumulator  -= Maths.wmul(removeFromDeposit, bucket.price);

        // apply bid penalty if deposit happened less than 24h ago
        if (block.timestamp - lpTimer_ < SECONDS_PER_DAY) {
            uint256 penalty = Maths.wmul(PENALTY_BPS, amount_);
            amount_        -= penalty;
            _bip[bucket.price]   += penalty;
        }

        bool isEmpty = bucket.onDeposit == 0 && bucket.debt == 0;
        bool noClaim = bucket.lpOutstanding == 0 && bucket.collateral == 0;

        _buckets[bucket.price] = bucket;

        // HPB and LUP management
        uint256 newHpb = (isEmpty && bucket.price == hpb) ? getHpb() : hpb;
        if (bucket.price >= lup && newLup < lup) lup = newLup; // move lup down only if removal happened at or above lup
        if (newHpb != hpb) hpb = newHpb;

        // bucket management
        if (isEmpty && noClaim) deactivateBucket(bucket); // cleanup if bucket no longer used
    }

    /**
     *  @notice Called by a borrower to repay quote tokens as part of reducing their position
     *  @param  amount_       The amount of quote tokens to repay to the bucket, WAD
     *  @param  inflator_     The current pool inflator rate, RAY
     *  @param  reconcile_    True if all debt in pool is repaid
     */
    function _repayBucket(uint256 amount_, uint256 inflator_, bool reconcile_) internal {
        uint256 curPrice = lup;
        uint256 pdAdd;

        while (true) {
            Bucket storage curLup = _buckets[curPrice];
            uint256 curDebt = accumulateBucketInterest(curLup.debt, curLup.inflatorSnapshot, inflator_);
            if (curDebt != 0) {
                curLup.inflatorSnapshot = inflator_;

                if (amount_ > curDebt) {
                    // pay entire debt on this bucket
                    amount_         -= curDebt;
                    curLup.onDeposit += curDebt;
                    pdAdd            += Maths.wmul(curDebt, curPrice);
                    curLup.debt      = 0;
                } else {
                    // pay as much debt as possible and exit
                    curLup.onDeposit += amount_;
                    pdAdd            += Maths.wmul(amount_, curPrice);
                    curLup.debt      = curDebt - amount_;
                    amount_         = 0;
                    break;
                }
            }

            if (curPrice == curLup.up) break; // nowhere to go

            curPrice = curLup.up; // move to upper bucket
        }

        // HPB and LUP management
        if (reconcile_) lup = 0;                 // reset LUP if no debt in pool
        else if (lup != curPrice) lup = curPrice; // update LUP to current price

        pdAccumulator += pdAdd;
    }

    /*********************************/
    /*** Private Utility Functions ***/
    /*********************************/

    /**
     *  @notice Update bucket.debt with interest accumulated since last state change
     *  @param debt_         Current ucket debt bucket being updated
     *  @param inflator_     RAY - The current bucket inflator value
     *  @param poolInflator_ RAY - The current pool inflator value
     */
    function accumulateBucketInterest(uint256 debt_, uint256 inflator_, uint256 poolInflator_) private pure returns (uint256){
        if (debt_ != 0) {
            // To preserve precision, multiply WAD * RAY = RAD, and then scale back down to WAD
            debt_ += Maths.radToWadTruncate(
                debt_ * (Maths.rdiv(poolInflator_, inflator_) - Maths.ONE_RAY)
            );
        }
        return debt_;
    }

    /**
     *  @notice Removes state for an unused bucket and update surrounding price pointers
     *  @param  bucket_ The price bucket to deactivate.
     */
    function deactivateBucket(Bucket memory bucket_) private {
        BitMaps.setTo(_bitmap, bucket_.price, false);
        bool isHighestBucket = bucket_.price == bucket_.up;
        bool isLowestBucket = bucket_.down == 0;
        if (isHighestBucket && !isLowestBucket) {                       // if highest bucket
            _buckets[bucket_.down].up = _buckets[bucket_.down].price; // make lower bucket the highest bucket
        } else if (!isHighestBucket && !isLowestBucket) {               // if middle bucket
            _buckets[bucket_.up].down = bucket_.down;                 // update down pointer of upper bucket
            _buckets[bucket_.down].up = bucket_.up;                   // update up pointer of lower bucket
        } else if (!isHighestBucket && isLowestBucket) {                // if lowest bucket
            _buckets[bucket_.up].down = 0;                             // make upper bucket the lowest bucket
        }
        delete _buckets[bucket_.price];
    }

    /**
     *  @notice Set state for a new bucket and update surrounding price pointers
     *  @param  hpb_   The current highest price bucket of the pool, WAD
     *  @param  price_ The price of the bucket to retrieve information from, WAD
     *  @return The new HPB given the newly initialized bucket
     */
    function initializeBucket(uint256 hpb_, uint256 price_) private returns (uint256) {
        Bucket storage bucket = _buckets[price_];

        bucket.price            = price_;
        bucket.inflatorSnapshot = Maths.ONE_RAY;

        if (price_ > hpb_) {
            bucket.down = hpb_;
            hpb_ = price_;
        }

        uint256 cur  = hpb_;
        uint256 down = _buckets[hpb_].down;
        uint256 up   = _buckets[hpb_].up;

        // update price pointers
        while (true) {
            if (price_ > down) {
                _buckets[cur].down = price_;
                bucket.up          = cur;
                bucket.down        = down;
                _buckets[down].up  = price_;
                break;
            }
            cur  = down;
            down = _buckets[cur].down;
            up   = _buckets[cur].up;
        }
        BitMaps.setTo(_bitmap, price_, true);
        return hpb_;
    }

    /**
     *  @notice Utility function to move quote tokens from LUP.
     *  @dev    Avoid Solidity's stack too deep in moveQuoteToken function
     *  @param  fromBucket_ The given bucket whose assets are being moved
     *  @param  toBucket_   The given bucket where assets are being moved
     *  @param  amount_     The amount of quote tokens being moved
     *  @param  inflator_   The current pool inflator rate, RAY
     *  @return newLup_     The new LUP
     */
    function moveQuoteTokenAtLup(
        Bucket memory fromBucket_, Bucket memory toBucket_, uint256 amount_, uint256 inflator_
    ) private returns (uint256 newLup_) {
        bool moveUp           = fromBucket_.price < toBucket_.price;
        uint256 debtToMove    = (amount_ > fromBucket_.onDeposit) ? amount_ - fromBucket_.onDeposit : 0;
        uint256 depositToMove = amount_ - debtToMove;

        // move debt
        if (moveUp) {
            fromBucket_.debt -= debtToMove;
            toBucket_.debt   += debtToMove;
        }

        // move deposit
        uint256 toOnDeposit  = moveUp ? depositToMove : amount_;
        fromBucket_.onDeposit -= depositToMove;
        toBucket_.onDeposit   += toOnDeposit;

        if (moveUp) {
            newLup_ = reallocateUpFromBucket(fromBucket_, toBucket_, depositToMove, inflator_);
        } else {
            newLup_ = reallocateDown(fromBucket_, debtToMove, inflator_);
        }

        pdAccumulator = pdAccumulator + Maths.wmul(toOnDeposit, toBucket_.price) - Maths.wmul(depositToMove, fromBucket_.price);
    }

    /**
     *  @notice Utility function to move quote tokens at a specific price (other than LUP)
     *  @dev    Avoid Solidity's stack too deep in moveQuoteToken function
     *  @param  fromBucket_ The given bucket whose assets are being moved
     *  @param  toBucket_   The given bucket where assets are being moved
     *  @param  amount_     The amount of quote tokens being moved
     *  @param  inflator_   The current pool inflator rate, RAY
     *  @param  lup_        The current LUP
     *  @return newLup_     The new LUP
     */
    function moveQuoteTokenAtPrice(
        Bucket memory fromBucket_, Bucket memory toBucket_, uint256 amount_, uint256 inflator_, uint256 lup_
    ) private returns (uint256 newLup_) {
        newLup_       = lup_;
        bool moveUp   = fromBucket_.price < toBucket_.price;
        bool aboveLup = newLup_ !=0 && newLup_ < Maths.min(fromBucket_.price, toBucket_.price);

        if (aboveLup) {
            // move debt
            fromBucket_.debt -= amount_;
            toBucket_.debt   += amount_;
        } else {
            // move deposit
            uint256 fromOnDeposit = moveUp ? amount_ : Maths.min(amount_, fromBucket_.onDeposit);
            fromBucket_.onDeposit -= fromOnDeposit;
            toBucket_.onDeposit   += amount_;

            if (newLup_ != 0 && toBucket_.price > Maths.max(fromBucket_.price, newLup_)) {
                newLup_ = reallocateUp(toBucket_, amount_, inflator_);
            } else if (newLup_ != 0 && fromBucket_.price >= Maths.max(toBucket_.price, newLup_)) {
                newLup_ = reallocateDownToBucket(fromBucket_, toBucket_, amount_, inflator_);
            }

            pdAccumulator = pdAccumulator + Maths.wmul(amount_, toBucket_.price) - Maths.wmul(fromOnDeposit, fromBucket_.price);
        }
    }

    /**
     *  @notice Moves assets in a bucket to a bucket's down pointers
     *  @dev    Occurs when quote tokens are being removed
     *  @dev    Should continue until all of the desired quote tokens have been removed
     *  @param  bucket_   The given bucket whose assets are being reallocated
     *  @param  amount_   The amount of quote tokens requiring reallocation, WAD
     *  @param  inflator_ The current pool inflator rate, RAY
     *  @return lup_      The price to which assets were reallocated
     */
    function reallocateDown(
        Bucket memory bucket_, uint256 amount_, uint256 inflator_
    ) private returns (uint256 lup_) {

        lup_ = bucket_.price;
        // debt reallocation
        if (amount_ > bucket_.onDeposit) {
            uint256 pdRemove;
            uint256 reallocation = amount_ - bucket_.onDeposit;
            if (bucket_.down != 0) {
                uint256 toPrice = bucket_.down;

                while (true) {
                    Bucket storage toBucket   = _buckets[toPrice];
                    uint256 toDebt            = accumulateBucketInterest(toBucket.debt, toBucket.inflatorSnapshot, inflator_);
                    uint256 toDeposit         = toBucket.onDeposit;
                    toBucket.inflatorSnapshot = inflator_;

                    if (reallocation < toDeposit) {
                        // reallocate all and exit
                        bucket_.debt       -= reallocation;
                        toBucket.debt      = toDebt + reallocation;
                        toBucket.onDeposit -= reallocation;
                        pdRemove           += Maths.wmul(reallocation, toPrice);
                        lup_ = toPrice;
                        break;
                    } else {
                        if (toDeposit != 0) {
                            reallocation       -= toDeposit;
                            bucket_.debt      -= toDeposit;
                            toDebt             += toDeposit;
                            pdRemove           += Maths.wmul(toDeposit, toPrice);
                            toBucket.onDeposit -= toDeposit;
                        }
                        toBucket.debt = toDebt;
                    }

                    if (toBucket.down == 0) {
                        // last bucket, nowhere to go, guard against reallocation failures
                        require(reallocation == 0, "B:RD:NO_REALLOC_LOCATION");
                        lup_ = toPrice;
                        break;
                    }

                    toPrice = toBucket.down;
                }
            } else {
                require(reallocation == 0, "B:RD:NO_REALLOC_LOCATION");
            }

            pdAccumulator -= pdRemove;
        }
    }

    /**
     *  @notice Moves assets in a bucket to a bucket's down pointers
     *  @dev    Occurs when quote tokens are being removed
     *  @dev    Should continue until all of the desired quote tokens have been removed
     *  @param  fromBucket_ The given bucket whose assets are being reallocated / moved
     *  @param  toBucket_   The given bucket where assets are being reallocated / moved
     *  @param  amount_   The amount of quote tokens requiring reallocation, WAD
     *  @param  inflator_ The current pool inflator rate, RAY
     *  @return lup_      The price to which assets were reallocated
     */
   function reallocateDownToBucket(
        Bucket memory fromBucket_, Bucket memory toBucket_, uint256 amount_, uint256 inflator_
    ) private returns (uint256 lup_) {

        lup_ = fromBucket_.price;

        if (amount_ > fromBucket_.onDeposit) {

            uint256 pdRemove;
            uint256 reallocation = amount_ - fromBucket_.onDeposit;

            if (fromBucket_.down != 0) {
                uint256 toPrice = fromBucket_.down;

                Bucket memory toBucket;
                bool isToBucket;

                while (true) {
                    isToBucket = toPrice == toBucket_.price;
                    if (isToBucket) { // use from bucket loaded in memory
                        toBucket  = toBucket_;
                    } else {
                        toBucket      = _buckets[toPrice]; // load to bucket from storage
                        toBucket.debt = accumulateBucketInterest(toBucket.debt, toBucket.inflatorSnapshot, inflator_);

                        toBucket.inflatorSnapshot = inflator_;
                    }

                    if (reallocation < toBucket.onDeposit) {
                        // reallocate all and exit
                        fromBucket_.debt  -= reallocation;
                        toBucket.debt      += reallocation;
                        toBucket.onDeposit -= reallocation;
                        pdRemove           += Maths.wmul(reallocation, toPrice);
                        lup_ = toPrice;

                        if (!isToBucket) _buckets[toPrice] = toBucket;

                        break;
                    } else {
                        if (toBucket.onDeposit != 0) {
                            reallocation       -= toBucket.onDeposit;
                            fromBucket_.debt  -= toBucket.onDeposit;
                            toBucket.debt      += toBucket.onDeposit;
                            pdRemove           += Maths.wmul(toBucket.onDeposit, toPrice);
                            toBucket.onDeposit = 0;
                        }

                        if (!isToBucket) _buckets[toPrice] = toBucket;
                    }

                    if (toBucket.down == 0) {
                        // last bucket, nowhere to go, guard against reallocation failures
                        require(reallocation == 0, "B:RD:NO_REALLOC_LOCATION");
                        lup_ = toPrice;
                        break;
                    }

                    toPrice = toBucket.down;
                }
            } else {
                require(reallocation == 0, "B:RD:NO_REALLOC_LOCATION");
            }

            pdAccumulator -= pdRemove;
        }
    }

    /**
     *  @notice Moves assets in a bucket to a bucket's up pointers
     *  @dev    Should continue until all desired quote tokens are added
     *  @dev    Occcurs when quote tokens are being added
     *  @param  bucket_   The given bucket whose assets are being reallocated
     *  @param  amount_   The amount of quote tokens requiring reallocation, WAD
     *  @param  inflator_ The current pool inflator rate, RAY
     *  @return lup_      The price to which assets were reallocated
     */
    function reallocateUp(
        Bucket memory bucket_, uint256 amount_, uint256 inflator_
    ) private returns (uint256 lup_) {

        uint256 curPrice = lup;
        uint256 pdAdd;
        uint256 pdRemove;

        while (true) {
            if (curPrice == bucket_.price) break; // reached deposit bucket; nowhere to go

            Bucket storage curLup = _buckets[curPrice];
            uint256 curLupDebt    = accumulateBucketInterest(curLup.debt, curLup.inflatorSnapshot, inflator_);

            curLup.inflatorSnapshot = inflator_;

            if (amount_ > curLupDebt) {
                bucket_.debt      += curLupDebt;
                bucket_.onDeposit -= curLupDebt;
                pdRemove          += Maths.wmul(curLupDebt, bucket_.price);
                curLup.debt       = 0;
                curLup.onDeposit  += curLupDebt;
                pdAdd             += Maths.wmul(curLupDebt, curPrice);
                amount_           -= curLupDebt;

                if (curPrice == curLup.up) break; // reached top-of-book; nowhere to go

            } else {
                bucket_.debt      += amount_;
                bucket_.onDeposit -= amount_;
                pdRemove          += Maths.wmul(amount_, bucket_.price);
                curLup.debt       = curLupDebt - amount_;
                curLup.onDeposit  += amount_;
                pdAdd             += Maths.wmul(amount_, curPrice);
                break;
            }

            curPrice = curLup.up;
        }

        lup_ = curPrice;
        pdAccumulator = pdAccumulator + pdAdd - pdRemove;
    }

    /**
     *  @notice Moves assets in a bucket to a bucket's up pointers
     *  @dev    Should continue until all desired quote tokens are added
     *  @dev    Occcurs when quote tokens are being added
     *  @param  fromBucket_ The given bucket whose assets are being reallocated / moved
     *  @param  toBucket_   The given bucket where assets are being reallocated / moved
     *  @param  amount_     The amount of quote tokens requiring reallocation, WAD
     *  @param  inflator_   The current pool inflator rate, RAY
     *  @return lup_        The price to which assets were reallocated
     */
    function reallocateUpFromBucket(
        Bucket memory fromBucket_, Bucket memory toBucket_, uint256 amount_, uint256 inflator_
    ) private returns (uint256 lup_) {

        uint256 curPrice = lup;
        uint256 pdAdd;
        uint256 pdRemove;

        Bucket memory curLup;
        bool isFromBucket;

        while (true) {
            if (curPrice == toBucket_.price) break; // reached deposit bucket; nowhere to go
            isFromBucket = curPrice == fromBucket_.price;

            if (isFromBucket) { // use from bucket loaded in memory
                curLup     = fromBucket_;
            } else {
                curLup      = _buckets[curPrice];
                curLup.debt = accumulateBucketInterest(curLup.debt, curLup.inflatorSnapshot, inflator_);

                curLup.inflatorSnapshot = inflator_;
            }

            if (amount_ > curLup.debt) {
                toBucket_.debt      += curLup.debt;
                toBucket_.onDeposit -= curLup.debt;
                pdRemove             += Maths.wmul(curLup.debt, toBucket_.price);
                curLup.onDeposit     += curLup.debt;
                pdAdd                += Maths.wmul(curLup.debt, curPrice);
                amount_             -= curLup.debt;
                curLup.debt          = 0;

                if (!isFromBucket) _buckets[curPrice] = curLup;

                if (curPrice == curLup.up) break; // reached top-of-book; nowhere to go

            } else {
                toBucket_.debt      += amount_;
                toBucket_.onDeposit -= amount_;
                pdRemove             += Maths.wmul(amount_, toBucket_.price);
                curLup.debt          -= amount_;
                curLup.onDeposit     += amount_;
                pdAdd                += Maths.wmul(amount_, curPrice);

                if (!isFromBucket) _buckets[curPrice] = curLup;

                break;
            }

            curPrice = curLup.up;
        }

        lup_ = curPrice;
        pdAccumulator = pdAccumulator + pdAdd - pdRemove;
    }


    /*****************************/
    /*** Public View Functions ***/
    /*****************************/

    function bipAt(uint256 price_) public view override returns (uint256) {
        return _bip[price_];
    }

    function bucketAt(uint256 price_)
        public
        view
        override
        returns (
            uint256 bucketPrice_,
            uint256 up_,
            uint256 down_,
            uint256 onDeposit_,
            uint256 debt_,
            uint256 bucketInflator_,
            uint256 lpOutstanding_,
            uint256 bucketCollateral_
        )
    {
        Bucket memory bucket = _buckets[price_];

        bucketPrice_      = bucket.price;
        up_               = bucket.up;
        down_             = bucket.down;
        onDeposit_        = bucket.onDeposit;
        debt_             = bucket.debt;
        bucketInflator_   = bucket.inflatorSnapshot;
        lpOutstanding_    = bucket.lpOutstanding;
        bucketCollateral_ = bucket.collateral;
    }

    function estimatePrice(uint256 amount_, uint256 hpb_) public view override returns (uint256 price_) {
        Bucket memory curLup = _buckets[hpb_];

        while (true) {
            if (amount_ > curLup.onDeposit) {
                amount_ -= curLup.onDeposit;
            } else if (amount_ <= curLup.onDeposit) {
                price_ = curLup.price;
                break;
            }

            if (curLup.down == 0) {
                break;
            } else {
                curLup = _buckets[curLup.down];
            }
        }
    }

    function getHpb() public view override returns (uint256 newHpb_) {
        newHpb_ = hpb;
        while (true) {
            (, , uint256 down, uint256 onDeposit, uint256 debt, , , ) = bucketAt(newHpb_);
            if (onDeposit != 0 || debt != 0) {
                break;
            } else if (down == 0) {
                newHpb_ = 0;
                break;
            }
            newHpb_ = down;
        }
    }

    function getHup() public view override returns (uint256 hup_) {
        hup_ = lup;
        while (true) {
            (uint256 price, , uint256 down, uint256 onDeposit, , , , ) = bucketAt(hup_);

            if (price == down || onDeposit != 0) break;

            // check that there are available quote tokens on deposit in down bucket
            (, , , uint256 downAmount, , , , ) = bucketAt(down);

            if (downAmount == 0) break;

            hup_ = down;
        }
    }

    function isBucketInitialized(uint256 price_) public view override returns (bool) {
        return BitMaps.get(_bitmap, price_);
    }

    /*******************************/
    /*** Private View Functions ***/
    /*******************************/

    /**
     *  @notice Calculate the current exchange rate for Quote tokens / LP Tokens
     *  @dev    Performs calculations in RAY terms and rounds up to determine size to minimize precision loss
     *  @return RAY The current rate at which quote tokens can be exchanged for LP tokens
     */
    function getExchangeRate(Bucket memory bucket_) private pure returns (uint256) {
        uint256 size = bucket_.onDeposit + bucket_.debt + Maths.wmul(bucket_.collateral, bucket_.price);
        return (size != 0 && bucket_.lpOutstanding != 0) ? Maths.wrdivr(size, bucket_.lpOutstanding) : Maths.ONE_RAY;
    }

}
