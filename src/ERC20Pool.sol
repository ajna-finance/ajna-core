// SPDX-License-Identifier: MIT

pragma solidity 0.8.11;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "./libraries/Maths.sol";
import {IPriceBuckets, PriceBuckets} from "./PriceBuckets.sol";
import "./libraries/BucketMath.sol";

interface IPool {
    function addQuoteToken(uint256 _amount, uint256 _price) external;

    function removeQuoteToken(uint256 _amount, uint256 _price) external;

    function addCollateral(uint256 _amount) external;

    function removeCollateral(uint256 _amount) external;

    function borrow(uint256 _amount, uint256 _stopPrice) external;

    function repay(uint256 _amount) external;

    function getNextValidPrice(uint256 _price) external returns (uint256);
}

contract ERC20Pool is IPool {
    using SafeERC20 for IERC20;

    struct BorrowerInfo {
        uint256 debt;
        uint256 collateralDeposited;
        uint256 inflatorSnapshot;
    }

    struct LenderInfo {
        uint256 amount;
        uint256 lpTokens;
    }

    uint256 public constant SECONDS_PER_YEAR = 3600 * 24 * 365;
    uint256 public constant MAX_PRICE = 7000 * 10**18;
    uint256 public constant MIN_PRICE = 1 * 10**18;
    uint256 public constant COUNT = 7000;

    IERC20 public immutable collateral;
    IERC20 public immutable quoteToken;

    uint256 public hdp;
    uint256 public lup;

    IPriceBuckets private immutable _buckets;

    // lenders book: lender address -> price bucket -> lender info struct
    mapping(address => mapping(uint256 => LenderInfo)) public lenders;
    // lender balance: lender address -> total amount
    mapping(address => uint256) public lenderBalance;

    // borrowers book: borrower address -> BorrowerInfo
    mapping(address => BorrowerInfo) public borrowers;

    uint256 public inflatorSnapshot = Maths.ONE_WAD;
    uint256 public lastBorrowerInflatorUpdate = block.timestamp;
    uint256 public previousRate = Maths.wdiv(5, 100);
    uint256 public previousRateUpdate = block.timestamp;

    uint256 public totalCollateral;

    uint256 public totalQuoteToken;
    uint256 public totalDebt;

    event AddQuoteToken(
        address lender,
        uint256 price,
        uint256 amount,
        uint256 lup
    );
    event RemoveQuoteToken(address lender, uint256 price, uint256 amount);
    event AddCollateral(address borrower, uint256 amount);
    event RemoveCollateral(address borrower, uint256 amount);
    event Borrow(address borrower, uint256 price, uint256 amount);
    event Repay(address borrower, uint256 price, uint256 amount);

    constructor(IERC20 _collateral, IERC20 _quoteToken) {
        collateral = _collateral;
        quoteToken = _quoteToken;

        _buckets = new PriceBuckets();
    }

    function addQuoteToken(uint256 _amount, uint256 _price) external {
        require(isValidPrice(_price), "ajna/invalid-bucket-price");

        accumulatePoolInterest();

        // create bucket if doesn't exist
        hdp = _buckets.ensureBucket(hdp, _price);

        // deposit amount
        uint256 lpTokens = _buckets.addToBucket(
            _price,
            _amount,
            inflatorSnapshot
        );

        // update lender info for current price bucket
        LenderInfo storage lender = lenders[msg.sender][_price];
        lender.amount += _amount;
        lender.lpTokens += lpTokens;

        // update lender balance
        lenderBalance[msg.sender] += _amount;

        // update quote token accumulator
        totalQuoteToken += _amount;

        // reallocate debt if needed
        if (totalDebt != 0 && _price >= lup) {
            lup = _buckets.reallocateDebt(
                _amount,
                _price,
                lup,
                inflatorSnapshot
            );
        }

        quoteToken.safeTransferFrom(msg.sender, address(this), _amount);
        emit AddQuoteToken(msg.sender, _price, _amount, lup);
    }

    function removeQuoteToken(uint256 _amount, uint256 _price) external {
        require(isValidPrice(_price), "ajna/invalid-bucket-price");

        LenderInfo storage lender = lenders[msg.sender][_price];
        require(lender.amount >= _amount, "ajna/lended-amount-excedeed");

        accumulatePoolInterest();

        totalQuoteToken -= _amount;
        require(
            getPoolCollateralization() > Maths.ONE_WAD,
            "ajna/pool-undercollateralized"
        );

        // remove from bucket
        uint256 lpTokens = _buckets.subtractFromBucket(
            _price,
            _amount,
            lender.amount,
            inflatorSnapshot
        );

        lender.amount -= _amount;
        lender.lpTokens -= lpTokens;

        lenderBalance[msg.sender] -= _amount;

        quoteToken.safeTransfer(msg.sender, _amount);
        emit RemoveQuoteToken(msg.sender, _price, _amount);
    }

    function addCollateral(uint256 _amount) external {
        accumulatePoolInterest();
        borrowers[msg.sender].collateralDeposited += _amount;
        totalCollateral += _amount;

        collateral.safeTransferFrom(msg.sender, address(this), _amount);
        emit AddCollateral(msg.sender, _amount);
    }

    function removeCollateral(uint256 _amount) external {
        accumulatePoolInterest();

        BorrowerInfo storage borrower = borrowers[msg.sender];
        accumulateBorrowerInterest(borrower);

        uint256 encumberedBorrowerCollateral;
        if (borrower.debt != 0) {
            encumberedBorrowerCollateral = Maths.wdiv(borrower.debt, lup);
        }

        require(
            borrower.collateralDeposited - encumberedBorrowerCollateral >=
                _amount,
            "ajna/not-enough-collateral"
        );

        borrower.collateralDeposited -= _amount;
        totalCollateral -= _amount;

        collateral.safeTransfer(msg.sender, _amount);
        emit RemoveCollateral(msg.sender, _amount);
    }

    function borrow(uint256 _amount, uint256 _stopPrice) external {
        require(
            _amount <= totalQuoteToken - totalDebt,
            "ajna/not-enough-liquidity"
        );

        accumulatePoolInterest();

        BorrowerInfo storage borrower = borrowers[msg.sender];
        accumulateBorrowerInterest(borrower);

        // if first loan then borrow at hdp
        uint256 curLup = lup;
        if (curLup == 0) {
            curLup = hdp;
        }

        uint256 encumberedBorrowerCollateral;
        if (borrower.debt != 0) {
            encumberedBorrowerCollateral = Maths.wdiv(borrower.debt, lup);
        }
        require(
            borrower.collateralDeposited > encumberedBorrowerCollateral,
            "ajna/not-enough-collateral"
        );

        uint256 loanCost;
        (lup, loanCost) = _buckets.borrow(
            _amount,
            _stopPrice,
            curLup,
            inflatorSnapshot
        );

        require(
            borrower.collateralDeposited >
                Maths.wdiv(borrower.debt + _amount, lup) &&
                borrower.collateralDeposited - Maths.wdiv(borrower.debt, lup) >
                loanCost,
            "ajna/not-enough-collateral"
        );
        borrower.debt += _amount;

        totalDebt += _amount;
        require(
            getPoolCollateralization() > Maths.ONE_WAD,
            "ajna/pool-undercollateralized"
        );

        quoteToken.safeTransfer(msg.sender, _amount);
        emit Borrow(msg.sender, lup, _amount);
    }

    function repay(uint256 _amount) external {
        uint256 availableAmount = quoteToken.balanceOf(msg.sender);
        require(availableAmount >= _amount, "ajna/no-funds-to-repay");

        BorrowerInfo storage borrower = borrowers[msg.sender];
        require(borrower.debt != 0, "ajna/no-debt-to-repay");
        accumulatePoolInterest();
        accumulateBorrowerInterest(borrower);

        uint256 debtToPay;
        (lup, debtToPay) = _buckets.repay(_amount, lup, inflatorSnapshot);

        if (debtToPay < borrower.debt && _amount >= borrower.debt) {
            debtToPay = borrower.debt;
        }

        if (debtToPay >= borrower.debt) {
            borrower.debt = 0;
            borrower.inflatorSnapshot = 0;
        } else {
            borrower.debt -= debtToPay;
        }

        totalDebt -= Maths.min(totalDebt, debtToPay);

        quoteToken.safeTransferFrom(msg.sender, address(this), debtToPay);
        emit Repay(msg.sender, lup, debtToPay);
    }

    function accumulatePoolInterest() private {
        if (block.timestamp - lastBorrowerInflatorUpdate != 0) {
            uint256 secondsSinceLastUpdate = block.timestamp -
                lastBorrowerInflatorUpdate;
            uint256 spr = previousRate / SECONDS_PER_YEAR;
            uint256 pendingInflator = Maths.wmul(
                inflatorSnapshot,
                Maths.ONE_WAD + (spr * secondsSinceLastUpdate)
            );

            totalDebt += Maths.wmul(
                totalDebt,
                Maths.wdiv(pendingInflator, inflatorSnapshot) - Maths.ONE_WAD
            );

            inflatorSnapshot = pendingInflator;
            lastBorrowerInflatorUpdate = block.timestamp;
        }
    }

    function accumulateBorrowerInterest(BorrowerInfo storage borrower) private {
        if (borrower.debt != 0 && borrower.inflatorSnapshot != 0) {
            uint256 pendingInterest = Maths.wmul(
                borrower.debt,
                inflatorSnapshot / borrower.inflatorSnapshot - 1
            );
            borrower.debt += pendingInterest;
            totalDebt += pendingInterest;
        }
        borrower.inflatorSnapshot = inflatorSnapshot;
    }

    // -------------------- Bucket related functions --------------------

    function bucketAt(uint256 _price)
        public
        view
        returns (
            uint256 price,
            uint256 up,
            uint256 down,
            uint256 amount,
            uint256 debt,
            uint256 inflatorSnapshot,
            uint256 lpOutstanding
        )
    {
        return _buckets.bucketAt(_price);
    }

    function getNextValidPrice(uint256 _price) public pure returns (uint256) {
        // dummy implementation, should calculate using maths library
        uint256 next = _price + 1;
        if (next > MAX_PRICE) {
            return 0;
        }
        return next;
    }

    // -------------------- Pool state related functions --------------------

    function isValidPrice(uint256 _price) public pure returns (bool) {
        // dummy implementation, should validate using maths library
        return (_price >= MIN_PRICE && _price < MAX_PRICE);
    }

    function getMinimumPoolPrice() public view returns (uint256) {
        if (totalDebt != 0) {
            return Maths.wdiv(totalDebt, totalCollateral);
        }
        return 0;
    }

    function getPoolCollateralization() public view returns (uint256) {
        uint256 encumberedCollateral = getEncumberedCollateral();
        if (encumberedCollateral != 0) {
            return Maths.wdiv(totalCollateral, encumberedCollateral);
        }
        return Maths.ONE_WAD;
    }

    function getEncumberedCollateral() public view returns (uint256) {
        if (lup != 0) {
            return Maths.wdiv(totalDebt, lup);
        }
        return 0;
    }

    function getPoolActualUtilization() public view returns (uint256) {
        return Maths.wdiv(totalDebt, totalQuoteToken);
    }

    function getPoolTargetUtilization() public view returns (uint256) {
        uint256 poolCollateralization = getPoolCollateralization();
        if (poolCollateralization != 0) {
            return Maths.wdiv(Maths.ONE_WAD, getPoolCollateralization());
        }
        return Maths.ONE_WAD;
    }

    // -------------------- Borrower related functions --------------------

    function getBorrowerInfo(address _borrower)
        public
        view
        returns (
            uint256,
            uint256,
            uint256,
            uint256,
            uint256,
            uint256,
            uint256
        )
    {
        BorrowerInfo memory borrower = borrowers[_borrower];
        uint256 borrowerDebt = borrower.debt;
        uint256 borrowerPendingDebt = borrower.debt;
        uint256 collateralEncumbered;
        uint256 collateralization;

        if (borrower.debt != 0 && borrower.inflatorSnapshot != 0) {
            uint256 secondsSinceLastUpdate = block.timestamp -
                lastBorrowerInflatorUpdate;
            uint256 spr = previousRate / SECONDS_PER_YEAR;
            uint256 pendingInflator = Maths.wmul(
                inflatorSnapshot,
                Maths.ONE_WAD + (spr * secondsSinceLastUpdate)
            );
            borrowerDebt += Maths.wmul(
                borrower.debt,
                inflatorSnapshot - borrower.inflatorSnapshot
            );
            borrowerPendingDebt += Maths.wmul(
                borrower.debt,
                pendingInflator - borrower.inflatorSnapshot
            );
            collateralEncumbered = Maths.wdiv(borrowerPendingDebt, lup);
            collateralization = Maths.wdiv(
                borrower.collateralDeposited,
                collateralEncumbered
            );
        }

        return (
            borrowerDebt,
            borrowerPendingDebt,
            borrower.collateralDeposited,
            collateralEncumbered,
            collateralization,
            borrower.inflatorSnapshot,
            inflatorSnapshot
        );
    }

    function estimatePriceForLoan(uint256 _amount)
        public
        view
        returns (uint256)
    {
        if (_amount > totalQuoteToken - totalDebt) {
            return 0;
        }

        if (lup == 0) {
            return _buckets.estimatePrice(_amount, hdp);
        }

        return _buckets.estimatePrice(_amount, lup);
    }
}
