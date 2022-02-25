// SPDX-License-Identifier: MIT

pragma solidity 0.8.11;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {BitMaps} from "@openzeppelin/contracts/utils/structs/BitMaps.sol";

import "./libraries/Maths.sol";
import "./libraries/Buckets.sol";

interface IPool {
    function addQuoteToken(uint256 _amount, uint256 _price) external;

    function removeQuoteToken(uint256 _amount, uint256 _price) external;

    function addCollateral(uint256 _amount) external;

    function removeCollateral(uint256 _amount) external;

    function borrow(uint256 _amount, uint256 _stopPrice) external;

    function payBack(uint256 _amount) external;

    function isBucketInitialized(uint256 _price) external returns (bool);

    function ensureBucket(uint256 _prevPrice, uint256 _price) external;

    function getNextValidPrice(uint256 _price) external returns (uint256);
}

contract ERC20Pool is IPool {
    using SafeERC20 for IERC20;
    using Buckets for mapping(uint256 => Buckets.Bucket);

    struct BorrowerInfo {
        uint256 debt;
        uint256 collateralDeposited;
        uint256 collateralEncumbered;
        uint256 inflatorSnapshot;
    }

    uint256 public constant SECONDS_PER_YEAR = 3600 * 24 * 365;
    uint256 public constant MAX_PRICE = 7000 * 10**18;
    uint256 public constant MIN_PRICE = 1 * 10**18;
    uint256 public constant COUNT = 7000;

    IERC20 public immutable collateral;
    IERC20 public immutable quoteToken;

    uint256 public hdp;
    uint256 public lup;

    // buckets: price -> Bucket
    mapping(uint256 => Buckets.Bucket) public buckets;
    BitMaps.BitMap private bitmap;

    // lenders book: lender address -> price bucket -> amount
    mapping(address => mapping(uint256 => uint256)) public lenders;
    // lender balance: lender address -> total amount
    mapping(address => uint256) public lenderBalance;

    // borrowers book: borrower address -> BorrowerInfo
    mapping(address => BorrowerInfo) public borrowers;

    uint256 public borrowerInflator = Maths.wad(1);
    uint256 public lastBorrowerInflatorUpdate = block.timestamp;
    uint256 public previousRate = Maths.wdiv(5, 100);
    uint256 public previousRateUpdate = block.timestamp;

    uint256 public totalCollateral;
    uint256 public totalQuoteToken;
    uint256 public totalDebt;
    uint256 public totalEncumberedCollateral;

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
    event PayBack(address borrower, uint256 price, uint256 amount);

    constructor(IERC20 _collateral, IERC20 _quoteToken) {
        collateral = _collateral;
        quoteToken = _quoteToken;
    }

    function addQuoteToken(uint256 _amount, uint256 _price) external {
        require(isValidPrice(_price), "ajna/invalid-bucket-price");

        lenders[msg.sender][_price] += _amount;
        lenderBalance[msg.sender] += _amount;

        // create bucket if not initialized yet
        if (!BitMaps.get(bitmap, _price)) {
            hdp = buckets.initializeBucket(hdp, _price);
            BitMaps.setTo(bitmap, _price, true);
        }

        // deposit amount
        buckets[_price].amount += _amount;
        totalQuoteToken += _amount;

        // reallocate debt if needed
        if (totalDebt > 0 && _price > lup) {
            lup = buckets.reallocateDebt(_amount, _price, hdp, lup);
        }

        quoteToken.safeTransferFrom(msg.sender, address(this), _amount);
        emit AddQuoteToken(msg.sender, _price, _amount, lup);
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
        updateBorrowerInflator();
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

        BorrowerInfo storage borrower = borrowers[msg.sender];

        require(
            borrower.collateralDeposited > borrower.collateralEncumbered,
            "ajna/not-enough-collateral"
        );

        // if first loan then borrow at hdp
        uint256 loanCost;
        if (lup == 0) {
            (lup, loanCost) = buckets.borrow(_amount, _stopPrice, hdp);
        } else {
            (lup, loanCost) = buckets.borrow(_amount, _stopPrice, lup);
        }

        require(
            borrower.collateralDeposited - borrower.collateralEncumbered >
                loanCost,
            "ajna/not-enough-collateral"
        );
        borrower.debt += _amount;
        borrower.collateralEncumbered += loanCost;
        updateBorrowerInflator();
        if (borrower.inflatorSnapshot == 0) {
            borrower.inflatorSnapshot = borrowerInflator;
        }

        totalDebt += _amount;
        totalEncumberedCollateral += loanCost;

        quoteToken.safeTransfer(msg.sender, _amount);
        emit Borrow(msg.sender, lup, _amount);
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

        buckets[lup].amount += _amount;
        totalDebt -= _amount;

        quoteToken.safeTransfer(msg.sender, _amount);
        emit PayBack(msg.sender, poolPrice, _amount);
    }

    // -------------------- Bucket related functions --------------------

    function isBucketInitialized(uint256 _price) public view returns (bool) {
        return BitMaps.get(bitmap, _price);
    }

    function ensureBucket(uint256 _prevPrice, uint256 _price) public {
        require(_prevPrice > _price, "ajna/price-lower-than-prev");
        require(BitMaps.get(bitmap, _prevPrice), "ajna/prev-not-initialized");
        require(!BitMaps.get(bitmap, _price), "ajna/price-already-initialized");

        buckets.initializeBucket(_prevPrice, _price);
        BitMaps.setTo(bitmap, _price, true);
    }

    function getNextValidPrice(uint256 _price) public view returns (uint256) {
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

    function getPoolPrice() public view returns (uint256) {
        if (totalDebt > 0) {
            return Maths.wdiv(totalDebt, totalEncumberedCollateral);
        }
        return lup;
    }

    function getMinimumPoolPrice() public view returns (uint256) {
        if (totalDebt > 0) {
            return Maths.wdiv(totalDebt, totalCollateral);
        }
        return lup;
    }

    function getPoolCollateralization() public view returns (uint256) {
        if (totalDebt > 0) {
            return Maths.wdiv(totalCollateral, totalEncumberedCollateral);
        }
        return Maths.wad(1);
    }

    function getPoolActualUtilization() public view returns (uint256) {
        return Maths.wdiv(totalDebt, totalQuoteToken);
    }

    function getPoolTargetUtilization() public view returns (uint256) {
        uint256 poolCollateralization = getPoolCollateralization();
        if (poolCollateralization > 0) {
            return Maths.wdiv(Maths.wad(1), getPoolCollateralization());
        }
        return Maths.wad(1);
    }

    function updateBorrowerInflator() internal {
        if (block.timestamp - lastBorrowerInflatorUpdate == 0) {
            return;
        }

        borrowerInflator = nextBorrowerInflator();
        lastBorrowerInflatorUpdate = block.timestamp;
    }

    function nextBorrowerInflator() public view returns (uint256 inflator) {
        uint256 secondsSinceLastUpdate = block.timestamp -
            lastBorrowerInflatorUpdate;
        uint256 spr = previousRate / SECONDS_PER_YEAR;
        inflator = Maths.wmul(
            borrowerInflator,
            Maths.wad(1) + (spr * secondsSinceLastUpdate)
        );
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
            uint256
        )
    {
        BorrowerInfo memory borrower = borrowers[_borrower];
        uint256 collateralization = Maths.wdiv(
            borrower.collateralDeposited,
            borrower.collateralEncumbered
        ) - Maths.wad(1);

        return (
            borrower.debt,
            borrower.collateralDeposited,
            borrower.collateralEncumbered,
            collateralization,
            borrower.inflatorSnapshot
        );
    }

    function getPendingEncumberedCollateral(address _borrower)
        public
        view
        returns (uint256)
    {
        BorrowerInfo memory borrower = borrowers[_borrower];
        uint256 interestAdjustment = Maths.wad(1) +
            nextBorrowerInflator() -
            borrower.inflatorSnapshot;

        return
            Maths.wmul(
                borrowers[_borrower].collateralEncumbered,
                interestAdjustment
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
            return buckets.estimatePrice(_amount, hdp);
        }

        return buckets.estimatePrice(_amount, lup);
    }
}
