// SPDX-License-Identifier: MIT

pragma solidity 0.8.11;

import { BitMaps } from "@openzeppelin/contracts/utils/structs/BitMaps.sol";

import "../libraries/Maths.sol";

abstract contract Buckets {

    /**
     *  @notice Mapping of buckets for a given pool
     *  @dev price [WAD] -> bucket
     */
    mapping(uint256 => Buckets.Bucket) internal _buckets;

    BitMaps.BitMap internal _bitmap;

    /**
     *  @notice The price value of the current Highest Price Bucket (HPB). WAD
     */
    uint256 public hpb;
    /**
     *  @notice The price value of the current Lowest Utilized Price (LUP) bucket. WAD
     */
    uint256 public lup;

    /**
     *  @notice struct holding bucket info
     *  @param price            Current bucket price, WAD
     *  @param up               Upper utilizable bucket price, WAD
     *  @param down             Next utilizable bucket price, WAD
     *  @param onDeposit        Quote token on deposit in bucket, WAD
     *  @param debt             Accumulated bucket debt, WAD
     *  @param inflatorSnapshot Bucket inflator snapshot, RAY
     *  @param lpOutstanding    Outstanding Liquidity Provider LP tokens in a bucket, RAY
     *  @param collateral       Current collateral tokens deposited in the bucket, RAY
     */
    struct Bucket {
        uint256 price;
        uint256 up;
        uint256 down;
        uint256 onDeposit;
        uint256 debt;
        uint256 inflatorSnapshot;
        uint256 lpOutstanding;
        uint256 collateral;
    }

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

        // debt reallocation
        bool reallocate = totalDebt_ != 0 && price_ > lup;
        uint256 newLup = reallocate ? reallocateUp(bucket, amount_, inflator_) : lup;

        // HPB and LUP management
        if (lup != newLup) lup = newLup;
        if (hpb != newHpb) hpb = newHpb;
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
     *  @notice Called by a borrower to borrow from a given bucket
     *  @param  amount_   The amount of quote tokens to borrow from the bucket, WAD
     *  @param  limit_    The lowest price desired to borrow at, WAD
     *  @param  inflator_ The current pool inflator rate, RAY
     */
    function borrowFromBucket(uint256 amount_, uint256 limit_, uint256 inflator_) internal {
        // if first loan then borrow at HPB price, otherwise at LUP
        uint256 price = lup == 0 ? hpb : lup;
        Bucket storage curLup = _buckets[price];

        while (true) {
            require(curLup.price >= limit_, "B:B:PRICE_LT_LIMIT");

            accumulateBucketInterest(curLup, inflator_);
            curLup.inflatorSnapshot = inflator_;

            if (amount_ > curLup.onDeposit) {
                // take all on deposit from this bucket
                curLup.debt      += curLup.onDeposit;
                amount_         -= curLup.onDeposit;
                curLup.onDeposit -= curLup.onDeposit;
            } else {
                // take all remaining amount for loan from this bucket and exit
                curLup.onDeposit -= amount_;
                curLup.debt      += amount_;
                break;
            }

            curLup = _buckets[curLup.down]; // move to next bucket
        }

        // HPB and LUP management
        lup = (price > curLup.price || price == 0) ? curLup.price : price;
    }

    /**
     *  @notice Called by a borrower to repay quote tokens as part of reducing their position
     *  @param  amount_       The amount of quote tokens to repay to the bucket, WAD
     *  @param  inflator_     The current pool inflator rate, RAY
     *  @param  reconcile_    True if all debt in pool is repaid
     */
    function repayBucket(uint256 amount_, uint256 inflator_, bool reconcile_) internal {
        Bucket storage curLup = _buckets[lup];

        while (true) {
            if (curLup.debt != 0) {
                accumulateBucketInterest(curLup, inflator_);

                if (amount_ > curLup.debt) {
                    // pay entire debt on this bucket
                    amount_         -= curLup.debt;
                    curLup.onDeposit += curLup.debt;
                    curLup.debt      = 0;
                } else {
                    // pay as much debt as possible and exit
                    curLup.onDeposit += amount_;
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
                        lup_ = toBucket.price;
                        break;
                    } else {
                        if (toBucket.onDeposit != 0) {
                            reallocation       -= toBucket.onDeposit;
                            bucket_.debt       -= toBucket.onDeposit;
                            toBucket.debt      += toBucket.onDeposit;
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

        while (true) {
            if (curLup.price == bucket_.price) break; // reached deposit bucket; nowhere to go

            accumulateBucketInterest(curLup, inflator_);

            curLupDebt = curLup.debt;

            if (amount_ > curLupDebt) {
                bucket_.debt      += curLupDebt;
                bucket_.onDeposit -= curLupDebt;
                curLup.debt       = 0;
                curLup.onDeposit  += curLupDebt;
                amount_           -= curLupDebt;

                if (curLup.price == curLup.up) break; // reached top-of-book; nowhere to go

            } else {
                bucket_.debt      += amount_;
                bucket_.onDeposit -= amount_;
                curLup.debt       -= amount_;
                curLup.onDeposit  += amount_;
                break;
            }

            curLup = _buckets[curLup.up];
        }

        lup_ = curLup.price;
    }

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
     *  @notice Estimate the price at which a loan can be taken
     *  @param  amount_ The amount of quote tokens desired to borrow, WAD
     *  @param  hpb_    The current highest price bucket of the pool, WAD
     *  @return price_  The estimated price at which the loan can be taken, WAD
     */
    function estimatePrice(uint256 amount_, uint256 hpb_) public view returns (uint256 price_) {
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
     *  @notice Get a bucket struct for a given price.
     *  @param  price_            The price of the bucket to retrieve.
     *  @return bucketPrice_      The price of the bucket.
     *  @return up_               The price of the next higher priced utlized bucket.
     *  @return down_             The price of the next lower price utilized bucket.
     *  @return onDeposit_        The amount of quote token available as liquidity in the bucket.
     *  @return debt_             The amount of quote token debt in the bucket.
     *  @return bucketInflator_   The inflator snapshot value in the bucket.
     *  @return lpOutstanding_    The amount of outstanding LP tokens in the bucket.
     *  @return bucketCollateral_ The amount of collateral posted in the bucket.
     */
    function bucketAt(uint256 price_)
        public
        view
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

    /**
     *  @notice Calculate the current exchange rate for Quote tokens / LP Tokens
     *  @dev    Performs calculations in RAY terms and rounds up to determine size to minimize precision loss
     *  @return exchangeRate_ RAY The current rate at which quote tokens can be exchanged for LP tokens
     */
    function getExchangeRate(Bucket storage bucket_) internal view returns (uint256 exchangeRate_) {
        uint256 size = bucket_.onDeposit + bucket_.debt + Maths.wmul(bucket_.collateral, bucket_.price);
        exchangeRate_ = (size != 0 && bucket_.lpOutstanding != 0) ? Maths.wrdivr(size, bucket_.lpOutstanding) : Maths.ONE_RAY;
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
     *  @notice Returns whether a bucket price has been initialized or not.
     *  @param  price_               The price of the bucket.
     *  @param  isBucketInitialized_ Boolean indicating if the bucket has been initialized at this price.
     */
    function isBucketInitialized(uint256 price_) public view returns (bool isBucketInitialized_) {
        return BitMaps.get(_bitmap, price_);
    }

    /**
     *  @notice Returns the current Highest Utilizable Price (HUP) bucket.
     *  @dev    Starting at the LUP, iterate through down pointers until no quote tokens are available.
     *  @dev    LUP should always be >= HUP.
     *  @return hup_ The current Highest Utilizable Price (HUP) bucket.
     */
    function getHup() public view returns (uint256 hup_) {
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

    /**
     *  @notice Returns the current Highest Price Bucket (HPB).
     *  @dev    Starting at the current HPB, iterate through down pointers until a new HPB found.
     *  @dev    HPB should have at on deposit or debt different than 0.
     *  @return newHpb_ The current Highest Price Bucket (HPB).
     */
    function getHpb() public view returns (uint256 newHpb_) {
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

}
