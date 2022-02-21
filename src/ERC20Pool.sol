// SPDX-License-Identifier: MIT

pragma solidity 0.8.10;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "./libraries/Maths.sol";
import "./libraries/Buckets.sol";

interface IPool {
    function addQuoteToken(uint256 _amount, uint256 _price) external;

    function removeQuoteToken(uint256 _amount, uint256 _price) external;

    function addCollateral(uint256 _amount) external;

    function removeCollateral(uint256 _amount) external;

    function borrow(uint256 _amount, uint256 _stopPrice) external;

    function payBack(uint256 _amount) external;
}

contract ERC20Pool is IPool {
    using SafeERC20 for IERC20;
    using Buckets for mapping(uint256 => Buckets.Bucket);

    struct BorrowerInfo {
        uint256 debt;
        uint256 collateralDeposited;
        uint256 collateralEncumbered;
    }

    uint256 public constant MAX_PRICE = 7000 * 10**18;
    uint256 public constant MIN_PRICE = 1000 * 10**18;
    uint256 public constant COUNT = 6000;
    uint256 public constant STEP = (MAX_PRICE - MIN_PRICE) / COUNT;

    IERC20 public immutable collateral;
    IERC20 public immutable quoteToken;

    uint256 public hup;

    // buckets: price -> Bucket
    mapping(uint256 => Buckets.Bucket) public buckets;

    // lenders book: lender address -> price bucket -> amount
    mapping(address => mapping(uint256 => uint256)) public lenders;
    // lender balance: lender address -> total amount
    mapping(address => uint256) public lenderBalance;

    // borrowers book: borrower address -> BorrowerInfo
    mapping(address => BorrowerInfo) public borrowers;

    uint256 public totalCollateral;
    uint256 public totalQuoteToken;
    uint256 public totalDebt;
    uint256 public totalEncumberedCollateral;

    event AddQuoteToken(
        address lender,
        uint256 price,
        uint256 amount,
        uint256 hup
    );
    event RemoveQuoteToken(address lender, uint256 price, uint256 amount);
    event AddCollateral(address borrower, uint256 amount);
    event RemoveCollateral(address borrower, uint256 amount);
    event Borrow(address borrower, uint256 price, uint256 amount);
    event PayBack(address borrower, uint256 price, uint256 amount);

    constructor(IERC20 _collateral, IERC20 _quoteToken) {
        collateral = _collateral;
        quoteToken = _quoteToken;
    }

    function addQuoteToken(uint256 _amount, uint256 _price) external {
        require(isValidPrice(_price), "ajna/invalid-bucket-price");

        lenders[msg.sender][_price] += _amount;
        lenderBalance[msg.sender] += _amount;

        hup = buckets.addPriceBucket(_amount, _price, hup);
        totalQuoteToken += _amount;

        quoteToken.safeTransferFrom(msg.sender, address(this), _amount);
        emit AddQuoteToken(msg.sender, _price, _amount, hup);
    }

    function removeQuoteToken(uint256 _amount, uint256 _price) external {
        require(isValidPrice(_price), "Not a valid bucket price");
        require(
            lenders[msg.sender][_price] >= _amount,
            "Exceeds lended amount"
        );
        require(
            _amount <= buckets.onDeposit(_price),
            "Not enough liquidity in bucket"
        );

        lenders[msg.sender][_price] -= _amount;
        lenderBalance[msg.sender] -= _amount;
        buckets[_price].amount -= _amount;

        quoteToken.safeTransfer(msg.sender, _amount);
        emit RemoveQuoteToken(msg.sender, _price, _amount);
    }

    function addCollateral(uint256 _amount) external {
        borrowers[msg.sender].collateralDeposited += _amount;
        totalCollateral += _amount;

        collateral.safeTransferFrom(msg.sender, address(this), _amount);
        emit AddCollateral(msg.sender, _amount);
    }

    function removeCollateral(uint256 _amount) external {
        require(
            borrowers[msg.sender].collateralDeposited -
                borrowers[msg.sender].collateralEncumbered >
                _amount,
            "Not enough collateral"
        );

        borrowers[msg.sender].collateralDeposited -= _amount;
        totalCollateral -= _amount;

        collateral.safeTransfer(msg.sender, _amount);
        emit RemoveCollateral(msg.sender, _amount);
    }

    function borrow(uint256 _amount, uint256 _stopPrice) external {
        require(
            _amount <= totalQuoteToken - totalDebt,
            "ajna/not-enough-liquidity"
        );

        hup = buckets.borrow(_amount, _stopPrice, hup);

        BorrowerInfo storage borrower = borrowers[msg.sender];
        require(
            borrower.collateralDeposited - borrower.collateralEncumbered >
                Maths.wdiv(_amount, hup),
            "ajna/not-enough-collateral"
        );
        borrower.debt += _amount;
        borrower.collateralEncumbered += Maths.wdiv(_amount, hup);

        totalDebt += _amount;
        totalEncumberedCollateral += Maths.wdiv(_amount, hup);

        quoteToken.safeTransfer(msg.sender, _amount);
        emit Borrow(msg.sender, hup, _amount);
    }

    function payBack(uint256 _amount) external {
        require(
            _amount <= borrowers[msg.sender].debt,
            "Amount greater than debt"
        );
        borrowers[msg.sender].debt -= _amount;
        uint256 poolPrice = getPoolPrice();

        if (
            borrowers[msg.sender].collateralEncumbered >=
            Maths.wdiv(_amount, poolPrice)
        ) {
            // pay back entire amount
            borrowers[msg.sender].collateralEncumbered -= Maths.wdiv(
                _amount,
                poolPrice
            );
            totalEncumberedCollateral -= Maths.wdiv(_amount, poolPrice);
        } else {
            // pay back only amount needed to cover encumbered collateral
            _amount = Maths.wmul(
                borrowers[msg.sender].collateralEncumbered,
                poolPrice
            );
            totalEncumberedCollateral -= borrowers[msg.sender]
                .collateralEncumbered;
            borrowers[msg.sender].collateralEncumbered = 0;
        }

        buckets[hup].amount += _amount;
        totalDebt -= _amount;

        quoteToken.safeTransfer(msg.sender, _amount);
        emit PayBack(msg.sender, poolPrice, _amount);
    }

    function estimatePriceForLoan(uint256 _amount)
        public
        view
        returns (uint256)
    {
        if (_amount > totalQuoteToken - totalDebt) {
            return 0;
        }

        return buckets.estimatePrice(_amount, hup);
    }

    function isValidPrice(uint256 _price) public pure returns (bool) {
        if ((_price - MIN_PRICE) % STEP > 0) {
            return false;
        }
        uint256 index = (_price - MIN_PRICE) / STEP;
        return (index >= 0 && index < COUNT);
    }

    function getPoolPrice() public view returns (uint256) {
        if (totalDebt > 0) {
            return Maths.wdiv(totalDebt, totalEncumberedCollateral);
        }
        return hup;
    }

    function getMinimumPoolPrice() public view returns (uint256) {
        if (totalDebt > 0) {
            return Maths.wdiv(totalDebt, totalCollateral);
        }
        return hup;
    }

    function getPoolCollateralization() public view returns (uint256) {
        return Maths.wdiv(totalCollateral, totalEncumberedCollateral);
    }

    function getCollateralization(address _borrower)
        public
        view
        returns (uint256)
    {
        return
            Maths.wdiv(
                borrowers[_borrower].collateralDeposited -
                    borrowers[_borrower].collateralEncumbered,
                getPoolPrice()
            );
    }

    function getActualUtilization() public view returns (uint256) {
        return Maths.wdiv(totalQuoteToken, totalDebt + totalQuoteToken);
    }

    function getTargetUtilization() public view returns (uint256) {
        return Maths.wdiv(1, getPoolCollateralization());
    }
}
