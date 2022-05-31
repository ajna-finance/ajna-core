// SPDX-License-Identifier: MIT
pragma solidity 0.8.11;

import { BitMaps } from "@openzeppelin/contracts/utils/structs/BitMaps.sol";

import { IBuckets } from "../interfaces/IBuckets.sol";

import "../libraries/Maths.sol";

abstract contract Buckets is IBuckets {

    /***********************/
    /*** State Variables ***/
    /***********************/

    /**
     *  @notice Mapping of buckets for a given pool
     *  @dev price [WAD] -> bucket
     */
    mapping(uint256 => Buckets.Bucket) internal _buckets;

    BitMaps.BitMap internal _bitmap;

    uint256 public override hpb;
    uint256 public override lup;
    uint256 public override pdAccumulator;

    /**********************************/
    /*** Internal Utility Functions ***/
    /**********************************/

    /**
     *  @notice Called by a lender to add quote tokens to a bucket
     *  @param  price_      The price bucket to which quote tokens should be added.
     *  @param  amount_     The amount of quote tokens to be added.
     *  @param  totalDebt_  The amount of total debt.
     *  @param  inflator_   The current pool inflator rate.
     *  @return lpTokens_   The amount of lpTokens received by the lender for the added quote tokens.
     */
    function addQuoteTokenToBucket(
        uint256 price_, uint256 amount_, uint256 totalDebt_, uint256 inflator_
    ) internal returns (uint256 lpTokens_) {
        // initialize bucket if required and get new HPB
        uint256 newHpb = !BitMaps.get(_bitmap, price_) ? initializeBucket(hpb, price_) : hpb;

        Bucket storage bucket = _buckets[price_];
        accumulateBucketInterest(bucket, inflator_);

        lpTokens_ = Maths.rdiv(Maths.wadToRay(amount_), getExchangeRate(bucket));

        // bucket accounting
        bucket.lpOutstanding += lpTokens_;
        bucket.onDeposit     += amount_;
        pdAccumulator        += Maths.wmul(amount_, price_);

        // debt reallocation
        bool reallocate = totalDebt_ != 0 && price_ > lup;
        uint256 newLup = reallocate ? reallocateUp(bucket, amount_, inflator_) : lup;

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
    function borrowFromBucket(uint256 amount_, uint256 fee_, uint256 limit_, uint256 inflator_) internal {
        // if first loan then borrow at HPB price, otherwise at LUP
        uint256 price = lup == 0 ? hpb : lup;
        Bucket storage curLup = _buckets[price];

        uint256 pdRemove;
        while (true) {
            require(curLup.price >= limit_, "B:B:PRICE_LT_LIMIT");

            accumulateBucketInterest(curLup, inflator_);
            curLup.inflatorSnapshot = inflator_;

            if (amount_ > curLup.onDeposit) {
                // take all on deposit from this bucket
                curLup.debt      += curLup.onDeposit;
                amount_         -= curLup.onDeposit;
                pdRemove         += Maths.wmul(curLup.onDeposit, curLup.price);
                curLup.onDeposit -= curLup.onDeposit;
            } else {
                // take all remaining amount for loan from this bucket and exit
                curLup.onDeposit -= amount_;
                pdRemove         += Maths.wmul(amount_, curLup.price);
                curLup.debt      += amount_ + fee_;
                break;
            }

            curLup = _buckets[curLup.down]; // move to next bucket
        }

        // HPB and LUP management
        lup = (price > curLup.price || price == 0) ? curLup.price : price;
        pdAccumulator -= pdRemove;
    }

    /**
     *  @notice Called by a lender to claim accumulated collateral
     *  @param  price_        The price bucket from which collateral should be claimed
     *  @param  amount_       The amount of collateral tokens to be claimed, WAD
     *  @param  lpBalance_    The claimers current LP balance, RAY
     *  @return lpRedemption_ The amount of LP tokens that will be redeemed
     */
    function claimCollateralFromBucket(
        uint256 price_, uint256 amount_, uint256 lpBalance_
    ) internal returns (uint256 lpRedemption_) {
        Bucket storage bucket = _buckets[price_];

        require(amount_ <= bucket.collateral, "B:CC:AMT_GT_COLLAT");

        lpRedemption_ = Maths.wrdivr(Maths.wmul(amount_, bucket.price), getExchangeRate(bucket));

        require(lpRedemption_ <= lpBalance_, "B:CC:INSUF_LP_BAL");

        // bucket accounting
        bucket.collateral    -= amount_;
        bucket.lpOutstanding -= lpRedemption_;

        // bucket management
        bool isEmpty = bucket.onDeposit == 0 && bucket.debt == 0;
        bool noClaim = bucket.lpOutstanding == 0 && bucket.collateral == 0;
        if (isEmpty && noClaim) deactivateBucket(bucket); // cleanup if bucket no longer used
    }

    /**
     *  @notice Liquidate a given position's collateral
     *  @param  debt_               The amount of debt to cover, WAD
     *  @param  collateral_         The amount of collateral deposited, WAD
     *  @param  inflator_           The current pool inflator rate, RAY
     *  @return requiredCollateral_ The amount of collateral to be liquidated
     */
    function liquidateAtBucket(
        uint256 debt_, uint256 collateral_, uint256 inflator_
    ) internal returns (uint256 requiredCollateral_) {
        Bucket storage bucket = _buckets[hpb];

        while (true) {
            accumulateBucketInterest(bucket, inflator_);
            uint256 bucketDebtToPurchase = Maths.min(debt_, bucket.debt);

            uint256 debtByPrice = Maths.wdiv(debt_, bucket.price);
            uint256 bucketRequiredCollateral = Maths.min(
                Maths.min(debtByPrice, collateral_),
                debtByPrice
            );

            debt_               -= bucketDebtToPurchase;
            collateral_         -= bucketRequiredCollateral;
            requiredCollateral_ += bucketRequiredCollateral;

            // bucket accounting
            bucket.debt       -= bucketDebtToPurchase;
            bucket.collateral += bucketRequiredCollateral;

            // forgive the debt when borrower has no remaining collateral but still has debt
            if (debt_ != 0 && collateral_ == 0) {
                bucket.debt = 0;
                break;
            }

            if (debt_ == 0) break; // stop if all debt reconciliated

            bucket = _buckets[bucket.down];
        }

        // HPB and LUP management
        uint256 newHpb = getHpb();
        if (hpb != newHpb) hpb = newHpb;
    }

    /**
     *  @notice Called by a lender to remove quote tokens from a bucket
     *  @param  fromPrice_    The price bucket from where quote tokens should be moved
     *  @param  toPrice_      The price bucket where quote tokens should be moved
     *  @param  amount_       The amount of quote tokens to be moved, WAD
     *  @param  lpBalance_    The LP balance for current lender, RAY
     *  @param  inflator_     The current pool inflator rate, RAY
     *  @return lpRedemption_ The amount of lpTokens moved from bucket
     *  @return lpAward_      The amount of lpTokens moved to bucket
     */
    function moveQuoteTokenFromBucket(
        uint256 fromPrice_, uint256 toPrice_, uint256 amount_, uint256 lpBalance_, uint256 inflator_
    ) internal returns (uint256 lpRedemption_, uint256 lpAward_) {
        uint256 newHpb = !BitMaps.get(_bitmap, toPrice_) ? initializeBucket(hpb, toPrice_) : hpb;
        uint256 newLup = lup;

        Bucket storage fromBucket = _buckets[fromPrice_];
        accumulateBucketInterest(fromBucket, inflator_);

        uint256 exchangeRate = getExchangeRate(fromBucket);
        lpRedemption_ = Maths.rdiv(Maths.wadToRay(amount_), exchangeRate);

        require(lpRedemption_ <= lpBalance_, "B:MQT:AMT_GT_CLAIM");

        Bucket storage toBucket = _buckets[toPrice_];
        accumulateBucketInterest(toBucket, inflator_);

        lpAward_ = Maths.rdiv(Maths.wadToRay(amount_), getExchangeRate(toBucket));

        // move LP tokens
        fromBucket.lpOutstanding -= lpRedemption_;
        toBucket.lpOutstanding   += lpAward_;

        bool moveUp = fromPrice_ < toPrice_;
        bool atLup  = newLup != 0 && fromPrice_ == newLup;

        if (atLup) {
            uint256 debtToMove    = (amount_ > fromBucket.onDeposit) ? amount_ - fromBucket.onDeposit : 0;
            uint256 depositToMove = amount_ - debtToMove;

            // move debt
            if (moveUp) {
                fromBucket.debt -= debtToMove;
                toBucket.debt   += debtToMove;
            }

            // move deposit
            uint256 toOnDeposit  = moveUp ? depositToMove : amount_;
            fromBucket.onDeposit -= depositToMove;
            toBucket.onDeposit   += toOnDeposit;

            newLup = moveUp ? reallocateUp(toBucket, depositToMove, inflator_) : reallocateDown(fromBucket, debtToMove, inflator_);
            pdAccumulator = pdAccumulator + Maths.wmul(toOnDeposit, toBucket.price) - Maths.wmul(depositToMove, fromBucket.price);
        } else {
            bool aboveLup = newLup !=0 && newLup < Maths.min(fromPrice_, toPrice_);
            if (aboveLup) {
                // move debt
                fromBucket.debt -= amount_;
                toBucket.debt   += amount_;
            } else {
                // move deposit
                uint256 fromOnDeposit = moveUp ? amount_ : Maths.min(amount_, fromBucket.onDeposit);
                fromBucket.onDeposit -= fromOnDeposit;
                toBucket.onDeposit   += amount_;

                if (newLup != 0 && toBucket.price > Maths.max(fromBucket.price, newLup)) newLup = reallocateUp(toBucket,  amount_, inflator_);
                else if (newLup != 0 && fromBucket.price >= Maths.max(toBucket.price, newLup)) newLup = reallocateDown(fromBucket, amount_, inflator_);
                pdAccumulator = pdAccumulator + Maths.wmul(amount_, toBucket.price) - Maths.wmul(fromOnDeposit, fromBucket.price);
            }
        }

        bool isEmpty = fromBucket.onDeposit == 0 && fromBucket.debt == 0;
        bool noClaim = fromBucket.lpOutstanding == 0 && fromBucket.collateral == 0;

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
    function purchaseBidFromBucket(
        uint256 price_, uint256 amount_, uint256 collateral_, uint256 inflator_
    ) internal {
        Bucket storage bucket = _buckets[price_];
        accumulateBucketInterest(bucket, inflator_);

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
        uint256 newHpb = (bucket.onDeposit == 0 && bucket.debt == 0) ? getHpb() : hpb;

        // HPB and LUP management
        if (lup != newLup) lup = newLup;
        if (hpb != newHpb) hpb = newHpb;

        pdAccumulator -= Maths.wmul(purchaseFromDeposit, bucket.price);
    }

    /**
     *  @notice Called by a lender to remove quote tokens from a bucket
     *  @param  price_     The price bucket from which quote tokens should be removed
     *  @param  maxAmount_ The maximum amount of quote tokens to be removed, WAD
     *  @param  lpBalance_ The LP balance for current lender, RAY
     *  @param  inflator_  The current pool inflator rate, RAY
     *  @return amount_    The actual amount being removed
     *  @return lpTokens_  The amount of lpTokens removed equivalent to the quote tokens removed
     */
    function removeQuoteTokenFromBucket(
        uint256 price_, uint256 maxAmount_, uint256 lpBalance_, uint256 inflator_
    ) internal returns (uint256 amount_, uint256 lpTokens_) {
        Bucket storage bucket = _buckets[price_];
        accumulateBucketInterest(bucket, inflator_);

        uint256 exchangeRate = getExchangeRate(bucket);                // RAY
        uint256 claimable    = Maths.rmul(lpBalance_, exchangeRate);   // RAY

        amount_   = Maths.min(Maths.wadToRay(maxAmount_), claimable); // RAY
        lpTokens_ = Maths.rdiv(amount_, exchangeRate);                // RAY
        amount_   = Maths.rayToWad(amount_);

        // bucket accounting
        uint256 removeFromDeposit = Maths.min(amount_, bucket.onDeposit); // Remove from deposit first
        bucket.onDeposit     -= removeFromDeposit;
        bucket.lpOutstanding -= lpTokens_;

        // debt reallocation
        uint256 newLup = reallocateDown(bucket, amount_ - removeFromDeposit, inflator_);
        pdAccumulator  -= Maths.wmul(removeFromDeposit, price_);

        bool isEmpty = bucket.onDeposit == 0 && bucket.debt == 0;
        bool noClaim = bucket.lpOutstanding == 0 && bucket.collateral == 0;

        // HPB and LUP management
        uint256 newHpb = (isEmpty && price_ == hpb) ? getHpb() : hpb;
        if (price_ >= lup && newLup < lup) lup = newLup; // move lup down only if removal happened at or above lup
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
    function repayBucket(uint256 amount_, uint256 inflator_, bool reconcile_) internal {
        Bucket storage curLup = _buckets[lup];

        uint256 pdAdd;

        while (true) {
            if (curLup.debt != 0) {
                accumulateBucketInterest(curLup, inflator_);

                if (amount_ > curLup.debt) {
                    // pay entire debt on this bucket
                    amount_         -= curLup.debt;
                    curLup.onDeposit += curLup.debt;
                    pdAdd            += Maths.wmul(curLup.debt, curLup.price);
                    curLup.debt      = 0;
                } else {
                    // pay as much debt as possible and exit
                    curLup.onDeposit += amount_;
                    pdAdd            += Maths.wmul(amount_, curLup.price);
                    curLup.debt      -= amount_;
                    amount_         = 0;
                    break;
                }
            }

            if (curLup.price == curLup.up) break; // nowhere to go

            curLup = _buckets[curLup.up]; // move to upper bucket
        }

        // HPB and LUP management
        if (reconcile_) lup = 0;                         // reset LUP if no debt in pool
        else if (lup != curLup.price) lup = curLup.price; // update LUP to current price

        pdAccumulator += pdAdd;
    }

    /*********************************/
    /*** Private Utility Functions ***/
    /*********************************/

    /**
     *  @notice Update bucket.debt with interest accumulated since last state change
     *  @param bucket_   The bucket being updated
     *  @param inflator_ RAY - The current bucket inflator value
     */
    function accumulateBucketInterest(Bucket storage bucket_, uint256 inflator_) private {
        if (bucket_.debt != 0) {
            // To preserve precision, multiply WAD * RAY = RAD, and then scale back down to WAD
            bucket_.debt += Maths.radToWadTruncate(
                bucket_.debt * (Maths.rdiv(inflator_, bucket_.inflatorSnapshot) - Maths.ONE_RAY)
            );
        }
        bucket_.inflatorSnapshot = inflator_;
    }

    /**
     *  @notice Removes state for an unused bucket and update surrounding price pointers
     *  @param  bucket_ The price bucket to deactivate.
     */
    function deactivateBucket(Bucket storage bucket_) private {
        BitMaps.setTo(_bitmap, bucket_.price, false);
        bool isHighestBucket = bucket_.price == bucket_.up;
        bool isLowestBucket = bucket_.down == 0;
        if (isHighestBucket && !isLowestBucket) {                     // if highest bucket
            _buckets[bucket_.down].up = _buckets[bucket_.down].price; // make lower bucket the highest bucket
        } else if (!isHighestBucket && !isLowestBucket) {             // if middle bucket
            _buckets[bucket_.up].down = bucket_.down;                 // update down pointer of upper bucket
            _buckets[bucket_.down].up = bucket_.up;                   // update up pointer of lower bucket
        } else if (!isHighestBucket && isLowestBucket) {              // if lowest bucket
            _buckets[bucket_.up].down = 0;                            // make upper bucket the lowest bucket
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
     *  @notice Moves assets in a bucket to a bucket's down pointers
     *  @dev    Occurs when quote tokens are being removed
     *  @dev    Should continue until all of the desired quote tokens have been removed
     *  @param  bucket_   The given bucket whose assets are being reallocated
     *  @param  amount_   The amount of quote tokens requiring reallocation, WAD
     *  @param  inflator_ The current pool inflator rate, RAY
     *  @return lup_      The price to which assets were reallocated
     */
    function reallocateDown(
        Bucket storage bucket_, uint256 amount_, uint256 inflator_
    ) private returns (uint256 lup_) {
        lup_ = bucket_.price;
        // debt reallocation
        if (amount_ > bucket_.onDeposit) {
            uint256 pdRemove;
            uint256 reallocation = amount_ - bucket_.onDeposit;
            if (bucket_.down != 0) {
                Bucket storage toBucket = _buckets[bucket_.down];

                while (true) {
                    accumulateBucketInterest(toBucket, inflator_);

                    if (reallocation < toBucket.onDeposit) {
                        // reallocate all and exit
                        bucket_.debt       -= reallocation;
                        toBucket.debt      += reallocation;
                        toBucket.onDeposit -= reallocation;
                        pdRemove           += Maths.wmul(reallocation, toBucket.price);
                        lup_ = toBucket.price;
                        break;
                    } else {
                        if (toBucket.onDeposit != 0) {
                            reallocation       -= toBucket.onDeposit;
                            bucket_.debt       -= toBucket.onDeposit;
                            toBucket.debt      += toBucket.onDeposit;
                            pdRemove           += Maths.wmul(toBucket.onDeposit, toBucket.price);
                            toBucket.onDeposit -= toBucket.onDeposit;
                        }
                    }

                    if (toBucket.down == 0) {
                        // last bucket, nowhere to go, guard against reallocation failures
                        require(reallocation == 0, "B:RD:NO_REALLOC_LOCATION");
                        lup_ = toBucket.price;
                        break;
                    }

                    toBucket = _buckets[toBucket.down];
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
        Bucket storage bucket_, uint256 amount_, uint256 inflator_
    ) private returns (uint256 lup_) {
        Bucket storage curLup = _buckets[lup];

        uint256 curLupDebt;
        uint256 pdAdd;
        uint256 pdRemove;

        while (true) {
            if (curLup.price == bucket_.price) break; // reached deposit bucket; nowhere to go

            accumulateBucketInterest(curLup, inflator_);

            curLupDebt = curLup.debt;

            if (amount_ > curLupDebt) {
                bucket_.debt      += curLupDebt;
                bucket_.onDeposit -= curLupDebt;
                pdRemove          += Maths.wmul(curLupDebt, bucket_.price);
                curLup.debt       = 0;
                curLup.onDeposit  += curLupDebt;
                pdAdd             += Maths.wmul(curLupDebt, curLup.price);
                amount_           -= curLupDebt;

                if (curLup.price == curLup.up) break; // reached top-of-book; nowhere to go

            } else {
                bucket_.debt      += amount_;
                bucket_.onDeposit -= amount_;
                pdRemove          += Maths.wmul(amount_, bucket_.price);
                curLup.debt       -= amount_;
                curLup.onDeposit  += amount_;
                pdAdd             += Maths.wmul(amount_, curLup.price);
                break;
            }

            curLup = _buckets[curLup.up];
        }

        lup_ = curLup.price;
        pdAccumulator = pdAccumulator + pdAdd - pdRemove;
    }

    /*****************************/
    /*** Public View Functions ***/
    /*****************************/

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
    /*** Internal View Functions ***/
    /*******************************/

    /**
     *  @notice Calculate the current exchange rate for Quote tokens / LP Tokens
     *  @dev    Performs calculations in RAY terms and rounds up to determine size to minimize precision loss
     *  @return RAY The current rate at which quote tokens can be exchanged for LP tokens
     */
    function getExchangeRate(Bucket storage bucket_) internal view returns (uint256) {
        uint256 size = bucket_.onDeposit + bucket_.debt + Maths.wmul(bucket_.collateral, bucket_.price);
        return (size != 0 && bucket_.lpOutstanding != 0) ? Maths.wrdivr(size, bucket_.lpOutstanding) : Maths.ONE_RAY;
    }

}
