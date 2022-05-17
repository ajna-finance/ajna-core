// SPDX-License-Identifier: MIT

pragma solidity 0.8.11;

import "../libraries/Maths.sol";

abstract contract Buckets {

    /**
     *  @notice Mapping of buckets for a given pool
     *  @dev    price [WAD] -> bucket
     */
    mapping(uint256 => Buckets.Bucket) internal _buckets;

    /**
     *  @notice struct holding bucket info
     *  @param  price current bucket price, WAD
     *  @param  up upper utilizable bucket price, WAD
     *  @param  down next utilizable bucket price, WAD
     *  @param  onDeposit quote token on deposit in bucket, WAD
     *  @param  debt accumulated bucket debt, WAD
     *  @param  inflatorSnapshot bucket inflator snapshot, RAY
     *  @param  lpOutstanding outstanding Liquidity Provider LP tokens in a bucket, RAY
     *  @param  collateral urrent collateral tokens deposited in the bucket, RAY
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
     *  @notice Raised when there is no bucket to reallocate debt to.
     */
    error NoDepositToReallocateTo();

    /**
     *  @notice Amount of LP tokens needed to be redeemed for claimed collateral is greater than claimer's balance.
     *  @param  balance Claimer's LP tokens balance.
     */
    error InsufficientLpBalance(uint256 balance);

    /**
     *  @notice Loan cannot be executed at a price greater than desired limit price.
     *  @param  borrowPrice The price below limit price.
     */
    error BorrowPriceBelowLimitPrice(uint256 borrowPrice);

    /**
     *  @notice The amount of collateral to be claimed exceeds available collateral in bucket.
     *  @param  collateralAmount Available collateral in bucket.
     */
    error ClaimExceedsCollateral(uint256 collateralAmount);

    /**
     *  @notice The amount of quote tokens to receive when purchse bid is greater than amount in bucket.
     *  @param  amountAvailable Amount of quote tokens in bucket.
     */
    error InsufficientBucketLiquidity(uint256 amountAvailable);

    /**
     *  @notice Called by a lender to add quote tokens to a bucket
     *  @param  price_      The price bucket to which quote tokens should be added
     *  @param  amount_     The amount of quote tokens to be added
     *  @param  lup_        The current pool LUP
     *  @param  inflator_   The current pool inflator rate
     *  @param  reallocate_ Boolean to check if assets need to be reallocated
     *  @return newLup_     The new pool LUP
     *  @return lpTokens_   The amount of lpTokens received by the lender for the added quote tokens
     */
    function addQuoteTokenToBucket(
        uint256 price_, uint256 amount_, uint256 lup_, uint256 inflator_, bool reallocate_
    ) public returns (uint256 newLup_, uint256 lpTokens_) {
        Bucket storage bucket = _buckets[price_];

        // accumulate bucket interest
        if (bucket.debt != 0) {
            bucket.debt = calculateBucketInterest(bucket.debt, bucket.inflatorSnapshot, inflator_);
            bucket.inflatorSnapshot = inflator_;
        }

        lpTokens_ = Maths.rdiv(
            Maths.wadToRay(amount_),
            calculateExchangeRate(bucket.price, bucket.onDeposit, bucket.debt, bucket.collateral, bucket.lpOutstanding)
        );
        bucket.lpOutstanding += lpTokens_;
        bucket.onDeposit     += amount_;

        newLup_ = lup_;
        if (reallocate_) {
            newLup_ = reallocateUp(bucket, amount_, lup_, inflator_);
        }
    }

    /**
     *  @notice Called by a lender to remove quote tokens from a bucket
     *  @param  bucket_    The price bucket from which quote tokens should be removed
     *  @param  maxAmount_ The maximum amount of quote tokens to be removed, WAD
     *  @param  lpBalance_ The LP balance for current lender, RAY
     *  @param  inflator_  The current pool inflator rate, RAY
     *  @return amount_    The actual amount being removed
     *  @return lup_       The new pool LUP
     *  @return lpTokens_  The amount of lpTokens removed equivalent to the quote tokens removed
     */
    function removeQuoteTokenFromBucket(
        Bucket memory bucket_, uint256 maxAmount_, uint256 lpBalance_, uint256 inflator_
    ) public returns (uint256 amount_, uint256 lup_, uint256 lpTokens_) {

        // accumulate bucket interest
        if (bucket_.debt != 0) {
            bucket_.debt = calculateBucketInterest(bucket_.debt, bucket_.inflatorSnapshot, inflator_);
            bucket_.inflatorSnapshot = inflator_;
        }

        uint256 exchangeRate = calculateExchangeRate(
            bucket_.price, bucket_.onDeposit, bucket_.debt, bucket_.collateral, bucket_.lpOutstanding
        );                                                             // RAY
        uint256 claimable    = Maths.rmul(lpBalance_, exchangeRate);  // RAY

        amount_ = Maths.min(Maths.wadToRay(maxAmount_), claimable);   // RAY
        lpTokens_ = Maths.rdiv(amount_, exchangeRate);                // RAY
        amount_ = Maths.rayToWad(amount_);

        // Remove from deposit first
        uint256 removeFromDeposit = Maths.min(amount_, bucket_.onDeposit);
        bucket_.onDeposit -= removeFromDeposit;

        // Reallocate debt to fund remaining withdrawal
        lup_ = reallocateDown(bucket_, amount_ - removeFromDeposit, inflator_);

        bucket_.lpOutstanding -= lpTokens_;
        // save bucket to storage
        _buckets[bucket_.price] = bucket_;
    }

    /**
     *  @notice Called by a lender to claim accumulated collateral
     *  @param  bucket_       The price bucket from which collateral should be claimed
     *  @param  amount_       The amount of collateral tokens to be claimed, WAD
     *  @param  lpBalance_    The claimers current LP balance, RAY
     *  @return lpRedemption_ The amount of LP tokens that will be redeemed
     */
    function claimCollateralFromBucket(
        Bucket memory bucket_, uint256 amount_, uint256 lpBalance_
    ) public returns (uint256 lpRedemption_) {

        if (amount_ > bucket_.collateral) {
            revert ClaimExceedsCollateral({collateralAmount: bucket_.collateral});
        }

        lpRedemption_ = Maths.wrdivr(
            Maths.wmul(amount_, bucket_.price),
            calculateExchangeRate(bucket_.price, bucket_.onDeposit, bucket_.debt, bucket_.collateral, bucket_.lpOutstanding)
        );

        if (lpRedemption_ > lpBalance_) {
            revert InsufficientLpBalance({balance: lpBalance_});
        }

        bucket_.collateral    -= amount_;
        bucket_.lpOutstanding -= lpRedemption_;
        // save bucket to storage
        _buckets[bucket_.price] = bucket_;
    }

    /**
     *  @notice Called by a borrower to borrow from a given bucket
     *  @param  amount_   The amount of quote tokens to borrow from the bucket, WAD
     *  @param  limit_    The lowest price desired to borrow at, WAD
     *  @param  lup_      The current pool LUP, WAD
     *  @param  inflator_ The current pool inflator rate, RAY
     *  @return lup WAD The price at which the borrow executed
     */
    function borrowFromBucket(
        uint256 amount_, uint256 limit_, uint256 lup_, uint256 inflator_
    ) public returns (uint256) {
        Bucket storage curLup = _buckets[lup_];

        while (true) {
            if (curLup.price < limit_) {
                revert BorrowPriceBelowLimitPrice({borrowPrice: curLup.price});
            }

            // accumulate bucket interest
            if (curLup.debt != 0) {
                curLup.debt = calculateBucketInterest(curLup.debt, curLup.inflatorSnapshot, inflator_);
            }
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

            // move to next bucket
            curLup = _buckets[curLup.down];
        }

        if (lup_ > curLup.price || lup_ == 0) {
            lup_ = curLup.price;
        }

        return lup_;
    }

    /**
     *  @notice Called by a borrower to repay quote tokens as part of reducing their position
     *  @param  amount_   The amount of quote tokens to repay to the bucket, WAD
     *  @param  lup_      The current pool LUP, WAD
     *  @param  inflator_ The current pool inflator rate, RAY
     *  @return The new pool LUP
     */
    function repayBucket(uint256 amount_, uint256 lup_, uint256 inflator_) public returns (uint256) {
        Bucket storage curLup = _buckets[lup_];

        while (true) {
            // accumulate bucket interest
            if (curLup.debt != 0) {
                curLup.debt = calculateBucketInterest(curLup.debt, curLup.inflatorSnapshot, inflator_);
                curLup.inflatorSnapshot = inflator_;

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

            if (curLup.price == curLup.up) {
                // nowhere to go
                break;
            }
            // move to upper bucket
            curLup = _buckets[curLup.up];
        }

        return curLup.price;
    }

    /**
     *  @notice Puchase a given amount of quote tokens for given collateral tokens
     *  @param  bucket_     The price bucket at which the exchange will occur, WAD
     *  @param  amount_     The amount of quote tokens to receive, WAD
     *  @param  collateral_ The amount of collateral to exchange, WAD
     *  @param  inflator_   The current pool inflator rate, RAY
     *  @return lup_        The new pool LUP
     */
    function purchaseBidFromBucket(
        Bucket memory bucket_, uint256 amount_, uint256 collateral_, uint256 inflator_
    ) public returns (uint256 lup_) {

        // accumulate bucket interest
        if (bucket_.debt != 0) {
            // To preserve precision, multiply WAD * RAY = RAD, and then scale back down to WAD
            bucket_.debt += Maths.radToWadTruncate(
                bucket_.debt * (Maths.rdiv(inflator_, bucket_.inflatorSnapshot) - Maths.ONE_RAY)
            );
            bucket_.inflatorSnapshot = inflator_;
        }

        uint256 available = bucket_.onDeposit + bucket_.debt;
        if (amount_ > available) {
            revert InsufficientBucketLiquidity({amountAvailable: available});
        }

        // Exchange collateral for quote token on deposit
        uint256 purchaseFromDeposit = Maths.min(amount_, bucket_.onDeposit);

        bucket_.onDeposit -= purchaseFromDeposit;
        amount_           -= purchaseFromDeposit;

        // Reallocate debt to exchange for collateral
        lup_ = reallocateDown(bucket_, amount_, inflator_);

        bucket_.collateral += collateral_;
        // save bucket to storage
        _buckets[bucket_.price] = bucket_;
    }

    /**
     *  @notice Liquidate a given position's collateral
     *  @param  debt_               The amount of debt to cover, WAD
     *  @param  collateral_         The amount of collateral deposited, WAD
     *  @param  hpb_                The pool's highest price bucket, WAD
     *  @param  inflator_           The current pool inflator rate, RAY
     *  @return requiredCollateral_ The amount of collateral to be liquidated
     */
    function liquidateAtBucket(
        uint256 debt_, uint256 collateral_, uint256 hpb_, uint256 inflator_
    ) public returns (uint256 requiredCollateral_) {
        Bucket storage bucket = _buckets[hpb_];

        while (true) {
            // accumulate bucket interest
            if (bucket.debt != 0) {
                bucket.debt = calculateBucketInterest(bucket.debt, bucket.inflatorSnapshot, inflator_);
                bucket.inflatorSnapshot = inflator_;
            }
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

            // stop if all debt reconciliated
            if (debt_ == 0) {
                break;
            }

            bucket = _buckets[bucket.down];
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
            uint256 reallocation = amount_ - bucket_.onDeposit;
            if (bucket_.down != 0) {
                Bucket storage toBucket = _buckets[bucket_.down];

                while (true) {
                    // accumulate bucket interest
                    if (toBucket.debt != 0) {
                        toBucket.debt = calculateBucketInterest(toBucket.debt, toBucket.inflatorSnapshot, inflator_);
                        toBucket.inflatorSnapshot = inflator_;
                    }

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
                        if (reallocation != 0) {
                            revert NoDepositToReallocateTo();
                        }
                        lup_ = toBucket.price;
                        break;
                    }

                    toBucket = _buckets[toBucket.down];
                }
            } else {
                // lup started at the bottom
                if (reallocation != 0) {
                    revert NoDepositToReallocateTo();
                }
            }
        }
    }

    /**
     *  @notice Moves assets in a bucket to a bucket's up pointers
     *  @dev    Should continue until all desired quote tokens are added
     *  @dev    Occcurs when quote tokens are being added
     *  @param  bucket_   The given bucket whose assets are being reallocated
     *  @param  amount_   The amount of quote tokens requiring reallocation, WAD
     *  @param  lup_      The current pool lup, WAD
     *  @param  inflator_ The current pool inflator rate, RAY
     *  @return The price to which assets were reallocated
     */
    function reallocateUp(
        Bucket storage bucket_, uint256 amount_, uint256 lup_, uint256 inflator_
    ) private returns (uint256) {
        Bucket storage curLup = _buckets[lup_];

        uint256 curLupDebt;

        while (true) {
            if (curLup.price == bucket_.price) {
                // reached deposit bucket; nowhere to go
                break;
            }

            // accumulate bucket interest
            if (curLup.debt != 0) {
                curLup.debt = calculateBucketInterest(curLup.debt, curLup.inflatorSnapshot, inflator_);
                curLup.inflatorSnapshot = inflator_;
            }

            curLupDebt = curLup.debt;

            if (amount_ > curLupDebt) {
                bucket_.debt      += curLupDebt;
                bucket_.onDeposit -= curLupDebt;
                curLup.debt       = 0;
                curLup.onDeposit  += curLupDebt;
                amount_           -= curLupDebt;

                if (curLup.price == curLup.up) {
                    // reached top-of-book; nowhere to go
                    break;
                }
            } else {
                bucket_.debt      += amount_;
                bucket_.onDeposit -= amount_;
                curLup.debt       -= amount_;
                curLup.onDeposit  += amount_;
                break;
            }

            curLup = _buckets[curLup.up];
        }

        return curLup.price;
    }

    /**
     *  @notice Update bucket.debt with interest accumulated since last state change
     *  @param  bucketDebt_       The bucket debt
     *  @param  inflatorSnapshot_ The bucket inflator snapshot
     *  @param  inflator_         RAY - The current bucket inflator value
     *  @return debt_             New calculated debt
     */
    function calculateBucketInterest(
        uint256 bucketDebt_, uint256 inflatorSnapshot_, uint256 inflator_)
    private pure returns (uint256 debt_) {
        debt_ = bucketDebt_ + Maths.radToWadTruncate(
            bucketDebt_ * (Maths.rdiv(inflator_, inflatorSnapshot_) - Maths.ONE_RAY)
        );
    }

    /**
     *  @notice Estimate the price at which a loan can be taken
     *  @param amount_ The amount of quote tokens desired to borrow, WAD
     *  @param hpb_    The current highest price bucket of the pool, WAD
     */
    function estimatePrice(uint256 amount_, uint256 hpb_) public view returns (uint256) {
        Bucket memory curLup = _buckets[hpb_];

        while (true) {
            if (amount_ > curLup.onDeposit) {
                amount_ -= curLup.onDeposit;
            } else if (amount_ <= curLup.onDeposit) {
                return curLup.price;
            }

            if (curLup.down == 0) {
                return 0;
            } else {
                curLup = _buckets[curLup.down];
            }
        }

        return 0;
    }

    /**
     *  @notice Get a bucket struct for a given price.
     *  @param  price_             The price of the bucket to retrieve.
     *  @return bucketPrice_              The price of the bucket.
     *  @return up_                 The price of the next higher priced utlized bucket.
     *  @return down_               The price of the next lower price utilized bucket.
     *  @return onDeposit_          The amount of quote token available as liquidity in the bucket.
     *  @return debt_               The amount of quote token debt in the bucket.
     *  @return bucketInflator_   The inflator snapshot value in the bucket.
     *  @return lpOutstanding_      The amount of outstanding LP tokens in the bucket.
     *  @return bucketCollateral_         The amount of collateral posted in the bucket.
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
     *  @param  price_         Bucket price
     *  @param  onDeposit_     Bucket on deposit
     *  @param  debt_          Bucket debt
     *  @param  collateral_    Bucket collateral
     *  @param  lpOutstanding_ Outstansing LP tokens in bucket
     *  @return exchangeRate_  RAY The current rate at which quote tokens can be exchanged for LP tokens
     */
    function calculateExchangeRate(
        uint256 price_, uint256 onDeposit_, uint256 debt_, uint256 collateral_, uint256 lpOutstanding_
    ) internal pure returns (uint256 exchangeRate_) {
        uint256 size = onDeposit_ + debt_ + Maths.wmul(collateral_, price_);
        exchangeRate_ = (size != 0 && lpOutstanding_ != 0) ? Maths.wrdivr(size, lpOutstanding_) : Maths.ONE_RAY;    
    }

    /**
     *  @notice Set state for a new bucket and update surrounding price pointers
     *  @param  hpb_ The current highest price bucket of the pool, WAD
     *  @param  price_ The price of the bucket to retrieve information from, WAD
     *  @return The new HPB given the newly initialized bucket
     */
    function initializeBucket(uint256 hpb_, uint256 price_) public returns (uint256) {
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
        return hpb_;
    }

    /**
     *  @notice Removes state for an unused bucket and update surrounding price pointers
     *  @param  bucket_ The price bucket to deactivate
     */
    function deactivateBucket(Bucket memory bucket_) public {
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

}
