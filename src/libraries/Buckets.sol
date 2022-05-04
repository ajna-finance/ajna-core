// SPDX-License-Identifier: MIT

pragma solidity 0.8.11;

import "./Maths.sol";

library Buckets {

    error NoDepositToReallocateTo();
    error InsufficientLpBalance(uint256 balance);
    error BorrowPriceBelowStopPrice(uint256 borrowPrice);
    error ClaimExceedsCollateral(uint256 collateralAmount);
    error InsufficientBucketLiquidity(uint256 amountAvailable);

    struct Bucket {
        uint256 price; // WAD current bucket price
        uint256 up; // WAD upper utilizable bucket price
        uint256 down; // WAD next utilizable bucket price
        uint256 onDeposit; // RAD quote token on deposit in bucket
        uint256 debt; // RAD accumulated bucket debt
        uint256 inflatorSnapshot; // RAY bucket inflator snapshot
        uint256 lpOutstanding; // RAY outstanding Liquidity Provider LP tokens in a bucket
        uint256 collateral; // RAY Current collateral tokens deposited in the bucket
    }

    /// @notice Called by a lender to add quote tokens to a bucket
    /// @param buckets_ Mapping of buckets for a given pool
    /// @param price_ The price bucket to which quote tokens should be added
    /// @param amount_ The amount of quote tokens to be added
    /// @param lup_ The current pool LUP
    /// @param inflator_ The current pool inflator rate
    /// @param reallocate_ Boolean to check if assets need to be reallocated
    /// @return newLup_ The new pool LUP
    /// @return lpTokens_ The amount of lpTokens received by the lender for the added quote tokens
    function addQuoteToken(
        mapping(uint256 => Bucket) storage buckets_,
        uint256 price_,
        uint256 amount_,
        uint256 lup_,
        uint256 inflator_,
        bool reallocate_
    ) public returns (uint256 newLup_, uint256 lpTokens_) {
        Bucket storage bucket = buckets_[price_];

        accumulateBucketInterest(bucket, inflator_);

        lpTokens_ = Maths.rdiv(Maths.radToRay(amount_), getExchangeRate(bucket));
        bucket.lpOutstanding += lpTokens_;
        bucket.onDeposit     += amount_;

        newLup_ = lup_;
        if (reallocate_) {
            newLup_ = reallocateUp(buckets_, bucket, amount_, lup_, inflator_);
        }
    }

    /// @notice Called by a lender to remove quote tokens from a bucket
    /// @param buckets_ Mapping of buckets for a given pool
    /// @param bucket_ The price bucket from which quote tokens should be removed
    /// @param maxAmount_ The maximum amount of quote tokens to be removed
    /// @param lpBalance_ The lender's current LP balance
    /// @param inflator_ The current pool inflator rate
    /// @return amount_ The actual amount being removed
    /// @return lup_ The new pool LUP
    /// @return lpTokens_ The amount of lpTokens removed equivalent to the quote tokens removed
    function removeQuoteToken(
        mapping(uint256 => Bucket) storage buckets_,
        Bucket storage bucket_,
        uint256 maxAmount_, // RAD
        uint256 lpBalance_, // RAY
        uint256 inflator_ // RAY
    ) public returns (uint256 amount_, uint256 lup_, uint256 lpTokens_) {
        accumulateBucketInterest(bucket_, inflator_);

        uint256 exchangeRate = getExchangeRate(bucket_);
        uint256 claimable    = Maths.rayToRad(Maths.rmul(lpBalance_, exchangeRate));

        amount_   = Maths.min(maxAmount_, claimable);
        lpTokens_ = Maths.rdiv(Maths.radToRay(amount_), exchangeRate);

        // Remove from deposit first
        uint256 removeFromDeposit = Maths.min(amount_, bucket_.onDeposit);
        bucket_.onDeposit -= removeFromDeposit;

        // Reallocate debt to fund remaining withdrawal
        lup_ = reallocateDown(buckets_, bucket_, amount_ - removeFromDeposit, inflator_);

        bucket_.lpOutstanding -= lpTokens_;
    }

    /// @notice Called by a lender to claim accumulated collateral
    /// @param buckets_ Mapping of buckets for a given pool
    /// @param price_ The price bucket from which collateral should be claimed
    /// @param amount_ The amount of collateral tokens to be claimed
    /// @param lpBalance_ The claimers current LP balance
    /// @return lpRedemption_ The amount of LP tokens that will be redeemed
    function claimCollateral(
        mapping(uint256 => Bucket) storage buckets_,
        uint256 price_, // WAD
        uint256 amount_, // RAY
        uint256 lpBalance_ // RAY
    ) public returns (uint256 lpRedemption_) {
        Bucket storage bucket = buckets_[price_];

        if (amount_ > bucket.collateral) {
            revert ClaimExceedsCollateral({collateralAmount: bucket.collateral});
        }

        lpRedemption_ = Maths.rdiv(Maths.rmul(amount_, Maths.wadToRay(bucket.price)), getExchangeRate(bucket));
        if (lpRedemption_ > lpBalance_) {
            revert InsufficientLpBalance({balance: lpBalance_});
        }

        bucket.collateral    -= amount_;
        bucket.lpOutstanding -= lpRedemption_;
    }

    /// @notice Called by a borrower to borrow from a given bucket
    /// @param buckets_ Mapping of buckets for a given pool
    /// @param amount_ The amount of quote tokens to borrow from the bucket
    /// @param stop_ The lowest price desired to borrow at
    /// @param lup_ The current pool LUP
    /// @param inflator_ The current pool inflator rate
    /// @return lup WAD The price at which the borrow executed
    function borrow(
        mapping(uint256 => Bucket) storage buckets_,
        uint256 amount_, // RAD
        uint256 stop_, // WAD
        uint256 lup_, // WAD
        uint256 inflator_ // RAY
    ) public returns (uint256) {
        Bucket storage curLup = buckets_[lup_];

        while (true) {
            if (curLup.price < stop_) {
                revert BorrowPriceBelowStopPrice({borrowPrice: curLup.price});
            }

            // accumulate bucket interest
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

            // move to next bucket
            curLup = buckets_[curLup.down];
        }

        if (lup_ > curLup.price || lup_ == 0) {
            lup_ = curLup.price;
        }

        return lup_;
    }

    /// @notice Called by a borrower to repay quote tokens as part of reducing their position
    /// @param buckets_ Mapping of buckets for a given pool
    /// @param amount_ The amount of quote tokens to repay to the bucket
    /// @param lup_ The current pool LUP
    /// @param inflator_ The current pool inflator rate
    /// @return The new pool LUP
    function repay(
        mapping(uint256 => Bucket) storage buckets_,
        uint256 amount_,   // RAD
        uint256 lup_,      // WAD
        uint256 inflator_  // RAY
    ) public returns (uint256) {
        Bucket storage curLup = buckets_[lup_];

        while (true) {
            // accumulate bucket interest
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

            if (curLup.price == curLup.up) {
                // nowhere to go
                break;
            }
            // move to upper bucket
            curLup = buckets_[curLup.up];
        }

        return curLup.price;
    }

    /// @notice Puchase a given amount of quote tokens for given collateral tokens
    /// @param buckets_ Mapping of buckets for a given pool
    /// @param bucket_ The price bucket at which the exchange will occur
    /// @param amount_ The amount of quote tokens to receive
    /// @param collateral_ The amount of collateral to exchange
    /// @param inflator_ The current pool inflator rate
    /// @return lup_ The new pool LUP
    function purchaseBid(
        mapping(uint256 => Bucket) storage buckets_,
        Bucket storage bucket_,
        uint256 amount_, // RAD
        uint256 collateral_, // RAY
        uint256 inflator_ // RAY
    ) public returns (uint256 lup_) {
        accumulateBucketInterest(bucket_, inflator_);

        uint256 available = Maths.add(bucket_.onDeposit, bucket_.debt);
        if (amount_ > available) {
            revert InsufficientBucketLiquidity({amountAvailable: available});
        }

        // Exchange collateral for quote token on deposit
        uint256 purchaseFromDeposit = Maths.min(amount_, bucket_.onDeposit);

        bucket_.onDeposit -= purchaseFromDeposit;
        amount_          -= purchaseFromDeposit;

        // Reallocate debt to exchange for collateral
        lup_ = reallocateDown(buckets_, bucket_, amount_, inflator_);

        bucket_.collateral += collateral_;
    }

    /// @notice Liquidate a given position's collateral
    /// @param buckets_ Mapping of buckets for a given pool
    /// @param debt_ The amount of debt to cover
    /// @param collateral_ The amount of collateral deposited
    /// @param hpb_ The pool's highest price bucket
    /// @param inflator_ The current pool inflator rate
    /// @return requiredCollateral_ The amount of collateral to be liquidated
    function liquidate(
        mapping(uint256 => Bucket) storage buckets_,
        uint256 debt_, // RAD
        uint256 collateral_, // RAY
        uint256 hpb_, // WAD
        uint256 inflator_ // RAY
    ) public returns (uint256 requiredCollateral_) {
        Bucket storage bucket = buckets_[hpb_];

        while (true) {
            accumulateBucketInterest(bucket, inflator_);
            uint256 bucketDebtToPurchase = Maths.min(debt_, bucket.debt);

            uint256 debtByPriceRay = Maths.rdiv(
                Maths.radToRay(debt_),
                Maths.wadToRay(bucket.price)
            );
            uint256 bucketRequiredCollateral = Maths.min(
                Maths.min(debtByPriceRay, collateral_),
                debtByPriceRay
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

            bucket = buckets_[bucket.down];
        }
    }

    /// @notice Moves assets in a bucket to a bucket's down pointers
    /// @dev Occurs when quote tokens are being removed
    /// @dev Should continue until all of the desired quote tokens have been removed
    /// @param buckets_ Mapping of buckets for a given pool
    /// @param bucket_ The given bucket whose assets are being reallocated
    /// @param amount_ The amount of quote tokens requiring reallocation
    /// @param inflator_ The current pool inflator rate
    /// @return lup_ The price to which assets were reallocated
    function reallocateDown(
        mapping(uint256 => Bucket) storage buckets_,
        Bucket storage bucket_,
        uint256 amount_, // RAD
        uint256 inflator_ // RAY
    ) private returns (uint256 lup_) {
        lup_ = bucket_.price;
        // debt reallocation
        if (amount_ > bucket_.onDeposit) {
            uint256 reallocation = amount_ - bucket_.onDeposit;
            if (bucket_.down != 0) {
                Bucket storage toBucket = buckets_[bucket_.down];

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
                        if (reallocation != 0) {
                            revert NoDepositToReallocateTo();
                        }
                        lup_ = toBucket.price;
                        break;
                    }

                    toBucket = buckets_[toBucket.down];
                }
            } else {
                // lup started at the bottom
                if (reallocation != 0) {
                    revert NoDepositToReallocateTo();
                }
            }
        }
    }

    /// @notice Moves assets in a bucket to a bucket's up pointers
    /// @dev Should continue until all desired quote tokens are added
    /// @dev Occcurs when quote tokens are being added
    /// @param buckets_ Mapping of buckets for a given pool
    /// @param bucket_ The given bucket whose assets are being reallocated
    /// @param amount_ The amount of quote tokens requiring reallocation
    /// @param lup_ The current pool lup
    /// @param inflator_ The current pool inflator rate
    /// @return The price to which assets were reallocated
    function reallocateUp(
        mapping(uint256 => Bucket) storage buckets_,
        Bucket storage bucket_,
        uint256 amount_,
        uint256 lup_,
        uint256 inflator_ // RAY
    ) private returns (uint256) {
        Bucket storage curLup = buckets_[lup_];

        uint256 curLupDebt;

        while (true) {
            if (curLup.price == bucket_.price) {
                // reached deposit bucket; nowhere to go
                break;
            }

            // accumulate bucket interest
            accumulateBucketInterest(curLup, inflator_);

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

            curLup = buckets_[curLup.up];
        }

        return curLup.price;
    }

    /// @notice Update bucket.debt with interest accumulated since last state change
    /// @param bucket_ The bucket being updated
    /// @param inflator_ RAY - The current bucket inflator value
    function accumulateBucketInterest(Bucket storage bucket_, uint256 inflator_) private {
        if (bucket_.debt != 0) {
            bucket_.debt += Maths.rayToRad(
                Maths.rmul(
                    Maths.radToRay(bucket_.debt),
                    Maths.sub(Maths.rdiv(inflator_, bucket_.inflatorSnapshot), Maths.ONE_RAY)
                )
            );
            bucket_.inflatorSnapshot = inflator_;
        }
    }

    /// @notice Estimate the price at which a loan can be taken
    /// @param buckets_ Mapping of buckets for a given pool
    /// @param amount_ The amount of quote tokens desired to borrow
    /// @param hpb_ The current highest price bucket of the pool
    function estimatePrice(
        mapping(uint256 => Bucket) storage buckets_,
        uint256 amount_,
        uint256 hpb_
    ) public view returns (uint256) {
        Bucket memory curLup = buckets_[hpb_];

        while (true) {
            if (amount_ > curLup.onDeposit) {
                amount_ -= curLup.onDeposit;
            } else if (amount_ <= curLup.onDeposit) {
                return curLup.price;
            }

            if (curLup.down == 0) {
                return 0;
            } else {
                curLup = buckets_[curLup.down];
            }
        }

        return 0;
    }

    /// @notice Return the information of the bucket at a given price
    /// @param buckets_ Mapping of buckets for a given pool
    /// @param price_ The price of the bucket to retrieve information from
    function bucketAt(mapping(uint256 => Bucket) storage buckets_, uint256 price_)
        public
        view
        returns (
            uint256 price,
            uint256 up,
            uint256 down,
            uint256 onDeposit,
            uint256 debt,
            uint256 inflatorSnapshot,
            uint256 lpOutstanding,
            uint256 collateral
        )
    {
        Bucket memory bucket = buckets_[price_];

        price            = bucket.price;
        up               = bucket.up;
        down             = bucket.down;
        onDeposit        = bucket.onDeposit;
        debt             = bucket.debt;
        inflatorSnapshot = bucket.inflatorSnapshot;
        lpOutstanding    = bucket.lpOutstanding;
        collateral       = bucket.collateral;
    }

    // TODO: replace + with Maths.add()
    /// @notice Calculate the current exchange rate for Quote tokens / LP Tokens
    /// @dev Performs calculations in RAY terms and rounds up to determine size to minimize precision loss
    /// @return RAY The current rate at which quote tokens can be exchanged for LP tokens
    function getExchangeRate(Bucket storage bucket_) internal view returns (uint256) {
        uint256 size = bucket_.onDeposit +
            bucket_.debt +
            Maths.rayToRad(Maths.rmul(bucket_.collateral, Maths.wadToRay(bucket_.price)));
        if (size != 0 && bucket_.lpOutstanding != 0) {
            return Maths.rdiv(Maths.radToRay(size), bucket_.lpOutstanding);
        }
        return Maths.ONE_RAY;
    }

    /// @notice Set state for a new bucket and update surrounding price pointers
    /// @param buckets_ Mapping of buckets for a given pool
    /// @param hpb_ The current highest price bucket of the pool
    /// @param price_ The price of the bucket to retrieve information from
    /// @return The new HPB given the newly initialized bucket
    function initializeBucket(
        mapping(uint256 => Bucket) storage buckets_,
        uint256 hpb_,
        uint256 price_
    ) public returns (uint256) {
        Bucket storage bucket = buckets_[price_];

        bucket.price            = price_;
        bucket.inflatorSnapshot = Maths.ONE_RAY;

        if (price_ > hpb_) {
            bucket.down = hpb_;
            hpb_ = price_;
        }

        uint256 cur  = hpb_;
        uint256 down = buckets_[hpb_].down;
        uint256 up   = buckets_[hpb_].up;

        // update price pointers
        while (true) {
            if (price_ > down) {
                buckets_[cur].down = price_;
                bucket.up          = cur;
                bucket.down        = down;
                buckets_[down].up  = price_;
                break;
            }
            cur  = down;
            down = buckets_[cur].down;
            up   = buckets_[cur].up;
        }
        return hpb_;
    }

}
