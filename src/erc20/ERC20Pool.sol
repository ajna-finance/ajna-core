// SPDX-License-Identifier: MIT

pragma solidity 0.8.14;

import { ERC20 }     from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { IERC20Pool } from "./interfaces/IERC20Pool.sol";

import { ScaledPool } from "../base/ScaledPool.sol";

import { Maths } from "../libraries/Maths.sol";

contract ERC20Pool is IERC20Pool, ScaledPool {
    using SafeERC20 for ERC20;

    struct LiquidationInfo {
        uint128 kickTime;
        uint128 referencePrice;
        uint256 remainingCollateral;
        uint256 remainingDebt;
    }

    /***********************/
    /*** State Variables ***/
    /***********************/

    // borrowers book: borrower address -> BorrowerInfo
    mapping(address => Borrower) public override borrowers;

    mapping (address => LiquidationInfo) public liquidations;

    uint256 public override collateralScale;

    /****************************/
    /*** Initialize Functions ***/
    /****************************/

    function initialize(uint256 rate_) external {
        require(poolInitializations == 0, "P:INITIALIZED");
        collateralScale = 10**(18 - collateral().decimals());
        quoteTokenScale = 10**(18 - quoteToken().decimals());

        inflatorSnapshot           = 10**18;
        lastInflatorSnapshotUpdate = block.timestamp;
        lenderInterestFactor       = 0.9 * 10**18;
        interestRate               = rate_;
        interestRateUpdate         = block.timestamp;
        minFee                     = 0.0005 * 10**18;

        // increment initializations count to ensure these values can't be updated
        poolInitializations += 1;
    }

    /***********************************/
    /*** Borrower External Functions ***/
    /***********************************/

    function pledgeCollateral(address borrower_, uint256 amount_, address oldPrev_, address newPrev_) external override {
        uint256 curDebt = _accruePoolInterest();

        // borrower accounting
        Borrower memory borrower = borrowers[borrower_];
        (borrower.debt, borrower.inflatorSnapshot) = _accrueBorrowerInterest(borrower.debt, borrower.inflatorSnapshot, inflatorSnapshot);
        borrower.collateral += amount_;

        // update loan queue
        uint256 thresholdPrice = _thresholdPrice(borrower.debt, borrower.collateral, borrower.inflatorSnapshot);
        if (borrower.debt != 0) _updateLoanQueue(borrower_, thresholdPrice, oldPrev_, newPrev_);

        borrowers[borrower_] = borrower;

        // update pool state
        pledgedCollateral += amount_;
        _updateInterestRateAndEMAs(curDebt, _lup());

        // move collateral from sender to pool
        emit PledgeCollateral(borrower_, amount_);
        collateral().safeTransferFrom(msg.sender, address(this), amount_ / collateralScale);
    }

    function borrow(uint256 amount_, uint256 limitIndex_, address oldPrev_, address newPrev_) external override {
        uint256 lupId = _lupIndex(amount_);
        require(lupId <= limitIndex_, "S:B:LIMIT_REACHED"); // TODO: add check that limitIndex is <= MAX_INDEX

        uint256 curDebt = _accruePoolInterest();

        Borrower memory borrower = borrowers[msg.sender];
        uint256 borrowersCount = totalBorrowers;
        if (borrowersCount != 0) require(borrower.debt + amount_ > _poolMinDebtAmount(curDebt), "S:B:AMT_LT_MIN_DEBT");

        (borrower.debt, borrower.inflatorSnapshot) = _accrueBorrowerInterest(borrower.debt, borrower.inflatorSnapshot, inflatorSnapshot);
        if (borrower.debt == 0) totalBorrowers = borrowersCount + 1;

        uint256 debt  = Maths.wmul(amount_, _calculateFeeRate() + Maths.WAD);
        borrower.debt += debt;

        uint256 newLup = _indexToPrice(lupId);
        require(_borrowerCollateralization(borrower.debt, borrower.collateral, newLup) >= Maths.WAD, "S:B:BUNDER_COLLAT");

        require(
            _poolCollateralizationAtPrice(curDebt, debt, pledgedCollateral, newLup) >= Maths.WAD,
            "S:B:PUNDER_COLLAT"
        );
        curDebt += debt;

        // update actor accounting
        borrowerDebt = curDebt;

        // update loan queue
        uint256 thresholdPrice = _thresholdPrice(borrower.debt, borrower.collateral, borrower.inflatorSnapshot);
        _updateLoanQueue(msg.sender, thresholdPrice, oldPrev_, newPrev_);
        borrowers[msg.sender] = borrower;

        _updateInterestRateAndEMAs(curDebt, newLup);

        // move borrowed amount from pool to sender
        emit Borrow(msg.sender, newLup, amount_);
        quoteToken().safeTransfer(msg.sender, amount_ / quoteTokenScale);
    }

    function pullCollateral(uint256 amount_, address oldPrev_, address newPrev_) external override {
        uint256 curDebt = _accruePoolInterest();

        // borrower accounting
        Borrower storage borrower = borrowers[msg.sender];
        (borrower.debt, borrower.inflatorSnapshot) = _accrueBorrowerInterest(borrower.debt, borrower.inflatorSnapshot, inflatorSnapshot);

        uint256 curLup = _lup();
        require(borrower.collateral - _encumberedCollateral(borrower.debt, curLup) >= amount_, "S:PC:NOT_ENOUGH_COLLATERAL");
        borrower.collateral -= amount_;

        // update loan queue
        uint256 thresholdPrice = _thresholdPrice(borrower.debt, borrower.collateral, borrower.inflatorSnapshot);
        if (borrower.debt != 0) _updateLoanQueue(msg.sender, thresholdPrice, oldPrev_, newPrev_);

        // update pool state
        pledgedCollateral -= amount_;
        _updateInterestRateAndEMAs(curDebt, curLup);

        // move collateral from pool to sender
        emit PullCollateral(msg.sender, amount_);
        collateral().safeTransfer(msg.sender, amount_ / collateralScale);
    }

    function repay(address borrower_, uint256 maxAmount_, address oldPrev_, address newPrev_) external override {
        _repayDebt(borrower_, maxAmount_, oldPrev_, newPrev_);
    }

    /*********************************/
    /*** Lender External Functions ***/
    /*********************************/

    function addCollateral(uint256 amount_, uint256 index_) external override returns (uint256 lpbChange_) {
        require(collateral().balanceOf(msg.sender) >= amount_, "S:AC:INSUF_COL");

        _accruePoolInterest();

        Bucket memory bucket = buckets[index_];
        BucketLender memory bucketLender = bucketLenders[index_][msg.sender];
        // Calculate exchange rate before new collateral has been accounted for.
        // This is consistent with how lbpChange in addQuoteToken is adjusted before calling _add.
        uint256 rate = _exchangeRate(_valueAt(index_), bucket.availableCollateral, bucket.lpAccumulator, index_);

        uint256 quoteValue     = Maths.wmul(amount_, _indexToPrice(index_));
        lpbChange_             = Maths.rdiv(Maths.wadToRay(quoteValue), rate);
        bucket.lpAccumulator   += lpbChange_;
        bucketLender.lpBalance += lpbChange_;

        bucket.availableCollateral        += amount_;
        buckets[index_]                   = bucket;
        bucketLenders[index_][msg.sender] = bucketLender;

        _updateInterestRateAndEMAs(borrowerDebt, _lup());

        // move required collateral from sender to pool
        emit AddCollateral(msg.sender, _indexToPrice(index_), amount_);
        collateral().safeTransferFrom(msg.sender, address(this), amount_ / collateralScale);
    }

    function removeAllCollateral(uint256 index_) external override returns (uint256 amount_, uint256 lpAmount_) {
        Bucket memory bucket = buckets[index_];
        require(bucket.availableCollateral != 0, "S:RAC:NO_COL");

        _accruePoolInterest();

        BucketLender memory bucketLender = bucketLenders[index_][msg.sender];
        uint256 price = _indexToPrice(index_);
        uint256 rate  = _exchangeRate(_valueAt(index_), bucket.availableCollateral, bucket.lpAccumulator, index_);
        lpAmount_     = bucketLender.lpBalance;
        amount_       = Maths.rwdivw(Maths.rmul(lpAmount_, rate), price);
        require(amount_ != 0, "S:RAC:NO_CLAIM");

        if (amount_ > bucket.availableCollateral) {
            // user is owed more collateral than is available in the bucket
            amount_   = bucket.availableCollateral;
            lpAmount_ = Maths.wrdivr(Maths.wmul(amount_, price), rate);
        } // else user is redeeming all of their LPs

        _redeemLPForCollateral(bucket, bucketLender, lpAmount_, amount_, price, index_);
    }

    function removeCollateral(uint256 amount_, uint256 index_) external override returns (uint256 lpAmount_) {
        Bucket memory bucket = buckets[index_];
        require(amount_ <= bucket.availableCollateral, "S:RC:INSUF_COL");

        _accruePoolInterest();

        BucketLender memory bucketLender = bucketLenders[index_][msg.sender];
        uint256 price        = _indexToPrice(index_);
        uint256 rate         = _exchangeRate(_valueAt(index_), bucket.availableCollateral, bucket.lpAccumulator, index_);
        uint256 availableLPs = bucketLender.lpBalance;

        // ensure user can actually remove that much
        lpAmount_ = Maths.rdiv((amount_ * price / 1e9), rate);
        require(availableLPs != 0 && lpAmount_ <= availableLPs, "S:RC:INSUF_LPS");

        _redeemLPForCollateral(bucket, bucketLender, lpAmount_, amount_, price, index_);
    }

    /*******************************/
    /*** Pool External Functions ***/
    /*******************************/

    // TODO: Remove
    function liquidate(address borrower_) external {
        (uint256 curDebt) = _accruePoolInterest();

        Borrower memory borrower = borrowers[borrower_];
        require(borrower.debt != 0, "P:L:NO_DEBT");

        (borrower.debt, borrower.inflatorSnapshot) = _accrueBorrowerInterest(borrower.debt, borrower.inflatorSnapshot, inflatorSnapshot);
        uint256 lup = _lup();
        _updateInterestRateAndEMAs(curDebt, lup);
        require(  // TODO: to kick, collateralization should be < 1 not <= 1
            _borrowerCollateralization(borrower.debt, borrower.collateral, lup) <= Maths.WAD,
            "P:L:BORROWER_OK"
        );

        borrowers[borrower_] = borrower;
        liquidations[borrower_] = LiquidationInfo({
            kickTime:            uint128(block.timestamp),
            referencePrice:      uint128(_hpbIndex()),
            remainingCollateral: borrower.collateral,
            remainingDebt:       borrower.debt
        });

        uint256 thresholdPrice = borrower.debt * Maths.WAD / borrower.collateral;
        uint256 poolPrice      = borrowerDebt * Maths.WAD / pledgedCollateral;  // PTP

        require(lup < thresholdPrice, "P:L:LUP_GT_THRESHOLD");

        // TODO: Post liquidation bond (use max bond factor of 1% but leave todo to revisit)
        // TODO: Account for repossessed collateral

        // Post the liquidation bond
        // Repossess the borrowers collateral, initialize the auction cooldown timer
    }

    // TODO: Add reentrancy guard
    function take(address borrower_, uint256 collateralToLiquidate_, bytes memory swapCalldata_, address oldPrev_, address newPrev_) external {
        Borrower        memory borrower    = borrowers[borrower_];
        LiquidationInfo memory liquidation = liquidations[borrower_];

        require(
            liquidation.kickTime != 0 &&
            block.timestamp - uint256(liquidation.kickTime) > 1 hours,
            "P:T:NOT_PAST_COOLDOWN"
        );

        require(
            _borrowerCollateralization(borrower.debt, borrower.collateral, _lup()) <= Maths.WAD,
            "P:L:BORROWER_OK"
        );

        uint256 collateralForLiquidation = Maths.min(collateralToLiquidate_, liquidation.remainingCollateral);

        // Reduce liquidation's remaining collateral
        liquidations[borrower_].remainingCollateral -= collateralForLiquidation;

        // Flash loan full amount to liquidate to borrower
        collateral().safeTransfer(msg.sender, collateralForLiquidation);

        // Execute arbitrary code at msg.sender address, allowing atomic conversion of asset
        msg.sender.call(swapCalldata_);

        // Get current swap price
        uint256 quoteTokenReturnAmount = _getQuoteTokenReturnAmount(uint256(liquidation.kickTime), uint256(liquidation.referencePrice), collateralForLiquidation);

        // Pull funds from msg.sender
        quoteToken().safeTransferFrom(msg.sender, address(this), quoteTokenReturnAmount);

        _repayDebt(borrower_, quoteTokenReturnAmount, oldPrev_, newPrev_);
    }


    /**************************/
    /*** Internal Functions ***/
    /**************************/

    function _redeemLPForCollateral(
        Bucket memory bucket,
        BucketLender memory bucketLender,
        uint256 lpAmount_,
        uint256 amount_,
        uint256 price_,
        uint256 index_
    ) internal {
        // update bucket accounting
        bucket.availableCollateral -= Maths.min(bucket.availableCollateral, amount_);
        bucket.lpAccumulator       -= Maths.min(bucket.lpAccumulator, lpAmount_);
        buckets[index_] = bucket;

        // update lender accounting
        bucketLender.lpBalance -= lpAmount_;
        bucketLenders[index_][msg.sender] = bucketLender;

        _updateInterestRateAndEMAs(borrowerDebt, _lup());

        // move collateral from pool to lender
        emit RemoveCollateral(msg.sender, price_, amount_);
        collateral().safeTransfer(msg.sender, amount_ / collateralScale);
    }

    function _repayDebt(address borrower_, uint256 maxAmount_, address oldPrev_, address newPrev_) internal {
        require(quoteToken().balanceOf(msg.sender) * quoteTokenScale >= maxAmount_, "S:R:INSUF_BAL");

        Borrower memory borrower = borrowers[borrower_];
        require(borrower.debt != 0, "S:R:NO_DEBT");

        uint256 curDebt = _accruePoolInterest();

        // update borrower accounting
        (borrower.debt, borrower.inflatorSnapshot) = _accrueBorrowerInterest(borrower.debt, borrower.inflatorSnapshot, inflatorSnapshot);
        uint256 amount = Maths.min(borrower.debt, maxAmount_);
        borrower.debt -= amount;
        curDebt       -= amount;

        // update loan queue
        uint256 borrowersCount = totalBorrowers;
        if (borrower.debt == 0) {
            totalBorrowers = borrowersCount - 1;
            _removeLoanQueue(borrower_, oldPrev_);
        } else {
            if (borrowersCount != 0) require(borrower.debt > _poolMinDebtAmount(curDebt), "R:B:AMT_LT_MIN_DEBT");
            uint256 thresholdPrice = _thresholdPrice(borrower.debt, borrower.collateral, borrower.inflatorSnapshot);
            _updateLoanQueue(borrower_, thresholdPrice, oldPrev_, newPrev_);
        }
        borrowers[borrower_] = borrower;

        // update pool state
        borrowerDebt = curDebt;

        uint256 newLup = _lup();
        _updateInterestRateAndEMAs(curDebt, newLup);

        // move amount to repay from sender to pool
        emit Repay(borrower_, newLup, amount);
        quoteToken().safeTransferFrom(msg.sender, address(this), amount / quoteTokenScale);
    }

    /**********************/
    /*** View Functions ***/
    /**********************/

    function borrowerInfo(address borrower_) external view override returns (uint256, uint256, uint256, uint256) {
        uint256 pendingDebt = Maths.wmul(borrowers[borrower_].debt, Maths.wdiv(_pendingInflator(), inflatorSnapshot));

        return (
            borrowers[borrower_].debt,            // accrued debt (WAD)
            pendingDebt,                          // current debt, accrued and pending accrual (WAD)
            borrowers[borrower_].collateral,      // deposited collateral including encumbered (WAD)
            borrowers[borrower_].inflatorSnapshot // used to calculate pending interest (WAD)
        );
    }


    function _getQuoteTokenReturnAmount(uint256 kickTime_, uint256 referencePrice_, uint256 collateralForLiquidation_) internal view returns (uint256 price_) {
        uint256 hoursSinceKick = (block.timestamp - kickTime_) / 1 hours;
        uint256 currentPrice   = 10 * referencePrice_ * 2 ** (hoursSinceKick - 1 hours);

        price_ = collateralForLiquidation_ * currentPrice * quoteTokenScale / collateralScale;
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
