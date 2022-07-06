// SPDX-License-Identifier: MIT

pragma solidity 0.8.14;

import { Clone } from "@clones/Clone.sol";

import { ERC20 }     from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { IPool } from "../base/interfaces/IPool.sol";

import { BucketMath } from "../libraries/BucketMath.sol";
import { Maths }      from "../libraries/Maths.sol";

// Added
import { BitMaps } from "@openzeppelin/contracts/utils/structs/BitMaps.sol";

abstract contract Pool is IPool, Clone {

    using SafeERC20 for ERC20;

    /***********************/
    /*** State Variables ***/
    /***********************/

    /** @dev Used for tracking LP token ownership structs for transferLPTokens access control */
    mapping(address => LpTokenOwnership) public lpTokenOwnership;

    uint256 public constant PENALTY_BPS         = 0.001 * 1e18;
    uint256 public constant SECONDS_PER_DAY     = 86_400;
    uint256 public constant SECONDS_PER_YEAR    = 86_400 * 365;
    uint256 public constant SECONDS_PER_HALFDAY = 43_200;
    uint256 public constant WAD_WEEKS_PER_YEAR  = 52 * 1e18;

    uint256 public constant RATE_INCREASE_COEFFICIENT = 1.1 * 1e18;
    uint256 public constant RATE_DECREASE_COEFFICIENT = 0.9 * 1e18;

    uint256 public constant LAMBDA_EMA      = 0.905723664263906671 * 1e18; // lambda used for the EMAs calculated as exp(-1/7 * ln2)
    uint256 public constant EMA_RATE_FACTOR = 1e18 - LAMBDA_EMA;

    /// @dev Counter used by onlyOnce modifier
    uint256 internal _poolInitializations = 0;

    mapping(uint256 => uint256) internal _bip;

    /**
     *  @notice Mapping of buckets for a given pool
     *  @dev price [WAD] -> bucket
     */
    mapping(uint256 => Bucket) internal _buckets;

    BitMaps.BitMap internal _bitmap;

    uint256 public          debtEma;                     // [WAD]  // TODO: Override
    uint256 public override inflatorSnapshot;            // [RAY]
    uint256 public override interestRate;                // [WAD]
    uint256 public override interestRateUpdate;          // [SEC]
    uint256 public override hpb;                         // [WAD]
    uint256 public override lastInflatorSnapshotUpdate;  // [SEC]
    uint256 public override lup;                         // [WAD]
    uint256 public          lupColEma;                   // [WAD]  // TODO: Override
    uint256 public override minFee;                      // [WAD]
    uint256 public override pdAccumulator;               // [WAD]
    uint256 public override quoteTokenScale;             // [N/A]
    uint256 public          totalBorrowers;              // [N/A]  // TODO: Override
    uint256 public override totalCollateral;             // [WAD]
    uint256 public          totalDebt;                   // [WAD]  // TODO: Override
    uint256 public override totalQuoteToken;             // [WAD]

    mapping(address => mapping(uint256 => uint256)) public override lpBalance;
    mapping(address => mapping(uint256 => uint256)) public lpTimer;  // TODO: override

    /*********************************/
    /*** Lender External Functions ***/
    /*********************************/

    function addQuoteToken(
        uint256 amount_, uint256 price_
    ) external override returns (uint256 lpTokens_) {
        require(BucketMath.isValidPrice(price_), "P:AQT:INVALID_PRICE");

        (uint256 curDebt, uint256 curInflator) = _accumulatePoolInterest(totalDebt, inflatorSnapshot);
        require(amount_ > _poolMinDebtAmount(curDebt, totalBorrowers), "P:AQT:AMT_LT_AVG_DEBT");

        // deposit quote token amount and get awarded LP tokens
        lpTokens_ = _addQuoteTokenToBucket(price_, amount_, curDebt, curInflator);

        // pool level accounting
        totalQuoteToken += amount_;

        // lender accounting
        lpBalance[msg.sender][price_] += lpTokens_;
        lpTimer[msg.sender][price_]   = block.timestamp;

        _updateInterestRate(curDebt);

        // move quote token amount from lender to pool
        quoteToken().safeTransferFrom(msg.sender, address(this), amount_ / quoteTokenScale);
        emit AddQuoteToken(msg.sender, price_, amount_, lup);
    }

    function moveQuoteToken(
        uint256 maxAmount_, uint256 fromPrice_, uint256 toPrice_
    ) external override {
        require(BucketMath.isValidPrice(toPrice_), "P:MQT:INVALID_TO_PRICE");
        require(fromPrice_ != toPrice_, "P:MQT:SAME_PRICE");

        (uint256 curDebt, uint256 curInflator) = _accumulatePoolInterest(totalDebt, inflatorSnapshot);

        // move quote tokens between buckets and get LP tokens
        (uint256 fromLpTokens, uint256 toLpTokens, uint256 movedAmount) = _moveQuoteTokenFromBucket(
            fromPrice_, toPrice_, maxAmount_, lpBalance[msg.sender][fromPrice_], lpTimer[msg.sender][fromPrice_], curInflator
        );
        require(_poolCollateralization(curDebt) >= Maths.WAD, "P:MQT:POOL_UNDER_COLLAT");

        // lender accounting
        lpBalance[msg.sender][fromPrice_] -= fromLpTokens;
        lpBalance[msg.sender][toPrice_]   += toLpTokens;

        _updateInterestRate(curDebt);

        emit MoveQuoteToken(msg.sender, fromPrice_, toPrice_, movedAmount, lup);
    }

    function removeQuoteToken(uint256 maxAmount_, uint256 price_, uint256 lpTokensToRemove) external override returns (uint256, uint256) {
        require(BucketMath.isValidPrice(price_), "P:RQT:INVALID_PRICE");

        (uint256 curDebt, uint256 curInflator) = _accumulatePoolInterest(totalDebt, inflatorSnapshot);

        // remove quote token amount and get LP tokens burned
        (uint256 amount, uint256 lpTokens) = _removeQuoteTokenFromBucket(
            price_, maxAmount_, lpTokensToRemove, lpTimer[msg.sender][price_], curInflator
        );
        require(_poolCollateralization(curDebt) >= Maths.WAD, "P:RQT:POOL_UNDER_COLLAT");

        // pool level accounting
        totalQuoteToken -= amount;

        // lender accounting
        lpBalance[msg.sender][price_] -= lpTokens;

        _updateInterestRate(curDebt);

        // move quote token amount from pool to lender
        uint256 scaledAmount = amount / quoteTokenScale;
        quoteToken().safeTransfer(msg.sender, scaledAmount);
        emit RemoveQuoteToken(msg.sender, price_, amount, lup);
        return (scaledAmount, lpTokens);
    }

    function approveNewPositionOwner(address owner_, address allowedNewOwner_) external {
        require(msg.sender == owner_, "P:ANPO:NOT_OWNER");

        LpTokenOwnership storage tokenOwnership = lpTokenOwnership[owner_];

        tokenOwnership.owner = owner_;
        tokenOwnership.allowedNewOwner = allowedNewOwner_;

        lpTokenOwnership[owner_] = tokenOwnership;
    }

    function transferLPTokens(address owner_, address newOwner_, uint256[] calldata prices_) external {
        require(lpTokenOwnership[owner_].owner == owner_ && lpTokenOwnership[owner_].allowedNewOwner == newOwner_, "P:TLT:NOT_OWNER");

        uint256 tokensTransferred;

        uint256 pricesLength = prices_.length;
        for (uint256 i = 0; i < pricesLength; ) {
            require(BucketMath.isValidPrice(prices_[i]), "P:TLT:INVALID_PRICE");

            // calculate lp tokens to be moved in the given bucket
            uint256 tokensToTransfer = lpBalance[owner_][prices_[i]];

            // move lp tokens to the new owners address
            delete lpBalance[owner_][prices_[i]];
            lpBalance[newOwner_][prices_[i]] += tokensToTransfer;

            tokensTransferred += tokensToTransfer;

            unchecked {
                ++i;
            }
        }

        emit TransferLPTokens(owner_, newOwner_, prices_, tokensTransferred);
    }

    /**********************************/
    /*** Internal Utility Functions ***/
    /**********************************/

    /**
     *  @notice Update the global borrower inflator
     *  @dev    Requires time to have passed between update calls
     */
    function _accumulatePoolInterest(uint256 totalDebt_, uint256 inflator_) internal returns (uint256 curDebt_, uint256 curInflator_) {
        uint256 elapsed  = block.timestamp - lastInflatorSnapshotUpdate;
        if (elapsed != 0) {
            curInflator_ = _pendingInflator(interestRate, inflator_, elapsed);                 // RAY
            curDebt_     = totalDebt_ + _pendingInterest(totalDebt_, curInflator_, inflator_); // WAD

            totalDebt                  = curDebt_;
            inflatorSnapshot           = curInflator_; // RAY
            lastInflatorSnapshotUpdate = block.timestamp;
        } else {
            curInflator_ = inflator_;
            curDebt_     = totalDebt_;
        }
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
        bucket.debt             = _accumulateBucketInterest(bucket.debt, bucket.inflatorSnapshot, inflator_);
        bucket.inflatorSnapshot = inflator_;

        lpTokens_ = Maths.rdiv(Maths.wadToRay(amount_), _exchangeRate(bucket));

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
            uint256 curDebt         = _accumulateBucketInterest(curLup.debt, curLup.inflatorSnapshot, inflator_);
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
     *  @notice Removes state for an unused bucket and update surrounding price pointers
     *  @param  bucket_ The price bucket to deactivate.
     */
    function _deactivateBucket(Bucket memory bucket_) internal {
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
     *  @notice Called by a lender to move quote tokens from a bucket
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
        fromBucket.debt             = _accumulateBucketInterest(fromBucket.debt, fromBucket.inflatorSnapshot, inflator_);
        fromBucket.inflatorSnapshot = inflator_;

        uint256 exchangeRate = _exchangeRate(fromBucket);                 // RAY
        uint256 claimable    = Maths.rmul(lpBalance_, exchangeRate);       // RAY

        amount_       = Maths.min(Maths.wadToRay(maxAmount_), claimable); // RAY
        lpRedemption_ = Maths.rdiv(amount_, exchangeRate);                // RAY
        amount_       = Maths.rayToWad(amount_);

        Bucket memory toBucket    = _buckets[toPrice_];
        toBucket.debt             = _accumulateBucketInterest(toBucket.debt, toBucket.inflatorSnapshot, inflator_);
        toBucket.inflatorSnapshot = inflator_;

        // apply bid penalty if deposit happened less than 24h ago
        if (fromBucket.price > toBucket.price && block.timestamp - lpTimer_ < SECONDS_PER_DAY) {
            uint256 penalty        = Maths.wmul(PENALTY_BPS, fromBucket.price - toBucket.price);
            amount_                -= penalty;
            _bip[fromBucket.price] += penalty;
        }

        lpAward_ = Maths.rdiv(Maths.wadToRay(amount_), _exchangeRate(toBucket));

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
        if (isEmpty && noClaim) _deactivateBucket(fromBucket); // cleanup if bucket no longer used
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
    function _reallocateDown(
        Bucket memory bucket_, uint256 amount_, uint256 inflator_
    ) internal returns (uint256 lup_) {

        lup_ = bucket_.price;
        // debt reallocation
        if (amount_ > bucket_.onDeposit) {
            uint256 pdRemove;
            uint256 reallocation = amount_ - bucket_.onDeposit;
            if (bucket_.down != 0) {
                uint256 toPrice = bucket_.down;

                while (true) {
                    Bucket storage toBucket   = _buckets[toPrice];
                    uint256 toDebt            = _accumulateBucketInterest(toBucket.debt, toBucket.inflatorSnapshot, inflator_);
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
        bucket.debt             = _accumulateBucketInterest(bucket.debt, bucket.inflatorSnapshot, inflator_);
        bucket.inflatorSnapshot = inflator_;

        uint256 exchangeRate = _exchangeRate(bucket);                  // RAY
        uint256 claimable    = Maths.rmul(lpBalance_, exchangeRate);   // RAY
        amount_             = Maths.min(Maths.wadToRay(maxAmount_), claimable); // RAY
        lpTokens_           = Maths.rdiv(amount_, exchangeRate);                // RAY
        amount_             = Maths.rayToWad(amount_);

        // bucket accounting
        uint256 removeFromDeposit = Maths.min(amount_, bucket.onDeposit); // Remove from deposit first
        bucket.onDeposit     -= removeFromDeposit;
        bucket.lpOutstanding -= lpTokens_;

        // debt reallocation
        uint256 newLup = _reallocateDown(bucket, amount_ - removeFromDeposit, inflator_);
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
        if (isEmpty && noClaim) _deactivateBucket(bucket); // cleanup if bucket no longer used
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
            uint256 curDebt = _accumulateBucketInterest(curLup.debt, curLup.inflatorSnapshot, inflator_);
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

    function _updateInterestRate(uint256 curDebt_) internal {
        uint256 poolCollateralization = _poolCollateralization(curDebt_);
        if (block.timestamp - interestRateUpdate > SECONDS_PER_HALFDAY && poolCollateralization > Maths.WAD) {
            uint256 oldRate = interestRate;

            uint256 curDebtEma   = Maths.wmul(curDebt_, EMA_RATE_FACTOR) + Maths.wmul(debtEma, LAMBDA_EMA);
            uint256 curLupColEma = Maths.wmul(Maths.wmul(lup, totalCollateral), EMA_RATE_FACTOR) + Maths.wmul(lupColEma, LAMBDA_EMA);

            int256 actualUtilization = int256(_poolActualUtilization(curDebt_));
            int256 targetUtilization = int256(Maths.wdiv(curDebtEma, curLupColEma));

            int256 decreaseFactor = 4 * (targetUtilization - actualUtilization);
            int256 increaseFactor = ((targetUtilization + actualUtilization - 10**18) ** 2) / 10**18;

            if (decreaseFactor < increaseFactor - 10**18) {
                interestRate = Maths.wmul(interestRate, RATE_INCREASE_COEFFICIENT);
            } else if (decreaseFactor > 10**18 - increaseFactor) {
                interestRate = Maths.wmul(interestRate, RATE_DECREASE_COEFFICIENT);
            }

            debtEma   = curDebtEma;
            lupColEma = curLupColEma;

            interestRateUpdate = block.timestamp;

            emit UpdateInterestRate(oldRate, interestRate);
        }
    }

    /*********************************/
    /*** Private Utility Functions ***/
    /*********************************/

    // TODO: Investigate making internal
    /**
     *  @notice Set state for a new bucket and update surrounding price pointers
     *  @param  hpb_   The current highest price bucket of the pool, WAD
     *  @param  price_ The price of the bucket to retrieve information from, WAD
     *  @return The new HPB given the newly initialized bucket
     */
    function initializeBucket(uint256 hpb_, uint256 price_) private returns (uint256) {
        Bucket storage bucket = _buckets[price_];

        bucket.price            = price_;
        bucket.inflatorSnapshot = Maths.RAY;

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
            newLup_ = _reallocateDown(fromBucket_, debtToMove, inflator_);
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
                        toBucket.debt = _accumulateBucketInterest(toBucket.debt, toBucket.inflatorSnapshot, inflator_);

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
            uint256 curLupDebt    = _accumulateBucketInterest(curLup.debt, curLup.inflatorSnapshot, inflator_);

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
                curLup.debt = _accumulateBucketInterest(curLup.debt, curLup.inflatorSnapshot, inflator_);

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

    // IBorrowerManager
    function getBorrowerCollateralization(uint256 collateralDeposited_, uint256 debt_) public view /*override*/ returns (uint256) {
        if (lup != 0 && debt_ != 0) {
            return Maths.wrdivw(collateralDeposited_, getEncumberedCollateral(debt_));
        }
        return Maths.WAD;
    }

    function getEncumberedCollateral(uint256 debt_) public view override returns (uint256) {
        // Calculate encumbrance as RAY to maintain precision
        return _encumberedCollateral(debt_);
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

    function getLPTokenExchangeValue(uint256 lpTokens_, uint256 price_) external view override returns (uint256 collateralTokens_, uint256 quoteTokens_) {
        require(BucketMath.isValidPrice(price_), "P:GLPTEV:INVALID_PRICE");

        ( , , , uint256 onDeposit, uint256 debt, , uint256 lpOutstanding, uint256 bucketCollateral) = bucketAt(price_);

        // calculate lpTokens share of all outstanding lpTokens for the bucket
        uint256 lenderShare = Maths.rdiv(lpTokens_, lpOutstanding);

        // calculate the amount of collateral and quote tokens equivalent to the lenderShare
        collateralTokens_ = Maths.radToWad(bucketCollateral * lenderShare);
        quoteTokens_      = Maths.radToWad((onDeposit + debt) * lenderShare);
    }

    function getMinimumPoolPrice() public view override returns (uint256) {
        return totalDebt != 0 ? Maths.wdiv(totalDebt, totalCollateral) : 0;
    }

    function getPendingBucketInterest(uint256 price_) external view returns (uint256 interest_) {
        (, , , , uint256 debt, uint256 bucketInflator, , ) = bucketAt(price_);
        return debt != 0 ? _pendingInterest(debt, getPendingInflator(), bucketInflator) : 0;
    }

    function getPendingInflator() public view returns (uint256) {
        return _pendingInflator(interestRate, inflatorSnapshot, block.timestamp - lastInflatorSnapshotUpdate);
    }

    function getPendingPoolInterest() external view returns (uint256) {
        return totalDebt != 0 ? _pendingInterest(totalDebt, getPendingInflator(), inflatorSnapshot) : 0;
    }

    function getPoolActualUtilization() public view override returns (uint256) {
        return _poolActualUtilization(totalDebt);
    }

    function getPoolCollateralization() public view override returns (uint256) {
        return _poolCollateralization(totalDebt);
    }

    function getPoolMinDebtAmount() public view override returns (uint256) {
        return _poolMinDebtAmount(totalDebt, totalBorrowers);
    }

    function getPoolTargetUtilization() public view override returns (uint256) {
        return _poolTargetUtilization(debtEma, lupColEma);
    }

    // IBorrowerManager
    function estimatePrice(uint256 amount_) public view /*override*/ returns (uint256) {
        return _estimatePrice(amount_, lup == 0 ? hpb : lup);
    }

    /*******************************/
    /*** Internal View Functions ***/
    /*******************************/

    function _encumberedCollateral(uint256 debt_) internal view returns (uint256) {
        // Calculate encumbrance as RAY to maintain precision
        return debt_ != 0 ? Maths.wwdivr(debt_, lup) : 0;
    }

    function _estimatePrice(uint256 amount_, uint256 hpb_) internal view returns (uint256 price_) {
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

    /**
     *  @notice Calculate the current exchange rate for Quote tokens / LP Tokens
     *  @dev    Performs calculations in RAY terms and rounds up to determine size to minimize precision loss
     *  @return RAY The current rate at which quote tokens can be exchanged for LP tokens
     */
    function _exchangeRate(Bucket memory bucket_) internal pure returns (uint256) {
        uint256 size = bucket_.onDeposit + bucket_.debt + Maths.wmul(bucket_.collateral, bucket_.price);
        return (size != 0 && bucket_.lpOutstanding != 0) ? Maths.wrdivr(size, bucket_.lpOutstanding) : Maths.RAY;
    }

    function _poolActualUtilization(uint256 totalDebt_) internal view returns (uint256) {
        if (totalDebt_ != 0) {
            uint256 lupMulDebt = Maths.wmul(lup, totalDebt_);
            return Maths.wdiv(lupMulDebt, lupMulDebt + pdAccumulator);
        }
        return 0;
    }

    function _poolCollateralization(uint256 totalDebt_) internal view returns (uint256) {
        if (totalDebt_ != 0) {
            return Maths.wrdivw(totalCollateral, Maths.wwdivr(totalDebt_, lup));
        }
        return Maths.WAD;
    }

    /*****************************/
    /*** Public Pure Functions ***/
    /*****************************/

    /**
     *  @dev Pure function used to facilitate accessing token via clone state.
     */
    function quoteToken() public pure returns (ERC20) {
        return ERC20(_getArgAddress(0x14));
    }

    function quoteTokenAddress() external pure returns (address) {
        return _getArgAddress(0x14);
    }

    /*******************************/
    /*** Internal Pure Functions ***/
    /*******************************/

    /**
     *  @notice Update bucket.debt with interest accumulated since last state change
     *  @param debt_         Current ucket debt bucket being updated
     *  @param inflator_     RAY - The current bucket inflator value
     *  @param poolInflator_ RAY - The current pool inflator value
     */
    // TODO: Investigate making this update storage
    function _accumulateBucketInterest(uint256 debt_, uint256 inflator_, uint256 poolInflator_) internal pure returns (uint256){
        if (debt_ != 0) {
            // To preserve precision, multiply WAD * RAY = RAD, and then scale back down to WAD
            debt_ += Maths.radToWadTruncate(
                debt_ * (Maths.rdiv(poolInflator_, inflator_) - Maths.RAY)
            );
        }
        return debt_;
    }

    /**
     *  @notice Calculate the pending inflator
     *  @param  interestRate_    WAD - The current interest rate value.
     *  @param  inflator_        RAY - The current inflator value
     *  @param  elapsed_         Seconds since last inflator update
     *  @return pendingInflator_ WAD - The pending inflator value
     */
    function _pendingInflator(uint256 interestRate_, uint256 inflator_, uint256 elapsed_) internal pure returns (uint256) {
        // Calculate annualized interest rate
        uint256 spr = Maths.wadToRay(interestRate_) / SECONDS_PER_YEAR;
        // secondsSinceLastUpdate is unscaled
        return Maths.rmul(inflator_, Maths.rpow(Maths.RAY + spr, elapsed_));
    }

    /**
     *  @notice Calculate the amount of unaccrued interest for a specified amount of debt
     *  @param  debt_            WAD - A debt amount (pool, bucket, or borrower)
     *  @param  pendingInflator_ RAY - The next debt inflator value
     *  @param  currentInflator_ RAY - The current debt inflator value
     *  @return interest_        WAD - The additional debt pending accumulation
     */
    function _pendingInterest(uint256 debt_, uint256 pendingInflator_, uint256 currentInflator_) internal pure returns (uint256) {
        // To preserve precision, multiply WAD * RAY = RAD, and then scale back down to WAD
        return Maths.radToWadTruncate(debt_ * (Maths.rdiv(pendingInflator_, currentInflator_) - Maths.RAY));
    }

    function _poolMinDebtAmount(uint256 totalDebt_, uint256 totalBorrowers_) internal pure returns (uint256) {
        return totalDebt_ != 0 ? Maths.wdiv(totalDebt_, Maths.wad(Maths.max(1000, totalBorrowers_ * 10))) : 0;
    }

    function _poolTargetUtilization(uint256 debtEma_, uint256 lupColEma_) internal pure returns (uint256) {
        if (debtEma_ != 0 && lupColEma_ != 0) {
            return Maths.wdiv(debtEma_, lupColEma_);
        }
        return Maths.WAD;
    }


}
