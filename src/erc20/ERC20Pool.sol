// SPDX-License-Identifier: MIT

pragma solidity 0.8.14;

import { ERC20 }     from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { IERC20Pool } from "./interfaces/IERC20Pool.sol";

import { ScaledPool } from "../base/ScaledPool.sol";

import { Maths } from "../libraries/Maths.sol";

contract ERC20Pool is IERC20Pool, ScaledPool {
    using SafeERC20 for ERC20;

    /***********************/
    /*** State Variables ***/
    /***********************/

    // borrowers book: borrower address -> BorrowerInfo
    mapping(address => Borrower) public override borrowers;

    uint256 public override collateralScale;

    /****************************/
    /*** Initialize Functions ***/
    /****************************/

    function initialize(uint256 rate_) external {
        require(_poolInitializations == 0, "P:INITIALIZED");
        collateralScale = 10**(18 - collateral().decimals());
        quoteTokenScale = 10**(18 - quoteToken().decimals());

        inflatorSnapshot           = 10**18;
        lastInflatorSnapshotUpdate = block.timestamp;
        lenderInterestFactor       = 0.9 * 10**18;
        interestRate               = rate_;
        interestRateUpdate         = block.timestamp;
        minFee                     = 0.0005 * 10**18;

        // increment initializations count to ensure these values can't be updated
        _poolInitializations += 1;
    }

    /***********************************/
    /*** Borrower External Functions ***/
    /***********************************/

    function addCollateral(uint256 amount_, address oldPrev_, address newPrev_) external override {
        uint256 curDebt = _accruePoolInterest();

        // borrower accounting
        Borrower memory borrower = borrowers[msg.sender];
        (borrower.debt, borrower.inflatorSnapshot) = _accrueBorrowerInterest(borrower.debt, borrower.inflatorSnapshot, inflatorSnapshot);
        borrower.collateral += amount_;

        // update loan queue
        uint256 thresholdPrice = _threshold_price(borrower.debt, borrower.collateral, borrower.inflatorSnapshot);
        if (borrower.debt != 0) _updateLoanQueue(msg.sender, thresholdPrice, oldPrev_, newPrev_);

        borrowers[msg.sender] = borrower;

        // update pool state
        pledgedCollateral += amount_;
        _updateInterestRate(curDebt, _lup());

        // move collateral from sender to pool
        collateral().safeTransferFrom(msg.sender, address(this), amount_ / collateralScale);
        emit AddCollateral(msg.sender, amount_);
    }

    function borrow(uint256 amount_, uint256 limitIndex_, address oldPrev_, address newPrev_) external override {
        uint256 lupId = _lupIndex(amount_);
        require(lupId <= limitIndex_, "S:B:LIMIT_REACHED"); // TODO: add check that limitIndex is <= MAX_INDEX

        uint256 curDebt = _accruePoolInterest();

        Borrower memory borrower = borrowers[msg.sender];
        uint256 borrowersCount = totalBorrowers;
        if (borrowersCount != 0) require(borrower.debt + amount_ > _poolMinDebtAmount(curDebt), "S:B:AMT_LT_AVG_DEBT");

        (borrower.debt, borrower.inflatorSnapshot) = _accrueBorrowerInterest(borrower.debt, borrower.inflatorSnapshot, inflatorSnapshot);
        if (borrower.debt == 0) totalBorrowers = borrowersCount + 1;

        uint256 feeRate = Maths.max(Maths.wdiv(interestRate, WAD_WEEKS_PER_YEAR), minFee) + Maths.WAD;
        uint256 debt    = Maths.wmul(amount_, feeRate);
        borrower.debt   += debt;

        uint256 newLup = _indexToPrice(lupId);
        require(_borrowerCollateralization(borrower.debt, borrower.collateral, newLup) >= Maths.WAD, "S:B:BUNDER_COLLAT");

        require(
            _poolCollateralizationAtPrice(curDebt, debt, pledgedCollateral, newLup) >= Maths.WAD,
            "S:B:PUNDER_COLLAT"
        );
        curDebt += debt;

        // update actor accounting
        borrowerDebt = curDebt;
        lenderDebt   += amount_;

        // update loan queue
        uint256 thresholdPrice = _threshold_price(borrower.debt, borrower.collateral, borrower.inflatorSnapshot);
        _updateLoanQueue(msg.sender, thresholdPrice, oldPrev_, newPrev_);
        borrowers[msg.sender] = borrower;

        _updateInterestRate(curDebt, newLup);

        // move borrowed amount from pool to sender
        quoteToken().safeTransfer(msg.sender, amount_ / quoteTokenScale);
        emit Borrow(msg.sender, newLup, amount_);
    }

    function removeCollateral(uint256 amount_, address oldPrev_, address newPrev_) external override {
        uint256 curDebt = _accruePoolInterest();

        // borrower accounting
        Borrower storage borrower = borrowers[msg.sender];
        (borrower.debt, borrower.inflatorSnapshot) = _accrueBorrowerInterest(borrower.debt, borrower.inflatorSnapshot, inflatorSnapshot);

        uint256 curLup = _lup();
        require(borrower.collateral - _encumberedCollateral(borrower.debt, curLup) >= amount_, "S:RC:NOT_ENOUGH_COLLATERAL");
        borrower.collateral -= amount_;

        // update loan queue
        uint256 thresholdPrice = _threshold_price(borrower.debt, borrower.collateral, borrower.inflatorSnapshot);
        if (borrower.debt != 0) _updateLoanQueue(msg.sender, thresholdPrice, oldPrev_, newPrev_);

        // update pool state
        pledgedCollateral -= amount_;
        _updateInterestRate(curDebt, curLup);

        // move collateral from pool to sender
        collateral().safeTransfer(msg.sender, amount_ / collateralScale);
        emit RemoveCollateral(msg.sender, amount_);
    }

    function repay(uint256 maxAmount_, address oldPrev_, address newPrev_) external override {
        require(quoteToken().balanceOf(msg.sender) * quoteTokenScale >= maxAmount_, "S:R:INSUF_BAL");

        Borrower memory borrower = borrowers[msg.sender];
        require(borrower.debt != 0, "S:R:NO_DEBT");

        uint256 curDebt = _accruePoolInterest();

        // update borrower accounting
        (borrower.debt, borrower.inflatorSnapshot) = _accrueBorrowerInterest(borrower.debt, borrower.inflatorSnapshot, inflatorSnapshot);
        uint256 amount = Maths.min(borrower.debt, maxAmount_);
        borrower.debt -= amount;

        // update lender accounting
        uint256 curLenderDebt = lenderDebt;
        curLenderDebt -= Maths.min(curLenderDebt, Maths.wmul(Maths.wdiv(curLenderDebt, curDebt), amount));

        curDebt       -= amount;

        // update loan queue
        uint256 borrowersCount = totalBorrowers;
        if (borrower.debt == 0) {
            totalBorrowers = borrowersCount - 1;
            _removeLoanQueue(msg.sender, oldPrev_);
        } else {
            if (borrowersCount != 0) require(borrower.debt > _poolMinDebtAmount(curDebt), "R:B:AMT_LT_AVG_DEBT");
            uint256 thresholdPrice = _threshold_price(borrower.debt, borrower.collateral, borrower.inflatorSnapshot);
            _updateLoanQueue(msg.sender, thresholdPrice, oldPrev_, newPrev_);
        }
        borrowers[msg.sender] = borrower;

        // update pool state
        if (curDebt != 0) {
            borrowerDebt = curDebt;
            lenderDebt   = curLenderDebt;
        } else {
            borrowerDebt = 0;
            lenderDebt   = 0;
        }

        uint256 newLup = _lup();
        _updateInterestRate(curDebt, newLup);

        // move amount to repay from sender to pool
        quoteToken().safeTransferFrom(msg.sender, address(this), amount / quoteTokenScale);
        emit Repay(msg.sender, newLup, amount);
    }

    /*********************************/
    /*** Lender External Functions ***/
    /*********************************/

    function claimCollateral(uint256 amount_, uint256 index_) external override returns (uint256 lpRedemption_) {
        Bucket storage bucket = buckets[index_];
        require(amount_ <= bucket.availableCollateral, "S:CC:AMT_GT_COLLAT");

        uint256 price = _indexToPrice(index_);
        uint256 rate  = _exchangeRate(bucket.availableCollateral, bucket.lpAccumulator, index_);
        lpRedemption_ = Maths.wrdivr(Maths.wmul(amount_, price), rate);
        require(lpRedemption_ <= lpBalance[index_][msg.sender], "S:CC:INSUF_LP_BAL");

        bucket.availableCollateral     -= amount_;
        bucket.lpAccumulator           -= lpRedemption_;
        lpBalance[index_][msg.sender] -= lpRedemption_;

        _updateInterestRate(borrowerDebt, _lup());

        // move claimed collateral from pool to claimer
        collateral().safeTransfer(msg.sender, amount_ / collateralScale);
        emit ClaimCollateral(msg.sender, price, amount_, lpRedemption_);
    }

    /*******************************/
    /*** Pool External Functions ***/
    /*******************************/

    function purchaseQuote(uint256 amount_, uint256 index_) external override {
        require(_rangeSum(index_, index_) >= amount_, "S:P:INSUF_QUOTE");

        uint256 curDebt = _accruePoolInterest();

        uint256 price = _indexToPrice(index_);
        uint256 collateralRequired = Maths.wdiv(amount_, price);
        require(collateral().balanceOf(msg.sender) * collateralScale >= collateralRequired, "S:P:INSUF_COL");

        _remove(index_, amount_);
        buckets[index_].availableCollateral += collateralRequired;

        _updateInterestRate(curDebt, _lup());

        // move required collateral from sender to pool
        collateral().safeTransferFrom(msg.sender, address(this), collateralRequired / collateralScale);
        // move quote token amount from pool to sender
        quoteToken().safeTransfer(msg.sender, amount_ / quoteTokenScale);
        emit Purchase(msg.sender, price, amount_, collateralRequired);
    }

    /**********************/
    /*** View Functions ***/
    /**********************/

    function borrowerInfo(address borrower_) external view override returns (uint256, uint256, uint256, uint256) {
        uint256 pending_debt = Maths.wmul(borrowers[borrower_].debt, Maths.wdiv(_pendingInflator(), inflatorSnapshot));

        return (
            borrowers[borrower_].debt,            // accrued debt (WAD)
            pending_debt,                         // current debt, accrued and pending accrual (WAD)
            borrowers[borrower_].collateral,      // deposited collateral including encumbered (WAD)
            borrowers[borrower_].inflatorSnapshot // used to calculate pending interest (WAD)
        );
    }

    /************************/
    /*** Helper Functions ***/
    /************************/

    /**
     *  @dev Pure function used to facilitate accessing token via clone state.
     */
    function collateral() public pure returns (ERC20) {
        return ERC20(_getArgAddress(0));
    }
}
