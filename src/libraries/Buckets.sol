// SPDX-License-Identifier: MIT

pragma solidity 0.8.11;

import "./Maths.sol";

library Buckets {
    struct Bucket {
        uint256 price; // current bucket price
        uint256 up; // upper utilizable bucket price
        uint256 down; // next utilizable bucket price
        uint256 amount; // total quote deposited in bucket
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

        lup = _lup;
        if (_reallocate) {
            lup = reallocateUp(buckets, _price, _amount, _lup, _inflator);
        }

        lpTokens = Maths.wdiv(_amount, getExchangeRate(bucket));
        bucket.amount += _amount;
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
            _amount <= Maths.wmul(_lpBalance, exchangeRate) &&
                bucket.amount >= bucket.debt,
            "ajna/amount-greater-than-claimable"
        );

        lup = reallocateDown(buckets, bucket, _amount, _inflator);

        lpTokens = Maths.wdiv(_amount, exchangeRate);
        bucket.amount -= _amount;
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
        uint256 curLupDeposit;

        while (true) {
            require(curLup.price >= _stop, "ajna/stop-price-exceeded");

            // accumulate bucket interest
            accumulateBucketInterest(curLup, _inflator);

            if (curLup.amount > curLup.debt) {
                curLup.inflatorSnapshot = _inflator;
                curLupDeposit = curLup.amount - curLup.debt;

                if (amountRemaining > curLupDeposit) {
                    // take all on deposit from this bucket
                    curLup.debt += curLupDeposit;
                    amountRemaining -= curLupDeposit;
                    loanCost += Maths.wdiv(curLupDeposit, curLup.price);
                } else {
                    // take all remaining amount for loan from this bucket and exit
                    curLup.debt += amountRemaining;
                    loanCost += Maths.wdiv(amountRemaining, curLup.price);
                    break;
                }
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
                    curLup.debt = 0;
                } else {
                    // pay as much debt as possible and exit
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

        require(_amount <= bucket.amount, "ajna/not-enough-quote-token");

        lup = reallocateDown(buckets, bucket, _amount, _inflator);

        bucket.amount -= _amount;
        bucket.collateral += _collateral;
    }

    function liquidate(
        mapping(uint256 => Bucket) storage buckets,
        uint256 _debt,
        uint256 _collateral,
        uint256 _hdp,
        uint256 _inflator
    ) public returns (uint256 lentTokens, uint256 requiredCollateral) {
        Bucket storage bucket = buckets[_hdp];

        while (true) {
            accumulateBucketInterest(bucket, _inflator);
            uint256 bucketDebtToPurchase = Maths.min(_debt, bucket.debt);

            uint256 bucketRequiredCollateral = Maths.min(
                Maths.min(Maths.wdiv(_debt, bucket.price), _collateral),
                Maths.wdiv(bucket.debt, bucket.price)
            );

            uint256 bucketLentTokens = Maths.min(
                bucket.amount,
                bucketDebtToPurchase
            );

            _debt -= bucketDebtToPurchase;
            _collateral -= bucketRequiredCollateral;
            requiredCollateral += bucketRequiredCollateral;

            lentTokens += bucketLentTokens;

            // bucket accounting
            bucket.debt -= bucketDebtToPurchase;
            bucket.amount -= bucketLentTokens;
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
        uint256 onDeposit;
        if (_bucket.amount > _bucket.debt) {
            onDeposit = _bucket.amount - _bucket.debt;
        }
        if (_amount > onDeposit) {
            uint256 reallocation = _amount - onDeposit;
            if (_bucket.down != 0) {
                Bucket storage toBucket = buckets[_bucket.down];

                while (true) {
                    accumulateBucketInterest(toBucket, _inflator);

                    uint256 toBucketOnDeposit;
                    if (toBucket.amount > toBucket.debt) {
                        toBucketOnDeposit = toBucket.amount - toBucket.debt;
                    }

                    if (reallocation < toBucketOnDeposit) {
                        // reallocate all and exit
                        _bucket.debt -= reallocation;
                        toBucket.debt += reallocation;
                        lup = toBucket.price;
                        break;
                    } else {
                        if (toBucketOnDeposit != 0) {
                            reallocation -= toBucketOnDeposit;
                            _bucket.debt -= toBucketOnDeposit;
                            toBucket.debt += toBucketOnDeposit;
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
                _amount -= curLupDebt;
                curLup.debt = 0;
                if (curLup.price == curLup.up) {
                    // nowhere to go
                    break;
                }
            } else {
                bucket.debt += _amount;
                curLup.debt -= _amount;
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
        uint256 curLupDeposit;

        while (true) {
            curLupDeposit = curLup.amount - curLup.debt;

            if (_amount > curLupDeposit) {
                _amount -= curLupDeposit;
            } else if (_amount <= curLupDeposit) {
                return curLup.price;
            }

            curLup = buckets[curLup.down];
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
        amount = bucket.amount;
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
        if (bucket.amount != 0 && bucket.lpOutstanding != 0) {
            return
                Maths.wdiv(
                    Maths.max(bucket.amount, bucket.debt) +
                        Maths.wmul(bucket.collateral, bucket.price),
                    bucket.lpOutstanding
                );
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
