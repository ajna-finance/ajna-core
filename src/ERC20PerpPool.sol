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
        mapping(uint256 => address) debitorIndex;
        mapping(address => uint256) debt;
        uint256 accumulator;
        uint256 price;
    }

    struct BorrowerInfo {
        address borrower;
        uint256 collateralEncumbered;
        uint256 debt;
        uint256 inflatorSnapshot;
    }

    // --- Math ---
    uint private constant WAD = 10 ** 18;

    function add(uint x, uint y) internal pure returns (uint z) {
        require((z = x + y) >= x, "ds-math-add-overflow");
    }
    function sub(uint x, uint y) internal pure returns (uint z) {
        require((z = x - y) <= x, "ds-math-sub-underflow");
    }
    function mul(uint x, uint y) internal pure returns (uint z) {
        require(y == 0 || (z = x * y) / y == x, "ds-math-mul-overflow");
    }
    function wmul(uint x, uint y) internal pure returns (uint z) {
        z = add(mul(x, y), WAD / 2) / WAD;
    }
    function wdiv(uint x, uint y) internal pure returns (uint z) {
        z = add(mul(x, WAD), y / 2) / y;
    }
    function max(uint x, uint y) internal pure returns (uint z) {
        z = x >= y ? x : y;
    }
    function min(uint x, uint y) internal pure returns (uint z) {
        z = x <= y ? x : y;
    }

    event CollateralDeposited(address depositor, uint256 amount, uint256 collateralAccumulator);
    event CollateralWithdrawn(address depositor, uint256 amount, uint256 collateralAccumulator);

    uint public constant HIGHEST_UTILIZABLE_PRICE = 1;
    uint public constant LOWEST_UTILIZABLE_PRICE = 2;

    uint public constant SECONDS_PER_YEAR = 3600 * 24 * 365;
    uint public constant MAX_PRICE = 1000 * WAD;
    uint public constant MIN_PRICE = 10 * WAD;
    uint public constant PRICE_COUNT = 10;
    uint public constant PRICE_STEP = (MAX_PRICE - MIN_PRICE) / PRICE_COUNT;

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

    uint256 public borrowerInflator;
    uint256 public lastBorrowerInflatorUpdate;
    uint256 public previousRate;
    uint256 public previousRateUpdate;

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
        uint256 secondsSinceLastUpdate = block.timestamp - lastBorrowerInflatorUpdate;
        if (secondsSinceLastUpdate == 0) {
            return;
        }

        borrowerInflator = borrowerInflatorPending();
        lastBorrowerInflatorUpdate = block.timestamp;
    }

    function depositCollateral(uint256 _amount) external updateBorrowerInflator(msg.sender) {
        collateralBalances[msg.sender] += _amount;
        collateralAccumulator += _amount;

        collateralToken.transferFrom(msg.sender, address(this), _amount);
        emit CollateralDeposited(msg.sender, _amount, collateralAccumulator);
    }

    function withdrawCollateral(uint256 _amount) external updateBorrowerInflator(msg.sender) {
        require(_amount <= collateralBalances[msg.sender], "Not enough collateral to withdraw");

        collateralBalances[msg.sender] -= _amount;
        collateralAccumulator -= _amount;

        collateralToken.transferFrom(address(this), msg.sender, _amount);
        emit CollateralWithdrawn(msg.sender, _amount, collateralAccumulator);
    }

    function depositQuoteToken(uint256 _amount, uint256 _price) external {

        uint256 depositBucketId = priceToIndex[_price];
        require(depositBucketId > 0, "Price bucket not found");

        PriceBucket storage bucket = buckets[depositBucketId];
        bucket.lpTokenBalance[msg.sender] += _amount;
        bucket.onDeposit += _amount;

        quoteBalances[msg.sender] += _amount;
        quoteTokenAccumulator += _amount;

        uint256 lupIndex = pointerToIndex[LOWEST_UTILIZABLE_PRICE];
        if (depositBucketId > lupIndex) {
            for (uint256 i = lupIndex; i < depositBucketId; i++) {
                require(buckets[i].price < bucket.price, "To bucket price not greater than from bucket price");

                for (uint256 debtIndex = 0; debtIndex < buckets[i].totalDebitors; debtIndex++) {
                    uint256 debtToReallocate = min(buckets[i].debt[buckets[i].debitorIndex[debtIndex]],
                                                bucket.onDeposit);
                    if (debtToReallocate > 0) {
                        // Todo reallocate debt here
                    }
                    if (bucket.onDeposit == 0) {
                        break;
                    }
                }

            }
        }

        if (bucket.onDeposit == 0) {
            return;
        }
        pointerToIndex[HIGHEST_UTILIZABLE_PRICE] = max(pointerToIndex[HIGHEST_UTILIZABLE_PRICE], depositBucketId);

    }

    function withdrawQuoteToken(uint256 _amount) external {
    }

    function borrow(uint256 _amount) external {
    }

    function actualUtilization() public view returns (uint256) {
        return 0;
    }

    function targetUtilization() public view returns (uint256) {
        return 0;
    }

    function borrowerInflatorPending() public view returns (uint256 pendingBorrowerInflator) {
        uint256 secondsSinceLastUpdate = block.timestamp - lastBorrowerInflatorUpdate;
        uint256 borrowerSpr = previousRate / SECONDS_PER_YEAR;

        pendingBorrowerInflator = wmul(borrowerInflator, 1 * WAD + (borrowerSpr * secondsSinceLastUpdate));
    }
    
}