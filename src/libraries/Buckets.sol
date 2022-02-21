pragma solidity 0.8.10;

library Buckets {
    struct Bucket {
        uint256 price; // current bucket price
        uint256 next; // next utilizable bucket price
        uint256 amount; // total quote deposited in bucket
        uint256 debt; // accumulated bucket debt
    }

    function addPriceBucket(
        mapping(uint256 => Bucket) storage buckets,
        uint256 _amount,
        uint256 _price,
        uint256 _hup
    ) public returns (uint256) {
        Bucket storage bucket = buckets[_price];
        bucket.price = _price;
        bucket.amount += _amount;

        if (_price > _hup && bucket.amount - bucket.debt > 0) {
            bucket.next = _hup;
            _hup = _price;
        }

        uint256 cur = _hup;
        uint256 next = buckets[_hup].next;

        // update next price pointers accordingly to current price
        while (true) {
            if (_price > next) {
                buckets[cur].next = _price;
                bucket.next = next;
                break;
            }
            cur = next;
            next = buckets[next].next;
        }

        return _hup;
    }

    function borrow(
        mapping(uint256 => Bucket) storage buckets,
        uint256 _amount,
        uint256 _stop,
        uint256 _hup
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
            } else if (amountRemaining <= curHupDeposit) {
                // take all remaining loan from this bucket and exit
                curHup.debt += amountRemaining;
                break;
            }

            curHup = buckets[curHup.next];
        }

        if (_hup != curHup.price) {
            _hup = curHup.price;
        }

        return _hup;
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

            curHup = buckets[curHup.next];
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
