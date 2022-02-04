// SPDX-License-Identifier: MIT

pragma solidity 0.8.10;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IPerpPool {
    function depositCollateral(uint256 _amount) external;
    function withdrawCollateral(uint256 _amount) external;
    function depositQuoteToken(uint256 _amount, uint256 _price) external;
    function borrow(uint256 _amount) external;
    function actualUtilization() external view returns (uint256);
    function targetUtilization() external view returns (uint256);
}

contract ERC20PerpPool is IPerpPool {

    struct Balance {
        uint256 collateral;
        uint256 quote;
    }

    struct PriceBucket {
        mapping(address => uint256) lpTokenBalance;
        uint256 onDeposit;
        mapping(address => uint256) debt;
        uint256 accumulator;
    }

    struct BorrowerInfo {
        address borrower;
        uint256 collateralEncumbered;
        uint256 debt;
        uint256 inflatorSnapshot;
    }

    enum PricePointer {
        HighestUtilizable,
        LowestUtilized
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

    event CollateralDeposited(address depositor, uint256 amount, uint256 collateralAccumulator);
    event CollateralWithdrawn(address depositor, uint256 amount, uint256 collateralAccumulator);

    uint public constant SECONDS_PER_YEAR = 3600 * 24 * 365;

    IERC20 public immutable collateralToken;
    IERC20 public immutable quoteToken;

    mapping(address => Balance) public balances;
    uint256 public collateralAccumulator;
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
        balances[msg.sender].collateral += _amount;
        collateralAccumulator += _amount;

        collateralToken.transferFrom(msg.sender, address(this), _amount);
        emit CollateralDeposited(msg.sender, _amount, collateralAccumulator);
    }

    function withdrawCollateral(uint256 _amount) external updateBorrowerInflator(msg.sender) {
        require(_amount <= balances[msg.sender].collateral, "Not enough collateral");

        balances[msg.sender].collateral -= _amount;
        collateralAccumulator -= _amount;

        collateralToken.transferFrom(address(this), msg.sender, _amount);
        emit CollateralWithdrawn(msg.sender, _amount, collateralAccumulator);
    }

    function depositQuoteToken(uint256 _amount, uint256 _price) external {
    }

    function borrow(uint256 _amount) external {
    }

    function actualUtilization() public view returns (uint256) {
        return 0;
    }

    function targetUtilization() public view returns (uint256) {
        return 0;
    }

    function borrowerInflatorPending() public view returns (uint256) {
        uint256 secondsSinceLastUpdate = block.timestamp - lastBorrowerInflatorUpdate;
        uint256 borrowerSpr = previousRate / SECONDS_PER_YEAR;
        return borrowerInflator * 1 + (borrowerSpr * secondsSinceLastUpdate);
    }
    
}