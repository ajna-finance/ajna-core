// SPDX-License-Identifier: MIT

pragma solidity 0.8.11;

import "./Maths.sol";

library Buckets {
    struct Bucket {
        uint256 price; // current bucket price
        uint256 up; // upper utilizable bucket price
        uint256 down; // next utilizable bucket price
        uint256 onDeposit; // quote token on deposit in bucket
        uint256 debt; // accumulated bucket debt
        uint256 inflatorSnapshot; // bucket inflator snapshot
        uint256 lpOutstanding;
        uint256 collateral;
    }

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

        bucket.onDeposit += _amount;
        lup = _lup;
        if (_reallocate) {
            lup = reallocateUp(buckets, _price, _amount, _lup, _inflator);
        }

        lpTokens = Maths.wdiv(_amount, getExchangeRate(bucket));
        bucket.lpOutstanding += lpTokens;
    }

    function removeQuoteToken(
        mapping(uint256 => Bucket) storage buckets,
        uint256 _price,
        uint256 _amount,
        uint256 _lpBalance,
        uint256 _inflator
    ) public returns (uint256 lup, uint256 lpTokens) {
        Bucket storage bucket = buckets[_price];

        accumulateBucketInterest(bucket, _inflator);

        uint256 exchangeRate = getExchangeRate(bucket);
        require(
            _amount <= Maths.wmul(_lpBalance, exchangeRate),
            "ajna/amount-greater-than-claimable"
        );
        lpTokens = Maths.wdiv(_amount, exchangeRate);

        // Remove from deposit first
        uint256 removeFromDeposit = Maths.min(_amount, bucket.onDeposit);
        bucket.onDeposit -= removeFromDeposit;
        _amount -= removeFromDeposit;

        // Reallocate debt to fund remaining withdrawal
        lup = reallocateDown(buckets, bucket, _amount, _inflator);

        bucket.lpOutstanding -= lpTokens;
    }

    function claimCollateral(
        mapping(uint256 => Bucket) storage buckets,
        uint256 _price,
        uint256 _amount,
        uint256 _lpBalance
    ) public returns (uint256) {
        Bucket storage bucket = buckets[_price];

        require(
            bucket.collateral > 0 && _amount <= bucket.collateral,
            "ajna/insufficient-amount-to-claim"
        );

        uint256 exchangeRate = getExchangeRate(bucket);
        uint256 lpRedemption = Maths.wdiv(
            Maths.wmul(_amount, bucket.price),
            exchangeRate
        );

        require(lpRedemption <= _lpBalance, "ajna/insufficient-lp-balance");

        bucket.collateral -= _amount;
        bucket.lpOutstanding -= lpRedemption;
        return lpRedemption;
    }

    function borrow(
        mapping(uint256 => Bucket) storage buckets,
        uint256 _amount,
        uint256 _stop, // lowest price desired to borrow at
        uint256 _lup, // lowest utilized price
        uint256 _inflator
    ) public returns (uint256 lup, uint256 loanCost) {
        Bucket storage curLup = buckets[_lup];
        uint256 amountRemaining = _amount;

        while (true) {
            require(curLup.price >= _stop, "ajna/stop-price-exceeded");

            // accumulate bucket interest
            accumulateBucketInterest(curLup, _inflator);
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

            // move to next bucket
            curLup = buckets[curLup.down];
        }

        if (_lup > curLup.price || _lup == 0) {
            _lup = curLup.price;
        }

        return (_lup, loanCost);
    }

    function repay(
        mapping(uint256 => Bucket) storage buckets,
        uint256 _amount,
        uint256 _lup,
        uint256 _inflator
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

    function purchaseBid(
        mapping(uint256 => Bucket) storage buckets,
        uint256 _price,
        uint256 _amount,
        uint256 _collateral,
        uint256 _inflator
    ) public returns (uint256 lup) {
        Bucket storage bucket = buckets[_price];
        accumulateBucketInterest(bucket, _inflator);

        require(
            _amount <= bucket.onDeposit + bucket.debt,
            "ajna/insufficient-bucket-size"
        );

        // Exchange collateral for quote token on deposit
        uint256 purchaseFromDeposit = Maths.min(_amount, bucket.onDeposit);
        bucket.onDeposit -= purchaseFromDeposit;
        _amount -= purchaseFromDeposit;

        // Reallocate debt to exchange for collateral
        lup = reallocateDown(buckets, bucket, _amount, _inflator);

        bucket.collateral += _collateral;
    }

    function liquidate(
        mapping(uint256 => Bucket) storage buckets,
        uint256 _debt,
        uint256 _collateral,
        uint256 _hdp,
        uint256 _inflator
    ) public returns (uint256 requiredCollateral) {
        Bucket storage bucket = buckets[_hdp];

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

            bucket = buckets[bucket.down];
        }
    }

    function reallocateDown(
        mapping(uint256 => Bucket) storage buckets,
        Bucket storage _bucket,
        uint256 _amount,
        uint256 _inflator
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
                        require(reallocation == 0, "ajna/failed-to-reallocate");
                        lup = toBucket.price;
                        break;
                    }

                    toBucket = buckets[toBucket.down];
                }
            } else {
                // lup started at the bottom
                require(reallocation == 0, "ajna/failed-to-reallocate");
            }
        }
    }

    function reallocateUp(
        mapping(uint256 => Bucket) storage buckets,
        uint256 _price,
        uint256 _amount,
        uint256 _lup,
        uint256 _inflator
    ) private returns (uint256) {
        Bucket storage bucket = buckets[_price];
        Bucket storage curLup = buckets[_lup];

        uint256 curLupDebt;

        while (true) {
            // accumulate bucket interest
            accumulateBucketInterest(curLup, _inflator);

            curLupDebt = curLup.debt;

            if (_amount > curLupDebt) {
                bucket.debt += curLupDebt;
                bucket.onDeposit -= curLupDebt;
                _amount -= curLupDebt;
                curLup.debt = 0;
                curLup.onDeposit += curLupDebt;
                if (curLup.price == curLup.up) {
                    // nowhere to go
                    break;
                }
            } else {
                bucket.debt += _amount;
                bucket.onDeposit -= _amount;
                curLup.debt -= _amount;
                curLup.onDeposit += _amount;
                break;
            }

            if (curLup.up == _price) {
                // nowhere to go
                break;
            }

            curLup = buckets[curLup.up];
        }

        return curLup.price;
    }

    function accumulateBucketInterest(Bucket storage bucket, uint256 _inflator)
        private
    {
        if (bucket.debt != 0) {
            bucket.debt += Maths.wmul(
                bucket.debt,
                Maths.wdiv(_inflator, bucket.inflatorSnapshot) - Maths.ONE_WAD
            );
            bucket.inflatorSnapshot = _inflator;
        }
    }

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

    function bucketAt(
        mapping(uint256 => Bucket) storage buckets,
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
        Bucket memory bucket = buckets[_price];

        price = bucket.price;
        up = bucket.up;
        down = bucket.down;
        amount = bucket.onDeposit;
        debt = bucket.debt;
        inflatorSnapshot = bucket.inflatorSnapshot;
        lpOutstanding = bucket.lpOutstanding;
        collateral = bucket.collateral;
    }

    function getExchangeRate(Bucket storage bucket)
        internal
        view
        returns (uint256)
    {
        uint256 size = bucket.onDeposit +
            bucket.debt +
            Maths.wmul(bucket.collateral, bucket.price);
        if (size != 0 && bucket.lpOutstanding != 0) {
            return Maths.wdiv(size, bucket.lpOutstanding);
        }
        return Maths.ONE_WAD;
    }

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
