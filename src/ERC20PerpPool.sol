// SPDX-License-Identifier: MIT

pragma solidity 0.8.10;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IPerpPool {
    function depositCollateral(uint256 _amount) external;

    function withdrawCollateral(uint256 _amount) external;

    function depositQuoteToken(uint256 _amount, uint256 _price) external;

    function withdrawQuoteToken(uint256 _amount) external;

    function borrow(uint256 _amount) external;

    function actualUtilization() external view returns (uint256);

    function targetUtilization() external view returns (uint256);
}

contract Common {
    // --- Math ---
    uint256 public constant WAD = 10**18;

    function add(uint256 x, uint256 y) internal pure returns (uint256 z) {
        require((z = x + y) >= x, "ds-math-add-overflow");
    }

    function sub(uint256 x, uint256 y) internal pure returns (uint256 z) {
        require((z = x - y) <= x, "ds-math-sub-underflow");
    }

    function mul(uint256 x, uint256 y) internal pure returns (uint256 z) {
        require(y == 0 || (z = x * y) / y == x, "ds-math-mul-overflow");
    }

    function wmul(uint256 x, uint256 y) internal pure returns (uint256 z) {
        z = add(mul(x, y), WAD / 2) / WAD;
    }

    function wdiv(uint256 x, uint256 y) internal pure returns (uint256 z) {
        z = add(mul(x, WAD), y / 2) / y;
    }

    function max(uint256 x, uint256 y) internal pure returns (uint256 z) {
        z = x >= y ? x : y;
    }

    function min(uint256 x, uint256 y) internal pure returns (uint256 z) {
        z = x <= y ? x : y;
    }
}

