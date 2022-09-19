// SPDX-License-Identifier: MIT

pragma solidity 0.8.14;

import { ERC20 }     from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { IERC20Pool } from "./interfaces/IERC20Pool.sol";

import { ScaledPool } from "../base/ScaledPool.sol";

import { Heap }  from "../libraries/Heap.sol";
import { Maths } from "../libraries/Maths.sol";
import '../libraries/Book.sol';
import '../libraries/Lenders.sol';

contract ERC20Pool is IERC20Pool, ScaledPool {
    using SafeERC20 for ERC20;
    using Book      for mapping(uint256 => Book.Bucket);
    using Lenders   for mapping(uint256 => mapping(address => Lenders.Lender));
    using Heap      for Heap.Data;

    /***********************/
    /*** State Variables ***/
    /***********************/

    mapping(address => LiquidationInfo) public override liquidations;

    uint256 public override collateralScale;

    /****************************/
    /*** Initialize Functions ***/
    /****************************/

    function initialize(uint256 rate_, address ajnaTokenAddress_) external {
        if (poolInitializations != 0) revert AlreadyInitialized();

        collateralScale = 10**(18 - collateral().decimals());
        quoteTokenScale = 10**(18 - quoteToken().decimals());

        ajnaTokenAddress           = ajnaTokenAddress_;
        inflatorSnapshot           = 10**18;
        lastInflatorSnapshotUpdate = block.timestamp;
        lenderInterestFactor       = 0.9 * 10**18;
        interestRate               = rate_;
        interestRateUpdate         = block.timestamp;
        minFee                     = 0.0005 * 10**18;

        loans.init();

        // increment initializations count to ensure these values can't be updated
        poolInitializations += 1;
    }

    /***********************************/
    /*** Borrower External Functions ***/
    /***********************************/

    function pledgeCollateral(address borrower_, uint256 amount_) external override {
        _pledgeCollateral(borrower_, amount_);

        // move collateral from sender to pool
        emit PledgeCollateral(borrower_, amount_);
        collateral().safeTransferFrom(msg.sender, address(this), amount_ / collateralScale);
    }

    function pullCollateral(uint256 amount_) external override {
        _pullCollateral(amount_);

        // move collateral from pool to sender
        emit PullCollateral(msg.sender, amount_);
        collateral().safeTransfer(msg.sender, amount_ / collateralScale);
    }

    /*********************************/
    /*** Lender External Functions ***/
    /*********************************/

    function addCollateral(uint256 amount_, uint256 index_) external override returns (uint256 lpbChange_) {
        lpbChange_ = _addCollateral(amount_, index_);

        // move required collateral from sender to pool
        emit AddCollateral(msg.sender, index_, amount_);
        collateral().safeTransferFrom(msg.sender, address(this), amount_ / collateralScale);
    }

    function moveCollateral(uint256 amount_, uint256 fromIndex_, uint256 toIndex_) external override returns (uint256 lpbAmountFrom_, uint256 lpbAmountTo_) {
        if (fromIndex_ == toIndex_) revert MoveCollateralToSamePrice();

        if (buckets.getCollateral(fromIndex_) < amount_) revert MoveCollateralInsufficientCollateral();

        uint256 curDebt = _accruePoolInterest();

        // determine amount of amount of LP required
        uint256 rate   = buckets.getExchangeRate(fromIndex_, _valueAt(fromIndex_));
        lpbAmountFrom_ = (amount_ * Book.indexToPrice(fromIndex_) * 1e18 + rate / 2) / rate;

        (uint256 lpBalance, ) = lenders.getLenderInfo(fromIndex_, msg.sender);
        if (lpbAmountFrom_ > lpBalance) revert MoveCollateralInsufficientLP();

        // update "to" bucket accounting
        rate         = buckets.getExchangeRate(toIndex_, _valueAt(toIndex_));
        lpbAmountTo_ = (amount_ * Book.indexToPrice(toIndex_) * 1e18 + rate / 2) / rate;

        // update buckets
        buckets.removeFromBucket(fromIndex_, lpbAmountFrom_, amount_);
        buckets.addToBucket(toIndex_, lpbAmountTo_, amount_);
        // update lender accounting
        lenders.removeLPs(fromIndex_, msg.sender, lpbAmountFrom_);
        lenders.addLPs(toIndex_, msg.sender, lpbAmountTo_);

        _updateInterestRateAndEMAs(curDebt, _lup());

        emit MoveCollateral(msg.sender, fromIndex_, toIndex_, amount_);
    }

    function removeAllCollateral(uint256 index_) external override returns (uint256 amount_, uint256 lpAmount_) {
        uint256 availableCollateral = buckets.getCollateral(index_);
        if (availableCollateral == 0) revert RemoveCollateralInsufficientCollateral();

        _accruePoolInterest();

        uint256 price = Book.indexToPrice(index_);
        uint256 rate  = buckets.getExchangeRate(index_, _valueAt(index_));
        (lpAmount_, ) = lenders.getLenderInfo(index_, msg.sender);
        amount_       = Maths.rwdivw(Maths.rmul(lpAmount_, rate), price);
        if (amount_ == 0) revert RemoveCollateralNoClaim();

        if (amount_ > availableCollateral) {
            // user is owed more collateral than is available in the bucket
            amount_   = availableCollateral;
            lpAmount_ = Maths.wrdivr(Maths.wmul(amount_, price), rate);
        } // else user is redeeming all of their LPs

        // update bucket accounting
        buckets.removeFromBucket(index_, lpAmount_, amount_);

        // update lender accounting
        lenders.removeLPs(index_, msg.sender, lpAmount_);

        _updateInterestRateAndEMAs(borrowerDebt, _lup());

        // move collateral from pool to lender
        emit RemoveCollateral(msg.sender, index_, amount_);
        collateral().safeTransfer(msg.sender, amount_ / collateralScale);
    }

    function removeCollateral(uint256 amount_, uint256 index_) external override returns (uint256 lpAmount_) {
        lpAmount_ = _removeCollateral(amount_, index_);

        // move collateral from pool to lender
        emit RemoveCollateral(msg.sender, index_, amount_);
        collateral().safeTransfer(msg.sender, amount_ / collateralScale);
    }

    /*******************************/
    /*** Pool External Functions ***/
    /*******************************/

    function arbTake(address borrower_, uint256 amount_, uint256 index_) external override {
        // TODO: implement
        emit ArbTake(borrower_, index_, amount_, 0, 0);
    }

    function clear(address borrower_, uint256 maxDepth_) external override {
        // TODO: implement
        uint256 debtCleared = maxDepth_ * 10_000;
        emit Clear(borrower_, _hpbIndex(), debtCleared, 0, 0);
    }

    function depositTake(address borrower_, uint256 amount_, uint256 index_) external override {
        // TODO: implement
        emit DepositTake(borrower_, index_, amount_, 0, 0);
    }

    function kick(address borrower_) external override {
        (uint256 curDebt) = _accruePoolInterest();

        Borrower memory borrower = borrowers[borrower_];
        if (borrower.debt == 0) revert KickNoDebt();

        (borrower.debt, borrower.inflatorSnapshot) = _accrueBorrowerInterest(borrower.debt, borrower.inflatorSnapshot, inflatorSnapshot);
        uint256 lup = _lup();
        _updateInterestRateAndEMAs(curDebt, lup);

        if (_borrowerCollateralization(borrower.debt, borrower.collateral, lup) >= Maths.WAD) revert LiquidateBorrowerOk();

        borrowers[borrower_] = borrower;
        liquidations[borrower_] = LiquidationInfo({
            kickTime:            uint128(block.timestamp),
            referencePrice:      uint128(_hpbIndex()),
            remainingCollateral: borrower.collateral,
            remainingDebt:       borrower.debt
        });

        uint256 thresholdPrice = borrower.debt * Maths.WAD / borrower.collateral;
        // TODO: Uncomment when needed
        // uint256 poolPrice      = borrowerDebt * Maths.WAD / pledgedCollateral;  // PTP

        if (lup > thresholdPrice) revert KickLUPGreaterThanTP();

        // TODO: Post liquidation bond (use max bond factor of 1% but leave todo to revisit)
        // TODO: Account for repossessed collateral
        liquidationBondEscrowed += Maths.wmul(borrower.debt, 0.01 * 1e18);

        // Post the liquidation bond
        // Repossess the borrowers collateral, initialize the auction cooldown timer

        emit Kick(borrower_, borrower.debt, borrower.collateral);
    }

    // TODO: Add reentrancy guard
    function take(address borrower_, uint256 amount_, bytes memory swapCalldata_) external override {
        Borrower        memory borrower    = borrowers[borrower_];
        LiquidationInfo memory liquidation = liquidations[borrower_];

        // check liquidation process status
        if (liquidation.kickTime == 0 || block.timestamp - uint256(liquidation.kickTime) <= 1 hours) revert TakeNotPastCooldown();
        if (_borrowerCollateralization(borrower.debt, borrower.collateral, _lup()) >= Maths.WAD) revert LiquidateBorrowerOk();

        // TODO: calculate using price decrease function and amount_
        uint256 liquidationPrice = Maths.WAD;
        uint256 collateralToPurchase = Maths.wdiv(amount_, liquidationPrice);

        // Reduce liquidation's remaining collateral
        liquidations[borrower_].remainingCollateral -= collateralToPurchase;

        // Flash loan full amount to liquidate to borrower
        collateral().safeTransfer(msg.sender, collateralToPurchase);

        // Execute arbitrary code at msg.sender address, allowing atomic conversion of asset
        msg.sender.call(swapCalldata_);

        // Get current swap price
        uint256 hoursSinceKick = (block.timestamp - uint256(liquidation.kickTime)) / 1 hours;
        uint256 currentPrice   = 10 * uint256(liquidation.referencePrice) * 2 ** (hoursSinceKick - 1 hours);
        uint256 quoteTokenReturnAmount = collateralToPurchase * currentPrice * quoteTokenScale / collateralScale;

        _repayDebt(borrower_, quoteTokenReturnAmount);

        emit Take(borrower_, amount_, collateralToPurchase, 0);
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
