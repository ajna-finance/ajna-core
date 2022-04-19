// SPDX-License-Identifier: MIT

pragma solidity 0.8.11;

import "./Maths.sol";

library Buckets {
    error NoDepositToReallocateTo();
    error InsufficientLpBalance(uint256 balance);
    error AmountExceedsClaimable(uint256 rightToClaim);
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
    /// @param buckets Mapping of buckets for a given pool
    /// @param _price The price bucket to which quote tokens should be added
    /// @param _amount The amount of quote tokens to be added
    /// @param _lup The current pool LUP
    /// @param _inflator The current pool inflator rate
    /// @param _reallocate Boolean to check if assets need to be reallocated
    /// @return lup The new pool LUP
    /// @return lpTokens The amount of lpTokens received by the lender for the added quote tokens
    function addQuoteToken(
        mapping(uint256 => Bucket) storage buckets,
        uint256 _price,
        uint256 _amount,
        uint256 _lup,
        uint256 _inflator,
        bool _reallocate
    ) public returns (uint256 lup, uint256 lpTokens) {
        Bucket storage bucket = buckets[_price];

        accumulateBucketInterest(bucket, _inflator);

        lpTokens = Maths.rdiv(Maths.radToRay(_amount), getExchangeRate(bucket));
        bucket.lpOutstanding += lpTokens;
        bucket.onDeposit += _amount;

        lup = _lup;
        if (_reallocate) {
            lup = reallocateUp(buckets, bucket, _amount, _lup, _inflator);
        }
    }

    /// @notice Called by a lender to remove quote tokens from a bucket
    /// @param buckets Mapping of buckets for a given pool
    /// @param _price The price bucket from which quote tokens should be removed
    /// @param _amount The amount of quote tokens to be removed
    /// @param _lpBalance The lender's current LP balance
    /// @param _inflator The current pool inflator rate
    /// @return lup The new pool LUP
    /// @return lpTokens The amount of lpTokens removed equivalent to the quote tokens removed
    function removeQuoteToken(
        mapping(uint256 => Bucket) storage buckets,
        uint256 _price, // WAD
        uint256 _amount, // RAD
        uint256 _lpBalance, // RAY
        uint256 _inflator // RAY
    ) public returns (uint256 lup, uint256 lpTokens) {
        Bucket storage bucket = buckets[_price];

        accumulateBucketInterest(bucket, _inflator);

        uint256 exchangeRate = getExchangeRate(bucket);

        uint256 claimable = Maths.rayToRad(Maths.rmul(_lpBalance, exchangeRate));

        if (_amount > claimable) {
            revert AmountExceedsClaimable({rightToClaim: claimable});
        }

        lpTokens = Maths.rdiv(Maths.radToRay(_amount), exchangeRate);

        // Remove from deposit first
        uint256 removeFromDeposit = Maths.min(_amount, bucket.onDeposit);
        bucket.onDeposit -= removeFromDeposit;
        _amount -= removeFromDeposit;

        // Reallocate debt to fund remaining withdrawal
        lup = reallocateDown(buckets, bucket, _amount, _inflator);

        bucket.lpOutstanding -= lpTokens;
    }

    /// @notice Called by a lender to claim accumulated collateral
    /// @param buckets Mapping of buckets for a given pool
    /// @param _price The price bucket from which collateral should be claimed
    /// @param _amount The amount of collateral tokens to be claimed
    /// @param _lpBalance The claimers current LP balance
    /// @return lpRedemption The amount of LP tokens that will be redeemed
    function claimCollateral(
        mapping(uint256 => Bucket) storage buckets,
        uint256 _price, // WAD
        uint256 _amount, // RAY
        uint256 _lpBalance // RAY
    ) public returns (uint256 lpRedemption) {
        Bucket storage bucket = buckets[_price];

        if (_amount > bucket.collateral) {
            revert ClaimExceedsCollateral({collateralAmount: bucket.collateral});
        }

        uint256 exchangeRate = getExchangeRate(bucket);
        lpRedemption = Maths.rdiv(Maths.rmul(_amount, Maths.wadToRay(bucket.price)), exchangeRate);

        if (lpRedemption > _lpBalance) {
            revert InsufficientLpBalance({balance: _lpBalance});
        }

        bucket.collateral -= _amount;
        bucket.lpOutstanding -= lpRedemption;
    }

    /// @notice Called by a borrower to borrow from a given bucket
    /// @param _amount The amount of quote tokens to borrow from the bucket
    /// @param _stop The lowest price desired to borrow at
    /// @param _lup The current pool LUP
    /// @param _inflator The current pool inflator rate
    /// @return lup WAD The price at which the borrow executed
    /// @return loanCost RAD The amount of quote tokens removed from the bucket
    function borrow(
        mapping(uint256 => Bucket) storage buckets,
        uint256 _amount, // RAD
        uint256 _stop, // WAD
        uint256 _lup, // WAD
        uint256 _inflator // RAY
    ) public returns (uint256 lup, uint256 loanCost) {
        Bucket storage curLup = buckets[_lup];
        uint256 amountRemaining = _amount;

        while (true) {
            if (curLup.price < _stop) {
                revert BorrowPriceBelowStopPrice({borrowPrice: curLup.price});
            }

            // accumulate bucket interest
            accumulateBucketInterest(curLup, _inflator);
            curLup.inflatorSnapshot = _inflator;

            if (amountRemaining > curLup.onDeposit) {
                // take all on deposit from this bucket
                curLup.debt += curLup.onDeposit;
                amountRemaining -= curLup.onDeposit;
                loanCost += Maths.rayToRad(
                    Maths.rdiv(Maths.radToRay(curLup.onDeposit), Maths.wadToRay(curLup.price))
                );
                curLup.onDeposit -= curLup.onDeposit;
            } else {
                // take all remaining amount for loan from this bucket and exit
                curLup.onDeposit -= amountRemaining;
                curLup.debt += amountRemaining;
                loanCost += Maths.rayToRad(
                    Maths.rdiv(Maths.radToRay(amountRemaining), Maths.wadToRay(curLup.price))
                );
                break;
            }

            // move to next bucket
            curLup = buckets[curLup.down];
        }

        if (_lup > curLup.price || _lup == 0) {
            _lup = curLup.price;
        }

        return (_lup, loanCost);
    }

    /// @notice Called by a borrower to repay quote tokens as part of reducing their position
    /// @param buckets Mapping of buckets for a given pool
    /// @param _amount The amount of quote tokens to repay to the bucket
    /// @param _lup The current pool LUP
    /// @param _inflator The current pool inflator rate
    /// @return The new pool LUP
    /// @return The amount of quote tokens to be repaid
    function repay(
        mapping(uint256 => Bucket) storage buckets,
        uint256 _amount, // RAD
        uint256 _lup, // WAD
        uint256 _inflator // RAY
    ) public returns (uint256, uint256) {
        Bucket storage curLup = buckets[_lup];
        uint256 debtToPay;

        while (true) {
            // accumulate bucket interest
            if (curLup.debt != 0) {
                accumulateBucketInterest(curLup, _inflator);

                if (_amount > curLup.debt) {
                    // pay entire debt on this bucket
                    debtToPay += curLup.debt;
                    _amount -= curLup.debt;
                    curLup.onDeposit += curLup.debt;
                    curLup.debt = 0;
                } else {
                    // pay as much debt as possible and exit
                    curLup.onDeposit += _amount;
                    curLup.debt -= _amount;
                    debtToPay += _amount;
                    _amount = 0;
                    break;
                }
            }

            if (curLup.price == curLup.up) {
                // nowhere to go
                break;
            }
            // move to upper bucket
            curLup = buckets[curLup.up];
        }

        return (curLup.price, debtToPay);
    }

    /// @notice Puchase a given amount of quote tokens for given collateral tokens
    /// @param buckets Mapping of buckets for a given pool
    /// @param _price The price at which the exchange will occur
    /// @param _amount The amount of quote tokens to receive
    /// @param _collateral The amount of collateral to exchange
    /// @param _inflator The current pool inflator rate
    /// @return lup The new pool LUP
    function purchaseBid(
        mapping(uint256 => Bucket) storage buckets,
        uint256 _price, // WAD
        uint256 _amount, // RAD
        uint256 _collateral, // RAY
        uint256 _inflator // RAY
    ) public returns (uint256 lup) {
        Bucket storage bucket = buckets[_price];
        accumulateBucketInterest(bucket, _inflator);

        uint256 available = Maths.add(bucket.onDeposit, bucket.debt);
        if (_amount > available) {
            revert InsufficientBucketLiquidity({amountAvailable: available});
        }

        // Exchange collateral for quote token on deposit
        uint256 purchaseFromDeposit = Maths.min(_amount, bucket.onDeposit);
        bucket.onDeposit -= purchaseFromDeposit;
        _amount -= purchaseFromDeposit;

        // Reallocate debt to exchange for collateral
        lup = reallocateDown(buckets, bucket, _amount, _inflator);

        bucket.collateral += _collateral;
    }

    /// @notice Liquidate a given position's collateral
    /// @param buckets Mapping of buckets for a given pool
    /// @param _collateral The amount of collateral deposited
    /// @param _hdp The pool's HDP
    /// @param _inflator The current pool inflator rate
    /// @return requiredCollateral The amount of collateral to be liquidated
    function liquidate(
        mapping(uint256 => Bucket) storage buckets,
        uint256 _debt, // RAD
        uint256 _collateral, // RAY
        uint256 _hdp, // WAD
        uint256 _inflator // RAY
    ) public returns (uint256 requiredCollateral) {
        Bucket storage bucket = buckets[_hdp];

        while (true) {
            accumulateBucketInterest(bucket, _inflator);
            uint256 bucketDebtToPurchase = Maths.min(_debt, bucket.debt);

            uint256 debtByPriceRay = Maths.rdiv(
                Maths.radToRay(_debt),
                Maths.wadToRay(bucket.price)
            );
            uint256 bucketRequiredCollateral = Maths.min(
                Maths.min(debtByPriceRay, _collateral),
                debtByPriceRay
            );

            _debt -= bucketDebtToPurchase;
            _collateral -= bucketRequiredCollateral;
            requiredCollateral += bucketRequiredCollateral;

            // bucket accounting
            bucket.debt -= bucketDebtToPurchase;
            bucket.collateral += bucketRequiredCollateral;

            // forgive the debt when borrower has no remaining collateral but still has debt
            if (_debt != 0 && _collateral == 0) {
                bucket.debt = 0;
                break;
            }

            // stop if all debt reconciliated
            if (_debt == 0) {
                break;
            }

            bucket = buckets[bucket.down];
        }
    }

    /// @notice Moves assets in a bucket to a bucket's down pointers
    /// @dev Occurs when quote tokens are being removed
    /// @dev Should continue until all of the desired quote tokens have been removed
    /// @param buckets Mapping of buckets for a given pool
    /// @param _bucket The given bucket whose assets are being reallocated
    /// @param _amount The amount of quote tokens requiring reallocation
    /// @param _inflator The current pool inflator rate
    /// @return lup The price to which assets were reallocated
    function reallocateDown(
        mapping(uint256 => Bucket) storage buckets,
        Bucket storage _bucket,
        uint256 _amount, // RAD
        uint256 _inflator // RAY
    ) private returns (uint256 lup) {
        lup = _bucket.price;
        // debt reallocation
        if (_amount > _bucket.onDeposit) {
            uint256 reallocation = _amount - _bucket.onDeposit;
            if (_bucket.down != 0) {
                Bucket storage toBucket = buckets[_bucket.down];

                while (true) {
                    accumulateBucketInterest(toBucket, _inflator);

                    if (reallocation < toBucket.onDeposit) {
                        // reallocate all and exit
                        _bucket.debt -= reallocation;
                        toBucket.debt += reallocation;
                        toBucket.onDeposit -= reallocation;
                        lup = toBucket.price;
                        break;
                    } else {
                        if (toBucket.onDeposit != 0) {
                            reallocation -= toBucket.onDeposit;
                            _bucket.debt -= toBucket.onDeposit;
                            toBucket.debt += toBucket.onDeposit;
                            toBucket.onDeposit -= toBucket.onDeposit;
                        }
                    }

                    if (toBucket.down == 0) {
                        // last bucket, nowhere to go, guard against reallocation failures
                        if (reallocation != 0) {
                            revert NoDepositToReallocateTo();
                        }
                        lup = toBucket.price;
                        break;
                    }

                    toBucket = buckets[toBucket.down];
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
    /// @param buckets Mapping of buckets for a given pool
    /// @param _bucket The given bucket whose assets are being reallocated
    /// @param _amount The amount of quote tokens requiring reallocation
    /// @param _lup The current pool lup
    /// @param _inflator The current pool inflator rate
    /// @return The price to which assets were reallocated
    function reallocateUp(
        mapping(uint256 => Bucket) storage buckets,
        Bucket storage _bucket,
        uint256 _amount,
        uint256 _lup,
        uint256 _inflator // RAY
    ) private returns (uint256) {
        Bucket storage curLup = buckets[_lup];

        uint256 curLupDebt;

        while (true) {
            if (curLup.price == _bucket.price) {
                // reached deposit bucket; nowhere to go
                break;
            }

            // accumulate bucket interest
            accumulateBucketInterest(curLup, _inflator);

            curLupDebt = curLup.debt;

            if (_amount > curLupDebt) {
                _bucket.debt += curLupDebt;
                _bucket.onDeposit -= curLupDebt;
                _amount -= curLupDebt;
                curLup.debt = 0;
                curLup.onDeposit += curLupDebt;
                if (curLup.price == curLup.up) {
                    // reached top-of-book; nowhere to go
                    break;
                }
            } else {
                _bucket.debt += _amount;
                _bucket.onDeposit -= _amount;
                curLup.debt -= _amount;
                curLup.onDeposit += _amount;
                break;
            }

            curLup = buckets[curLup.up];
        }

        return curLup.price;
    }

    /// @notice Update bucket.debt with interest accumulated since last state change
    /// @param bucket The bucket being updated
    /// @param _inflator RAY - The current bucket inflator value
    function accumulateBucketInterest(Bucket storage bucket, uint256 _inflator) private {
        if (bucket.debt != 0) {
            bucket.debt += Maths.rayToRad(
                Maths.rmul(
                    Maths.radToRay(bucket.debt),
                    Maths.sub(Maths.rdiv(_inflator, bucket.inflatorSnapshot), Maths.ONE_RAY)
                )
            );
            bucket.inflatorSnapshot = _inflator;
        }
    }

    /// @notice Estimate the price at which a loan can be taken
    /// @param buckets Mapping of buckets for a given pool
    /// @param _amount The amount of quote tokens desired to borrow
    /// @param _hdp The current HDP of the pool
    function estimatePrice(
        mapping(uint256 => Bucket) storage buckets,
        uint256 _amount,
        uint256 _hdp
    ) public view returns (uint256) {
        Bucket memory curLup = buckets[_hdp];

        while (true) {
            if (_amount > curLup.onDeposit) {
                _amount -= curLup.onDeposit;
            } else if (_amount <= curLup.onDeposit) {
                return curLup.price;
            }

            if (curLup.down == 0) {
                return 0;
            } else {
                curLup = buckets[curLup.down];
            }
        }

        return 0;
    }

    /// @notice Return the information of the bucket at a given price
    /// @param buckets Mapping of buckets for a given pool
    /// @param _price The price of the bucket to retrieve information from
    function bucketAt(mapping(uint256 => Bucket) storage buckets, uint256 _price)
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
        Bucket memory bucket = buckets[_price];

        price = bucket.price;
        up = bucket.up;
        down = bucket.down;
        onDeposit = bucket.onDeposit;
        debt = bucket.debt;
        inflatorSnapshot = bucket.inflatorSnapshot;
        lpOutstanding = bucket.lpOutstanding;
        collateral = bucket.collateral;
    }

    // TODO: replace + with Maths.add()
    /// @notice Calculate the current exchange rate for Quote tokens / LP Tokens
    /// @dev Performs calculations in RAY terms and rounds up to determine size to minimize precision loss
    /// @return RAY The current rate at which quote tokens can be exchanged for LP tokens
    function getExchangeRate(Bucket storage bucket) internal view returns (uint256) {
        uint256 size = bucket.onDeposit +
            bucket.debt +
            Maths.rayToRad(Maths.rmul(bucket.collateral, Maths.wadToRay(bucket.price)));
        if (size != 0 && bucket.lpOutstanding != 0) {
            return Maths.rdiv(Maths.radToRay(size), bucket.lpOutstanding);
        }
        return Maths.ONE_RAY;
    }

    /// @notice Set state for a new bucket and update surrounding price pointers
    /// @param buckets Mapping of buckets for a given pool
    /// @param _hdp The current HDP of the pool
    /// @param _price The price of the bucket to retrieve information from
    /// @return The new HDP given the newly initialized bucket
    function initializeBucket(
        mapping(uint256 => Bucket) storage buckets,
        uint256 _hdp,
        uint256 _price
    ) public returns (uint256) {
        Bucket storage bucket = buckets[_price];
        bucket.price = _price;
        bucket.inflatorSnapshot = Maths.ONE_WAD;

        if (_price > _hdp) {
            bucket.down = _hdp;
            _hdp = _price;
        }

        uint256 cur = _hdp;
        uint256 down = buckets[_hdp].down;
        uint256 up = buckets[_hdp].up;

        // update price pointers
        while (true) {
            if (_price > down) {
                buckets[cur].down = _price;
                bucket.up = cur;
                bucket.down = down;
                buckets[down].up = _price;
                break;
            }
            cur = down;
            down = buckets[cur].down;
            up = buckets[cur].up;
        }
        return _hdp;
    }
}