contract ERC20PerpPool is IPerpPool, Common {
    struct Bucket {
        mapping(address => uint256) lpTokenBalance;
        uint256 onDeposit;
        uint256 totalDebitors;
        mapping(uint256 => address) indexToDebitor;
        mapping(address => uint256) debitorToIndex;
        mapping(address => uint256) debt;
        uint256 debtAccumulator;
    }

    struct Borrower {
        uint256 collateralEncumbered;
        uint256 debt;
        uint256 inflatorSnapshot;
    }

    event CollateralDeposit(
        address depositor,
        uint256 amount,
        uint256 collateralAccumulator
    );
    event CollateralWithdraw(
        address depositor,
        uint256 amount,
        uint256 collateralAccumulator
    );
    event QuoteTokenDeposit(
        address depositor,
        uint256 amount,
        uint256 quoteTokenAccumulator
    );
    event Borrow(
        address borrower,
        uint256 amount,
        uint256 quoteTokenAccumulator
    );

    uint256 public constant SECONDS_PER_YEAR = 3600 * 24 * 365;
    uint256 public constant MAX_PRICE = 5000 * WAD;
    uint256 public constant MIN_PRICE = 1000 * WAD;
    uint256 public constant PRICE_COUNT = 7000;
    uint256 public constant PRICE_STEP = (MAX_PRICE - MIN_PRICE) / PRICE_COUNT;

    IERC20 public immutable collateralToken;
    IERC20 public immutable quoteToken;

    mapping(uint256 => Bucket) public buckets;

    mapping(address => uint256) public collateralBalances;
    uint256 public collateralAccumulator;

    mapping(address => uint256) public quoteBalances;
    uint256 public quoteTokenAccumulator;

    mapping(address => Borrower) public borrowers;

    uint256 public borrowerInflator = 1 * WAD;
    uint256 public lastBorrowerInflatorUpdate = block.timestamp;
    uint256 public previousRate = wdiv(5, 100);
    uint256 public previousRateUpdate = block.timestamp;

    constructor(IERC20 _collateralToken, IERC20 _quoteToken) {
        collateralToken = _collateralToken;
        quoteToken = _quoteToken;
    }

    modifier updateBorrowerInflator(address account) {
        _;
        if (block.timestamp - lastBorrowerInflatorUpdate == 0) {
            return;
        }

        borrowerInflator = nextBorrowerInflator();
        lastBorrowerInflatorUpdate = block.timestamp;
    }

    function priceToIndex(uint256 price) public pure returns (uint256 index) {
        index = (price - MIN_PRICE) / PRICE_STEP;
    }

    function indexToPrice(uint256 index) public pure returns (uint256 price) {
        price = MIN_PRICE + (PRICE_STEP * index);
    }

    function depositCollateral(uint256 _amount)
        external
        updateBorrowerInflator(msg.sender)
    {
        require(
            collateralToken.balanceOf(msg.sender) >= _amount,
            "low-balance"
        );

        collateralBalances[msg.sender] += _amount;
        collateralAccumulator += _amount;

        collateralToken.transferFrom(msg.sender, address(this), _amount);
        emit CollateralDeposit(msg.sender, _amount, collateralAccumulator);
    }

    function withdrawCollateral(uint256 _amount)
        external
        updateBorrowerInflator(msg.sender)
    {
        require(
            _amount < collateralAvailableToWithdraw(msg.sender),
            "not-enough-collateral"
        );

        collateralBalances[msg.sender] -= _amount;
        collateralAccumulator -= _amount;

        collateralToken.transfer(msg.sender, _amount);
        emit CollateralWithdraw(msg.sender, _amount, collateralAccumulator);
    }

    function depositQuoteToken(uint256 _amount, uint256 _price) external {
        uint256 depositIndex = priceToIndex(_price);
        require(
            depositIndex > 0 && quoteToken.balanceOf(msg.sender) >= _amount,
            "no-price-bucket-or-balance"
        );

        Bucket storage toBucket = buckets[depositIndex];

        toBucket.lpTokenBalance[msg.sender] += _amount;
        toBucket.onDeposit += _amount;

        uint256 toBucketDebtAccumulator = toBucket.debtAccumulator;

        quoteBalances[msg.sender] += _amount;
        quoteTokenAccumulator += _amount;

        uint256 lupIndex = lup();
        if (depositIndex > lupIndex) {
            for (uint256 i = lupIndex; i < depositIndex; i++) {
                uint256 fromBucketPrice = indexToPrice(i);
                require(fromBucketPrice < _price, "lower-to-bucket-price");

                Bucket storage fromBucket = buckets[i];

                uint256 totalDebitors = fromBucket.totalDebitors;
                uint256 fromBucketDebtAccumulator = fromBucket.debtAccumulator;

                for (
                    uint256 debitorIndex = 0;
                    debitorIndex < totalDebitors;
                    debitorIndex++
                ) {
                    address debitor = fromBucket.indexToDebitor[debitorIndex];
                    uint256 debtToReallocate = min(
                        fromBucket.debt[debitor],
                        toBucket.onDeposit
                    );
                    if (debtToReallocate > 0) {
                        require(
                            toBucket.onDeposit >= debtToReallocate &&
                                debtToReallocate <= fromBucket.debt[debitor],
                            "no-debt-to-reallocate-or-low-liquidity"
                        );

                        // update accounting of encumbered collateral
                        borrowers[debitor].collateralEncumbered +=
                            debtToReallocate /
                            fromBucketPrice -
                            debtToReallocate /
                            _price;

                        if (
                            toBucket.debt[debitor] == 0 &&
                            toBucket.debitorToIndex[debitor] == 0
                        ) {
                            toBucket.indexToDebitor[
                                toBucket.totalDebitors
                            ] = debitor;
                            toBucket.debitorToIndex[debitor] = toBucket
                                .totalDebitors;
                            toBucket.totalDebitors += 1;
                        }
                        toBucket.debt[debitor] += debtToReallocate;
                        toBucketDebtAccumulator += debtToReallocate;

                        fromBucket.debt[debitor] -= debtToReallocate;
                        if (fromBucket.debt[debitor] == 0) {
                            delete fromBucket.indexToDebitor[
                                fromBucket.debitorToIndex[debitor]
                            ];
                            delete fromBucket.debitorToIndex[debitor];
                            fromBucket.totalDebitors -= 1;
                        }
                        fromBucketDebtAccumulator -= debtToReallocate;

                        // pay off the moved debt
                        fromBucket.onDeposit += debtToReallocate;
                        toBucket.onDeposit -= debtToReallocate;
                    }
                    if (toBucket.onDeposit == 0) {
                        break;
                    }
                }

                fromBucket.debtAccumulator = fromBucketDebtAccumulator;
            }
        }

        toBucket.debtAccumulator = toBucketDebtAccumulator;
        if (toBucket.onDeposit == 0) {
            return;
        }

        quoteToken.transferFrom(msg.sender, address(this), _amount);
        emit QuoteTokenDeposit(msg.sender, _amount, quoteTokenAccumulator);
    }

    function withdrawQuoteToken(uint256 _amount) external {}

    function borrow(uint256 _amount)
        external
        updateBorrowerInflator(msg.sender)
    {
        require(
            collateralBalances[msg.sender] > 0 &&
                borrowers[msg.sender].collateralEncumbered <
                collateralBalances[msg.sender],
            "undercollateralized-borrower"
        );

        uint256 amountRemaining = _amount;

        for (uint256 bucketId = hup() + 1; bucketId > 0; bucketId--) {
            Bucket storage bucket = buckets[bucketId];

            if (bucket.onDeposit > 0) {
                uint256 priceAmount = min(bucket.onDeposit, amountRemaining);
                uint256 priceCost = priceAmount / indexToPrice(bucketId);

                require(
                    bucket.onDeposit >= priceAmount &&
                        borrowers[msg.sender].collateralEncumbered + priceCost <
                        collateralBalances[msg.sender],
                    "insufficient-funds"
                );

                bucket.onDeposit -= priceAmount;
                if (
                    bucket.debt[msg.sender] == 0 &&
                    bucket.debitorToIndex[msg.sender] == 0
                ) {
                    bucket.indexToDebitor[bucket.totalDebitors] = msg.sender;
                    bucket.debitorToIndex[msg.sender] = bucket.totalDebitors;
                    bucket.totalDebitors += 1;
                }
                bucket.debt[msg.sender] += priceAmount;
                bucket.debtAccumulator += priceAmount;
                quoteBalances[msg.sender] += priceAmount;

                borrowers[msg.sender].debt += priceAmount;
                borrowers[msg.sender].collateralEncumbered += priceCost;

                amountRemaining -= priceAmount;

                if (amountRemaining == 0) {
                    break;
                }
            }
        }

        borrowers[msg.sender].inflatorSnapshot = borrowerInflator;
        require(amountRemaining == 0, "amount-remaining");

        quoteToken.transfer(msg.sender, _amount);
        emit Borrow(msg.sender, _amount, quoteTokenAccumulator);
    }

    function actualUtilization() public view returns (uint256) {
        return 0;
    }

    function targetUtilization() public view returns (uint256) {
        return 0;
    }

    function nextBorrowerInflator() public view returns (uint256 inflator) {
        uint256 secondsSinceLastUpdate = block.timestamp -
            lastBorrowerInflatorUpdate;
        uint256 spr = previousRate / SECONDS_PER_YEAR;
        inflator = wmul(
            borrowerInflator,
            1 * WAD + (spr * secondsSinceLastUpdate)
        );
    }

    function collateralAvailableToWithdraw(address _address)
        public
        view
        returns (uint256 collateral)
    {
        collateral =
            collateralBalances[_address] -
            _pendingEncumberedCollateral(_address);
    }

    function lup() private view returns (uint256) {
        for (
            uint256 bucketIndex = 0;
            bucketIndex < PRICE_COUNT;
            bucketIndex++
        ) {
            if (buckets[bucketIndex].totalDebitors > 0) {
                return bucketIndex;
            }
        }
        return 0;
    }

    function hup() private view returns (uint256) {
        for (
            uint256 bucketIndex = PRICE_COUNT;
            bucketIndex > 0;
            bucketIndex--
        ) {
            if (buckets[bucketIndex].onDeposit > 0) {
                return bucketIndex;
            }
        }
        return 0;
    }

    function bucketInfo(uint256 _id)
        public
        view
        returns (
            uint256,
            uint256,
            uint256,
            uint256
        )
    {
        return (
            buckets[_id].onDeposit,
            buckets[_id].totalDebitors,
            buckets[_id].debtAccumulator,
            indexToPrice(_id)
        );
    }

    function userInfo(address _usr)
        public
        view
        returns (
            uint256,
            uint256,
            uint256,
            uint256,
            uint256
        )
    {
        return (
            collateralBalances[_usr],
            quoteBalances[_usr],
            borrowers[_usr].collateralEncumbered,
            borrowers[_usr].debt,
            borrowers[_usr].inflatorSnapshot
        );
    }

    function userDebt(address _usr, uint256 _id) public view returns (uint256) {
        return buckets[_id].debt[_usr];
    }

    function _pendingEncumberedCollateral(address _usr)
        public
        view
        returns (uint256 amt)
    {
        amt = wmul(
            borrowers[_usr].collateralEncumbered,
            1 * WAD + nextBorrowerInflator() - borrowers[_usr].inflatorSnapshot
        );
    }
}
