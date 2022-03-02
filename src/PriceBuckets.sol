pragma solidity 0.8.11;

import {BitMaps} from "@openzeppelin/contracts/utils/structs/BitMaps.sol";

import "./libraries/Maths.sol";

interface IPriceBuckets {
    function addToBucket(uint256 _price, uint256 _amount) external;

    function subtractFromBucket(uint256 _price, uint256 _amount) external;

    function reallocateDebt(
        uint256 _amount,
        uint256 _price,
        uint256 _hdp,
        uint256 _lup
    ) external returns (uint256 price);

    function borrow(
        uint256 _amount,
        uint256 _stop,
        uint256 _lup
    ) external returns (uint256 lup, uint256 loanCost);

    function ensureBucket(uint256 _hdp, uint256 _price)
        external
        returns (uint256 hdp);

    function isBucketInitialized(uint256 _price) external view returns (bool);

    function onDeposit(uint256 _price) external view returns (uint256);

    function estimatePrice(uint256 amount, uint256 hdp)
        external
        view
        returns (uint256 price);

    function bucketAt(uint256 _price)
        external
        view
        returns (
            uint256 price,
            uint256 up,
            uint256 down,
            uint256 amount,
            uint256 debt
        );
}

contract PriceBuckets is IPriceBuckets {
    struct Bucket {
        uint256 price; // current bucket price
        uint256 up; // upper utilizable bucket price
        uint256 down; // next utilizable bucket price
        uint256 amount; // total quote deposited in bucket
        uint256 debt; // accumulated bucket debt
    }

    mapping(uint256 => Bucket) private buckets;
    BitMaps.BitMap private bitmap;

    function addToBucket(uint256 _price, uint256 _amount) public {
        buckets[_price].amount += _amount;
    }

    function subtractFromBucket(uint256 _price, uint256 _amount) public {
        buckets[_price].amount -= _amount;
    }

    function reallocateDebt(
        uint256 _amount,
        uint256 _price,
        uint256 _hdp,
        uint256 _lup
    ) public returns (uint256 price) {
        Bucket memory bucket = buckets[_price];
        Bucket storage curLup = buckets[_lup];

        uint256 curLupDebt;
        uint256 debtReallocated;

        while (true) {
            if (curLup.price == _hdp) {
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
        uint256 _amount,
        uint256 _stop,
        uint256 _lup
    ) public returns (uint256 lup, uint256 loanCost) {
        Bucket storage curLup = buckets[_lup];
        uint256 amountRemaining = _amount;
        uint256 curLupDeposit;

        while (true) {
            require(curLup.price >= _stop, "ajna/stop-price-exceeded");

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

            // move to next bucket
            curLup = buckets[curLup.down];
        }

        if (_lup > curLup.price || _lup == 0) {
            _lup = curLup.price;
        }

        return (_lup, loanCost);
    }

    function estimatePrice(uint256 _amount, uint256 _hdp)
        public
        view
        returns (uint256)
    {
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

    function ensureBucket(uint256 _hdp, uint256 _price)
        public
        returns (uint256)
    {
        if (isBucketInitialized(_price)) {
            return _hdp;
        } else {
            return _initializeBucket(_hdp, _price);
        }
    }

    function onDeposit(uint256 _price) public view returns (uint256) {
        Bucket storage cur = buckets[_price];
        return cur.amount - cur.debt;
    }

    function bucketAt(uint256 _price)
        public
        view
        returns (
            uint256 price,
            uint256 up,
            uint256 down,
            uint256 amount,
            uint256 debt
        )
    {
        Bucket memory bucket = buckets[_price];

        price = bucket.price;
        up = bucket.up;
        down = bucket.down;
        amount = bucket.amount;
        debt = bucket.debt;
    }

    function isBucketInitialized(uint256 _price) public view returns (bool) {
        return BitMaps.get(bitmap, _price);
    }

    function _initializeBucket(uint256 _hdp, uint256 _price)
        internal
        returns (uint256)
    {
        Bucket storage bucket = buckets[_price];
        bucket.price = _price;

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

        BitMaps.setTo(bitmap, _price, true);
        return _hdp;
    }
}
