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

contract ERC20PerpPool is IPerpPool {
    struct PriceBucket {
        mapping(address => uint256) lpTokenBalance;
        uint256 onDeposit;
        uint256 totalDebitors;
        mapping(uint256 => address) indexToDebitor;
        mapping(address => uint256) debitorToIndex;
        mapping(address => uint256) debt;
        uint256 debtAccumulator;
        uint256 price;
    }

    struct BorrowerInfo {
        uint256 collateralEncumbered;
        uint256 debt;
        uint256 inflatorSnapshot;
    }

    // --- Math ---
    uint256 private constant WAD = 10**18;

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

    uint256 public constant HIGHEST_UTILIZABLE_PRICE = 1;
    uint256 public constant LOWEST_UTILIZED_PRICE = 2;

    uint256 public constant SECONDS_PER_YEAR = 3600 * 24 * 365;
    uint256 public constant MAX_PRICE = 5000 * WAD;
    uint256 public constant MIN_PRICE = 1000 * WAD;
    uint256 public constant PRICE_COUNT = 15;
    uint256 public constant PRICE_STEP = (MAX_PRICE - MIN_PRICE) / PRICE_COUNT;

    IERC20 public immutable collateralToken;
    mapping(address => uint256) public collateralBalances;
    uint256 public collateralAccumulator;

    IERC20 public immutable quoteToken;
    mapping(address => uint256) public quoteBalances;
    uint256 public quoteTokenAccumulator;

    mapping(uint256 => uint256) public priceToIndex;
    mapping(uint256 => uint256) public indexToPrice;
    mapping(uint256 => uint256) public pointerToIndex;

    mapping(uint256 => PriceBucket) public buckets;

    mapping(address => BorrowerInfo) public borrowers;

    uint256 public borrowerInflator;
    uint256 public lastBorrowerInflatorUpdate;
    uint256 public previousRate;
    uint256 public previousRateUpdate;

    uint256 public debtAccumulatorCollateral;
    uint256 public debtAccumulatorQuote;

    constructor(IERC20 _collateralToken, IERC20 _quoteToken) {
        collateralToken = _collateralToken;
        quoteToken = _quoteToken;

        borrowerInflator = 1 * WAD;
        lastBorrowerInflatorUpdate = block.timestamp;

        previousRate = wdiv(5, 100);
        previousRateUpdate = block.timestamp;

        for (uint256 i = 0; i < PRICE_COUNT; i++) {
            uint256 price = MIN_PRICE + (PRICE_STEP * i);
            priceToIndex[price] = i;
            indexToPrice[i] = price;

            buckets[i].price = price;
        }
    }

    modifier updateBorrowerInflator(address account) {
        _;
        uint256 secondsSinceLastUpdate = block.timestamp -
            lastBorrowerInflatorUpdate;
        if (secondsSinceLastUpdate == 0) {
            return;
        }

        borrowerInflator = borrowerInflatorPending();
        lastBorrowerInflatorUpdate = block.timestamp;
    }

    function depositCollateral(uint256 _amount)
        external
        updateBorrowerInflator(msg.sender)
    {
        require(
            collateralToken.balanceOf(msg.sender) >= _amount,
            "Not enough funds to deposit"
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
            "Not enough collateral to withdraw"
        );

        collateralBalances[msg.sender] -= _amount;
        collateralAccumulator -= _amount;

        collateralToken.transferFrom(address(this), msg.sender, _amount);
        emit CollateralWithdraw(msg.sender, _amount, collateralAccumulator);
    }

    function depositQuoteToken(uint256 _amount, uint256 _price) external {
        require(
            quoteToken.balanceOf(msg.sender) >= _amount,
            "Not enough funds to deposit"
        );

        uint256 depositIndex = priceToIndex[_price];
        require(depositIndex > 0, "Price bucket not found");

        PriceBucket storage toBucket = buckets[depositIndex];
        toBucket.lpTokenBalance[msg.sender] += _amount;
        toBucket.onDeposit += _amount;

        quoteBalances[msg.sender] += _amount;
        quoteTokenAccumulator += _amount;

        uint256 lupIndex = pointerToIndex[LOWEST_UTILIZED_PRICE];
        if (depositIndex > lupIndex) {
            for (uint256 i = lupIndex; i < depositIndex; i++) {
                require(
                    buckets[i].price < toBucket.price,
                    "To bucket price lower than from bucket price"
                );

                uint256 totalDebitors = buckets[i].totalDebitors;

                for (
                    uint256 debitorIndex = 0;
                    debitorIndex < totalDebitors;
                    debitorIndex++
                ) {
                    address debitor = buckets[i].indexToDebitor[debitorIndex];
                    uint256 debtToReallocate = min(
                        buckets[i].debt[debitor],
                        toBucket.onDeposit
                    );
                    if (debtToReallocate > 0) {
                        require(
                            debtToReallocate <= buckets[i].debt[debitor],
                            "No debt to reallocate"
                        );
                        require(
                            toBucket.onDeposit >= debtToReallocate,
                            "Insufficent liquidity to reallocate"
                        );

                        // update accounting of encumbered collateral
                        borrowers[debitor].collateralEncumbered +=
                            debtToReallocate /
                            buckets[i].price -
                            debtToReallocate /
                            toBucket.price;

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
                        toBucket.debtAccumulator += debtToReallocate;

                        buckets[i].debt[debitor] -= debtToReallocate;
                        if (buckets[i].debt[debitor] == 0) {
                            delete buckets[i].indexToDebitor[
                                buckets[i].debitorToIndex[debitor]
                            ];
                            delete buckets[i].debitorToIndex[debitor];
                            buckets[i].totalDebitors -= 1;
                        }
                        buckets[i].debtAccumulator -= debtToReallocate;

                        // pay off the moved debt
                        buckets[i].onDeposit += debtToReallocate;
                        toBucket.onDeposit -= debtToReallocate;

                        if (priceToIndex[buckets[i].price] >= lupIndex) {
                            while (buckets[lupIndex].debtAccumulator == 0) {
                                lupIndex += 1;
                            }
                            pointerToIndex[LOWEST_UTILIZED_PRICE] = lupIndex;
                        }

                        uint256 hupIndex = depositIndex;
                        while (toBucket.onDeposit == 0) {
                            hupIndex -= 1;
                        }
                        pointerToIndex[HIGHEST_UTILIZABLE_PRICE] = hupIndex;
                    }
                    if (toBucket.onDeposit == 0) {
                        break;
                    }
                }
            }
        }

        if (toBucket.onDeposit == 0) {
            return;
        }
        pointerToIndex[HIGHEST_UTILIZABLE_PRICE] = max(
            pointerToIndex[HIGHEST_UTILIZABLE_PRICE],
            depositIndex
        );

        quoteToken.transferFrom(msg.sender, address(this), _amount);
        emit QuoteTokenDeposit(msg.sender, _amount, quoteTokenAccumulator);
    }

    function withdrawQuoteToken(uint256 _amount) external {}

    function borrow(uint256 _amount)
        external
        updateBorrowerInflator(msg.sender)
    {
        require(
            collateralBalances[msg.sender] > 0,
            "No collalteral for borrower"
        );
        require(
            borrowers[msg.sender].collateralEncumbered <
                collateralBalances[msg.sender],
            "Borrower is already undercollateralized"
        );

        uint256 amountRemaining = _amount;
        uint256 lastBucketBorrowedFrom;

        for (
            uint256 bucketId = pointerToIndex[HIGHEST_UTILIZABLE_PRICE] + 1;
            bucketId > 0;
            bucketId--
        ) {
            PriceBucket storage bucket = buckets[bucketId];

            if (bucket.onDeposit > 0) {
                uint256 priceAmount = min(bucket.onDeposit, amountRemaining);
                uint256 priceCost = priceAmount / bucket.price;

                require(
                    borrowers[msg.sender].collateralEncumbered + priceCost <
                        collateralBalances[msg.sender],
                    "Insufficient collateral to fund loan"
                );
                require(
                    bucket.onDeposit >= priceAmount,
                    "Not enough funds deposited in bucket"
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

                amountRemaining -= priceAmount;
                debtAccumulatorCollateral += priceCost;
                debtAccumulatorQuote += priceAmount;
                borrowers[msg.sender].debt += priceAmount;
                borrowers[msg.sender].collateralEncumbered += priceCost;

                lastBucketBorrowedFrom = bucketId;

                if (amountRemaining == 0) {
                    break;
                }
            }
        }

        borrowers[msg.sender].inflatorSnapshot = borrowerInflator;

        require(amountRemaining == 0, "Amount remaining greater than 0");

        if (lastBucketBorrowedFrom > 0) {
            pointerToIndex[LOWEST_UTILIZED_PRICE] = min(
                pointerToIndex[LOWEST_UTILIZED_PRICE],
                lastBucketBorrowedFrom
            );

            while (
                buckets[lastBucketBorrowedFrom].onDeposit == 0 &&
                lastBucketBorrowedFrom > 0
            ) {
                lastBucketBorrowedFrom -= 1;
            }
            if (buckets[lastBucketBorrowedFrom].onDeposit > 0) {
                pointerToIndex[
                    HIGHEST_UTILIZABLE_PRICE
                ] = lastBucketBorrowedFrom;
            }
        }

        quoteToken.transfer(msg.sender, _amount);
        emit Borrow(msg.sender, _amount, quoteTokenAccumulator);
    }

    function actualUtilization() public view returns (uint256) {
        return 0;
    }

    function targetUtilization() public view returns (uint256) {
        return 0;
    }

    function borrowerInflatorPending()
        public
        view
        returns (uint256 pendingBorrowerInflator)
    {
        uint256 secondsSinceLastUpdate = block.timestamp -
            lastBorrowerInflatorUpdate;
        uint256 borrowerSpr = previousRate / SECONDS_PER_YEAR;

        pendingBorrowerInflator = wmul(
            borrowerInflator,
            1 * WAD + (borrowerSpr * secondsSinceLastUpdate)
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

    function addressBalances(address _address)
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
            collateralBalances[_address],
            quoteBalances[_address],
            borrowers[_address].collateralEncumbered,
            borrowers[_address].debt,
            borrowers[_address].inflatorSnapshot
        );
    }

    function bucketInfoForAddress(uint256 _bucketId, address _address)
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
            buckets[_bucketId].onDeposit,
            buckets[_bucketId].totalDebitors,
            buckets[_bucketId].debt[_address],
            buckets[_bucketId].debtAccumulator,
            buckets[_bucketId].price
        );
    }

    function _pendingEncumberedCollateral(address _address)
        public
        view
        returns (uint256 collateral)
    {
        collateral = wmul(
            borrowers[_address].collateralEncumbered,
            1 *
                WAD +
                borrowerInflatorPending() -
                borrowers[_address].inflatorSnapshot
        );
    }
}
