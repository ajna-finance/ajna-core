// SPDX-License-Identifier: MIT

pragma solidity 0.8.11;

import "./Maths.sol";
import "./BucketMath.sol";

library Buckets {
    struct Bucket {
        uint256 price; // current bucket price
        int256 index; // price index
        int256 up; // upper utilizable bucket price index
        int256 down; // next utilizable bucket price index
        uint256 onDeposit; // quote token on deposit in bucket
        uint256 debt; // accumulated bucket debt
        uint256 inflatorSnapshot; // bucket inflator snapshot
        uint256 lpOutstanding;
        uint256 collateral;
    }

    function addQuoteToken(
        mapping(int256 => Bucket) storage _buckets,
        Bucket storage _bucket,
        uint256 _amount,
        int256 _lup,
        uint256 _inflator,
        bool _reallocate
    ) public returns (int256 lup, uint256 lpTokens) {
        accumulateBucketInterest(_bucket, _inflator);

        _bucket.onDeposit += _amount;
        if (_reallocate) {
            lup = reallocateUp(_buckets, _bucket, _amount, _lup, _inflator);
        }

        lpTokens = Maths.wdiv(_amount, getExchangeRate(_bucket));
        _bucket.lpOutstanding += lpTokens;
    }

    function removeQuoteToken(
        mapping(int256 => Bucket) storage _buckets,
        Bucket storage _bucket,
        uint256 _amount,
        uint256 _lpBalance,
        uint256 _inflator
    ) public returns (int256 lup, uint256 lpTokens) {
        accumulateBucketInterest(_bucket, _inflator);

        uint256 exchangeRate = getExchangeRate(_bucket);
        require(
            _amount <= Maths.wmul(_lpBalance, exchangeRate),
            "ajna/amount-greater-than-claimable"
        );
        lpTokens = Maths.wdiv(_amount, exchangeRate);

        // Remove from deposit first
        uint256 removeFromDeposit = Maths.min(_amount, _bucket.onDeposit);
        _bucket.onDeposit -= removeFromDeposit;
        _amount -= removeFromDeposit;

        // Reallocate debt to fund remaining withdrawal
        lup = reallocateDown(_buckets, _bucket, _amount, _inflator);

        _bucket.lpOutstanding -= lpTokens;
    }

    function claimCollateral(
        mapping(int256 => Bucket) storage _buckets,
        Bucket storage _bucket,
        uint256 _amount,
        uint256 _lpBalance
    ) public returns (uint256) {
        require(
            _bucket.collateral > 0 && _amount <= _bucket.collateral,
            "ajna/insufficient-amount-to-claim"
        );

        uint256 exchangeRate = getExchangeRate(_bucket);
        uint256 lpRedemption = Maths.wdiv(
            Maths.wmul(_amount, _bucket.price),
            exchangeRate
        );

        require(lpRedemption <= _lpBalance, "ajna/insufficient-lp-balance");

        _bucket.collateral -= _amount;
        _bucket.lpOutstanding -= lpRedemption;
        return lpRedemption;
    }

    function borrow(
        mapping(int256 => Bucket) storage _buckets,
        uint256 _amount,
        uint256 _stop, // lowest price desired to borrow at
        int256 _lup, // lowest utilized price
        uint256 _inflator
    ) public returns (int256 lup, uint256 loanCost) {
        Bucket storage curLup = _buckets[_lup];
        uint256 amountRemaining = _amount;

        while (true) {
            require(curLup.price >= _stop, "ajna/stop-price-exceeded");

            // accumulate bucket interest
            accumulateBucketInterest(curLup, _inflator);

            if (curLup.onDeposit > curLup.debt) {
                curLup.inflatorSnapshot = _inflator;

                if (amountRemaining > curLup.onDeposit) {
                    // take all on deposit from this bucket
                    curLup.debt += curLup.onDeposit;
                    amountRemaining -= curLup.onDeposit;
                    loanCost += Maths.wdiv(curLup.onDeposit, curLup.price);
                    curLup.onDeposit -= curLup.onDeposit;
                } else {
                    // take all remaining amount for loan from this bucket and exit
                    curLup.onDeposit -= amountRemaining;
                    curLup.debt += amountRemaining;
                    loanCost += Maths.wdiv(amountRemaining, curLup.price);
                    break;
                }
            }

            // move to next bucket
            curLup = _buckets[curLup.down];
        }

        if (_lup > curLup.index || _lup == BucketMath.MIN_PRICE_INDEX) {
            _lup = curLup.index;
        }

        return (_lup, loanCost);
    }

    function repay(
        mapping(int256 => Bucket) storage _buckets,
        uint256 _amount,
        int256 _lup,
        uint256 _inflator
    ) public returns (int256, uint256) {
        Bucket storage curLup = _buckets[_lup];
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

            if (curLup.index == curLup.up) {
                // nowhere to go
                break;
            }
            // move to upper bucket
            curLup = _buckets[curLup.up];
        }

        return (curLup.index, debtToPay);
    }

    function purchaseBid(
        mapping(int256 => Bucket) storage _buckets,
        Bucket storage _bucket,
        uint256 _amount,
        uint256 _collateral,
        uint256 _inflator
    ) public returns (int256 lup) {
        accumulateBucketInterest(_bucket, _inflator);

        require(
            _amount <= _bucket.onDeposit + _bucket.debt,
            "ajna/insufficient-bucket-size"
        );

        // Exchange collateral for quote token on deposit
        uint256 purchaseFromDeposit = Maths.min(_amount, _bucket.onDeposit);
        _bucket.onDeposit -= purchaseFromDeposit;
        _amount -= purchaseFromDeposit;

        // Reallocate debt to exchange for collateral
        lup = reallocateDown(_buckets, _bucket, _amount, _inflator);

        _bucket.collateral += _collateral;
    }

    function liquidate(
        mapping(int256 => Bucket) storage _buckets,
        uint256 _debt,
        uint256 _collateral,
        int256 _hdp,
        uint256 _inflator
    ) public returns (uint256 requiredCollateral) {
        Bucket storage bucket = _buckets[_hdp];

        while (true) {
            accumulateBucketInterest(bucket, _inflator);
            uint256 bucketDebtToPurchase = Maths.min(_debt, bucket.debt);

            uint256 bucketRequiredCollateral = Maths.min(
                Maths.min(Maths.wdiv(_debt, bucket.price), _collateral),
                Maths.wdiv(bucket.debt, bucket.price)
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

            bucket = _buckets[bucket.down];
        }
    }

    function reallocateDown(
        mapping(int256 => Bucket) storage _buckets,
        Bucket storage _bucket,
        uint256 _amount,
        uint256 _inflator
    ) private returns (int256 lup) {
        lup = _bucket.index;

        // debt reallocation
        if (_amount > _bucket.onDeposit) {
            uint256 reallocation = _amount - _bucket.onDeposit;
            if (_bucket.down != BucketMath.MIN_PRICE_INDEX) {
                Bucket storage toBucket = _buckets[_bucket.down];

                while (true) {
                    accumulateBucketInterest(toBucket, _inflator);

                    if (reallocation < toBucket.onDeposit) {
                        // reallocate all and exit
                        _bucket.debt -= reallocation;
                        toBucket.debt += reallocation;
                        toBucket.onDeposit -= reallocation;
                        lup = toBucket.index;
                        break;
                    } else {
                        if (toBucket.onDeposit != 0) {
                            reallocation -= toBucket.onDeposit;
                            _bucket.debt -= toBucket.onDeposit;
                            toBucket.debt += toBucket.onDeposit;
                            toBucket.onDeposit -= toBucket.onDeposit;
                        }
                    }

                    if (toBucket.down == BucketMath.MIN_PRICE_INDEX) {
                        // last bucket, nowhere to go, guard against reallocation failures
                        require(reallocation == 0, "ajna/failed-to-reallocate");
                        lup = toBucket.index;
                        break;
                    }

                    toBucket = _buckets[toBucket.down];
                }
            } else {
                // lup started at the bottom
                require(reallocation == 0, "ajna/failed-to-reallocate");
            }
        }
    }

    function reallocateUp(
        mapping(int256 => Bucket) storage _buckets,
        Bucket storage _bucket,
        uint256 _amount,
        int256 _lup,
        uint256 _inflator
    ) private returns (int256) {
        Bucket storage curLup = _buckets[_lup];

        uint256 curLupDebt;

        while (true) {
            // accumulate bucket interest
            accumulateBucketInterest(curLup, _inflator);

            curLupDebt = curLup.debt;

            if (_amount > curLupDebt) {
                _bucket.debt += curLupDebt;
                _bucket.onDeposit -= curLupDebt;
                _amount -= curLupDebt;
                curLup.debt = 0;
                curLup.onDeposit += curLupDebt;
                if (curLup.index == curLup.up) {
                    // nowhere to go
                    break;
                }
            } else {
                _bucket.debt += _amount;
                _bucket.onDeposit -= _amount;
                curLup.debt -= _amount;
                curLup.onDeposit += _amount;
                break;
            }

            if (curLup.up == _bucket.index) {
                // nowhere to go
                break;
            }

            curLup = _buckets[curLup.up];
        }

        return curLup.index;
    }

    function accumulateBucketInterest(Bucket storage _bucket, uint256 _inflator)
        private
    {
        if (_bucket.debt != 0) {
            _bucket.debt += Maths.wmul(
                _bucket.debt,
                Maths.wdiv(_inflator, _bucket.inflatorSnapshot) - Maths.ONE_WAD
            );
            _bucket.inflatorSnapshot = _inflator;
        }
    }

    function estimatePrice(
        mapping(int256 => Bucket) storage _buckets,
        uint256 _amount,
        int256 _hdp
    ) public view returns (uint256) {
        Bucket memory curLup = _buckets[_hdp];

        while (true) {
            if (_amount > curLup.onDeposit) {
                _amount -= curLup.onDeposit;
            } else if (_amount <= curLup.onDeposit) {
                return curLup.price;
            }

            if (curLup.down == BucketMath.MIN_PRICE_INDEX) {
                return 0;
            } else {
                curLup = _buckets[curLup.down];
            }
        }

        return 0;
    }

    function bucketAt(
        mapping(int256 => Bucket) storage _buckets,
        uint256 _price
    )
        public
        view
        returns (
            uint256 price,
            uint256 up,
            uint256 down,
            uint256 amount,
            uint256 debt,
            uint256 inflatorSnapshot,
            uint256 lpOutstanding,
            uint256 collateral
        )
    {
        Bucket memory bucket = _buckets[BucketMath.priceToIndex(_price)];

        price = bucket.price;
        up = _buckets[bucket.up].price;
        down = _buckets[bucket.down].price;
        amount = bucket.onDeposit;
        debt = bucket.debt;
        inflatorSnapshot = bucket.inflatorSnapshot;
        lpOutstanding = bucket.lpOutstanding;
        collateral = bucket.collateral;
    }

    function getExchangeRate(Bucket storage _bucket)
        internal
        view
        returns (uint256)
    {
        uint256 size = _bucket.onDeposit +
            _bucket.debt +
            Maths.wmul(_bucket.collateral, _bucket.price);
        if (size != 0 && _bucket.lpOutstanding != 0) {
            return Maths.wdiv(size, _bucket.lpOutstanding);
        }
        return Maths.ONE_WAD;
    }

    function initializeBucket(
        mapping(int256 => Bucket) storage _buckets,
        Bucket storage _bucket,
        int256 _hdp
    ) public returns (int256) {
        _bucket.inflatorSnapshot = Maths.ONE_WAD;

        if (_hdp == BucketMath.MIN_PRICE_INDEX) {
            _bucket.up = _bucket.index;
            _bucket.down = BucketMath.MIN_PRICE_INDEX;
            _buckets[BucketMath.MIN_PRICE_INDEX].up = _bucket.index;
            return _bucket.index;
        }

        if (_bucket.index > _hdp) {
            _bucket.down = _hdp;
            _hdp = _bucket.index;
        }

        Bucket storage hdpBucket = _buckets[_hdp];
        int256 down = hdpBucket.down;

        // update price pointers
        while (true) {
            if (_bucket.index > down) {
                hdpBucket.down = _bucket.index;
                _bucket.up = hdpBucket.index;
                _bucket.down = down;
                _buckets[down].up = _bucket.index;
                break;
            }
            hdpBucket = _buckets[down];
            down = hdpBucket.down;
        }

        return _hdp;
    }
}
