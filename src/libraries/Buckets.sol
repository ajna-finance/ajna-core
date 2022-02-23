pragma solidity 0.8.11;

library Buckets {
    struct Bucket {
        uint256 price; // current bucket price
        uint256 up; // upper utilizable bucket price
        uint256 down; // next utilizable bucket price
        uint256 amount; // total quote deposited in bucket
        uint256 debt; // accumulated bucket debt
    }

    function initializeBucket(
        mapping(uint256 => Bucket) storage buckets,
        uint256 _hup,
        uint256 _price
    ) public returns (uint256) {
        Bucket storage bucket = buckets[_price];
        bucket.price = _price;

        if (_price > _hup) {
            bucket.down = _hup;
            _hup = _price;
        }

        uint256 cur = _hup;
        uint256 down = buckets[_hup].down;
        uint256 up = buckets[_hup].up;

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

        return _hup;
    }

    function reallocateDebt(
        mapping(uint256 => Bucket) storage buckets,
        uint256 _amount,
        uint256 _price,
        uint256 _hup,
        uint256 _lup
    ) public returns (uint256) {
        Bucket memory bucket = buckets[_price];
        Bucket storage curLup = buckets[_lup];

        uint256 curLupDebt;
        uint256 debtReallocated;

        while (true) {
            if (curLup.price == _hup) {
                break;
            }

            curLupDebt = curLup.debt;

            if (_amount > curLupDebt) {
                bucket.debt += curLupDebt;
                _amount -= curLupDebt;
                curLup.debt = 0;
                debtReallocated += curLupDebt;
            } else {
                bucket.debt += _amount;
                curLup.debt -= _amount;
                debtReallocated += _amount;
                break;
            }

            curLup = buckets[curLup.up];
        }

        buckets[_price] = bucket;
        return curLup.price;
    }

    function borrow(
        mapping(uint256 => Bucket) storage buckets,
        uint256 _amount,
        uint256 _stop,
        uint256 _hup,
        uint256 _lup
    ) public returns (uint256) {
        Bucket storage curHup = buckets[_hup];
        uint256 amountRemaining = _amount;
        uint256 curHupDeposit;

        while (true) {
            require(curHup.price >= _stop, "ajna/stop-price-exceeded");

            curHupDeposit = curHup.amount - curHup.debt;

            if (amountRemaining > curHupDeposit) {
                // take all on deposit from this bucket, move to next
                curHup.debt += curHupDeposit;
                amountRemaining -= curHupDeposit;
            } else {
                // take all remaining loan from this bucket and exit
                curHup.debt += amountRemaining;
                break;
            }

            curHup = buckets[curHup.down];
        }

        if (_lup > curHup.price || _lup == 0) {
            _lup = curHup.price;
        }

        return _lup;
    }

    function estimatePrice(
        mapping(uint256 => Bucket) storage buckets,
        uint256 _amount,
        uint256 _hup
    ) public view returns (uint256) {
        Bucket memory curHup = buckets[_hup];
        uint256 curHupDeposit;

        while (true) {
            curHupDeposit = curHup.amount - curHup.debt;

            if (_amount > curHupDeposit) {
                _amount -= curHupDeposit;
            } else if (_amount <= curHupDeposit) {
                return curHup.price;
            }

            curHup = buckets[curHup.down];
        }

        return 0;
    }

    function onDeposit(
        mapping(uint256 => Bucket) storage buckets,
        uint256 _price
    ) public view returns (uint256) {
        Bucket storage cur = buckets[_price];
        return cur.amount - cur.debt;
    }
}
