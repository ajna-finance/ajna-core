// SPDX-License-Identifier: MIT

pragma solidity 0.8.14;

import { PRBMathSD59x18 } from "@prb-math/contracts/PRBMathSD59x18.sol";
import { ERC20 }     from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { IERC20Pool } from "./interfaces/IERC20Pool.sol";

import { ScaledPool } from "../base/ScaledPool.sol";

import { Heap }  from "../libraries/Heap.sol";
import { Maths } from "../libraries/Maths.sol";

contract ERC20Pool is IERC20Pool, ScaledPool {
    using SafeERC20 for ERC20;
    using Heap      for Heap.Data;

    /***********************/
    /*** State Variables ***/
    /***********************/

    // borrowers book: borrower address -> BorrowerInfo
    mapping(address => Borrower) public override borrowers;

    mapping(address => LiquidationInfo) public override liquidations;

    uint256 public override collateralScale;

    /****************************/
    /*** Initialize Functions ***/
    /****************************/

    function initialize(uint256 rate_) external {
        if (poolInitializations != 0) revert AlreadyInitialized();

        collateralScale = 10**(18 - collateral().decimals());
        quoteTokenScale = 10**(18 - quoteToken().decimals());

        inflatorSnapshot           = 10**18;
        lastInflatorSnapshotUpdate = block.timestamp;
        lenderInterestFactor       = 0.9 * 10**18;
        interestRate               = rate_;
        interestRateUpdate         = block.timestamp;
        minFee                     = 0.0005 * 10**18;

        loans.init();
        auctions.init();

        // increment initializations count to ensure these values can't be updated
        poolInitializations += 1;
    }

    /***********************************/
    /*** Borrower External Functions ***/
    /***********************************/
    function pledgeCollateral(address borrower_, uint256 amount_) external override {
        uint256 curDebt = _accruePoolInterest();

        // borrower accounting
        //TODO: check if loan is in liquidation, remove loan from liquidation if additional pledge collateral saves it.
        Borrower memory borrower = borrowers[borrower_];
        (borrower.debt, borrower.inflatorSnapshot) = _accrueBorrowerInterest(borrower.debt, borrower.inflatorSnapshot, inflatorSnapshot);
        borrower.collateral += amount_;

        // update loan queue
        uint256 thresholdPrice = _t0ThresholdPrice(borrower.debt, borrower.collateral, borrower.inflatorSnapshot);
        if (borrower.debt != 0) loans.upsert(borrower_, thresholdPrice);

        borrowers[borrower_] = borrower;

        // update pool state
        pledgedCollateral += amount_;
        _updateInterestRateAndEMAs(curDebt, _lup());

        // move collateral from sender to pool
        emit PledgeCollateral(borrower_, amount_);
        collateral().safeTransferFrom(msg.sender, address(this), amount_ / collateralScale);
    }

    function borrow(uint256 amount_, uint256 limitIndex_) external override {
        uint256 lupId = _lupIndex(amount_);
        if (lupId > limitIndex_) revert BorrowLimitIndexReached();

        uint256 curDebt = _accruePoolInterest();

        Borrower memory borrower = borrowers[msg.sender];
        if (loans.count - 1 != 0) if (borrower.debt + amount_ < _poolMinDebtAmount(curDebt)) revert BorrowAmountLTMinDebt();

        (borrower.debt, borrower.inflatorSnapshot) = _accrueBorrowerInterest(borrower.debt, borrower.inflatorSnapshot, inflatorSnapshot);

        uint256 debt  = Maths.wmul(amount_, _calculateFeeRate() + Maths.WAD);
        borrower.debt += debt;

        uint256 newLup = _indexToPrice(lupId);

        // check borrow won't push borrower or pool into a state of under-collateralization
        if (_borrowerCollateralization(borrower.debt, borrower.collateral, newLup) < Maths.WAD) revert BorrowBorrowerUnderCollateralized();
        if (_poolCollateralizationAtPrice(curDebt, debt, pledgedCollateral, newLup) < Maths.WAD) revert BorrowPoolUnderCollateralized();

        curDebt += debt;

        // update actor accounting
        borrowerDebt = curDebt;

        // update loan queue
        uint256 thresholdPrice = _t0ThresholdPrice(borrower.debt, borrower.collateral, borrower.inflatorSnapshot);
        loans.upsert(msg.sender, thresholdPrice);

        borrowers[msg.sender] = borrower;

        _updateInterestRateAndEMAs(curDebt, newLup);

        // move borrowed amount from pool to sender
        emit Borrow(msg.sender, newLup, amount_);
        quoteToken().safeTransfer(msg.sender, amount_ / quoteTokenScale);
    }

    function pullCollateral(uint256 amount_) external override {
        uint256 curDebt = _accruePoolInterest();

        // borrower accounting
        Borrower memory borrower = borrowers[msg.sender];
        (borrower.debt, borrower.inflatorSnapshot) = _accrueBorrowerInterest(borrower.debt, borrower.inflatorSnapshot, inflatorSnapshot);

        uint256 curLup = _lup();
        if (borrower.collateral - _encumberedCollateral(borrower.debt, curLup) < amount_) revert RemoveCollateralInsufficientCollateral();
        borrower.collateral -= amount_;

        // update loan queue
        uint256 thresholdPrice = _t0ThresholdPrice(borrower.debt, borrower.collateral, borrower.inflatorSnapshot);
        if (borrower.debt != 0) loans.upsert(msg.sender, thresholdPrice);

        borrowers[msg.sender] = borrower;

        // update pool state
        pledgedCollateral -= amount_;
        _updateInterestRateAndEMAs(curDebt, curLup);

        // move collateral from pool to sender
        emit PullCollateral(msg.sender, amount_);
        collateral().safeTransfer(msg.sender, amount_ / collateralScale);
    }

    function repay(address borrower_, uint256 maxAmount_) external override {
        _repayDebt(borrower_, maxAmount_);
    }

    /*********************************/
    /*** Lender External Functions ***/
    /*********************************/

    function addCollateral(uint256 amount_, uint256 index_) external override returns (uint256 lpbChange_) {
        uint256 curDebt = _accruePoolInterest();

        // Calculate exchange rate before new collateral has been accounted for.
        // This is consistent with how lbpChange in addQuoteToken is adjusted before calling _add.
        Bucket memory bucket        = buckets[index_];
        uint256 rate                = _exchangeRate(_valueAt(index_), bucket.availableCollateral, bucket.lpAccumulator, index_);
        uint256 quoteValue          = Maths.wmul(amount_, _indexToPrice(index_));
        lpbChange_                 = Maths.rdiv(Maths.wadToRay(quoteValue), rate);
        bucket.lpAccumulator       += lpbChange_;
        bucket.availableCollateral += amount_;
        buckets[index_]            = bucket;

        bucketLenders[index_][msg.sender].lpBalance += lpbChange_;

        _updateInterestRateAndEMAs(curDebt, _lup());

        // move required collateral from sender to pool
        emit AddCollateral(msg.sender, _indexToPrice(index_), amount_);
        collateral().safeTransferFrom(msg.sender, address(this), amount_ / collateralScale);
    }

    function moveCollateral(uint256 amount_, uint256 fromIndex_, uint256 toIndex_) external override returns (uint256 lpbAmountFrom_, uint256 lpbAmountTo_) {
        if (fromIndex_ == toIndex_) revert MoveCollateralToSamePrice();

        Bucket storage fromBucket = buckets[fromIndex_];
        if (fromBucket.availableCollateral < amount_) revert MoveCollateralInsufficientCollateral();

        BucketLender storage bucketLender = bucketLenders[fromIndex_][msg.sender];
        uint256 curDebt                   = _accruePoolInterest();

        // determine amount of amount of LP required
        uint256 rate                 = _exchangeRate(_valueAt(fromIndex_), fromBucket.availableCollateral, fromBucket.lpAccumulator, fromIndex_);
        lpbAmountFrom_               = (amount_ * _indexToPrice(fromIndex_) * 1e18 + rate / 2) / rate;
        if (lpbAmountFrom_ > bucketLender.lpBalance) revert MoveCollateralInsufficientLP();

        // update "from" bucket accounting
        fromBucket.lpAccumulator -= lpbAmountFrom_;
        fromBucket.availableCollateral -= amount_;

        // update "to" bucket accounting
        Bucket storage toBucket      = buckets[toIndex_];
        rate                         = _exchangeRate(_valueAt(toIndex_), toBucket.availableCollateral, toBucket.lpAccumulator, toIndex_);
        lpbAmountTo_                 = (amount_ * _indexToPrice(toIndex_) * 1e18 + rate / 2) / rate;
        toBucket.lpAccumulator       += lpbAmountTo_;
        toBucket.availableCollateral += amount_;

        // update lender accounting
        bucketLender.lpBalance -= lpbAmountFrom_;
        bucketLenders[toIndex_][msg.sender].lpBalance += lpbAmountTo_;

        _updateInterestRateAndEMAs(curDebt, _lup());

        emit MoveCollateral(msg.sender, fromIndex_, toIndex_, amount_);
    }

    function removeAllCollateral(uint256 index_) external override returns (uint256 amount_, uint256 lpAmount_) {
        Bucket memory bucket = buckets[index_];
        if (bucket.availableCollateral == 0) revert RemoveCollateralInsufficientCollateral();

        _accruePoolInterest();

        BucketLender storage bucketLender = bucketLenders[index_][msg.sender];
        uint256 price = _indexToPrice(index_);
        uint256 rate  = _exchangeRate(_valueAt(index_), bucket.availableCollateral, bucket.lpAccumulator, index_);
        lpAmount_     = bucketLender.lpBalance;
        amount_       = Maths.rwdivw(Maths.rmul(lpAmount_, rate), price);
        if (amount_ == 0) revert RemoveCollateralNoClaim();

        if (amount_ > bucket.availableCollateral) {
            // user is owed more collateral than is available in the bucket
            amount_   = bucket.availableCollateral;
            lpAmount_ = Maths.wrdivr(Maths.wmul(amount_, price), rate);
        } // else user is redeeming all of their LPs

        _redeemLPForCollateral(bucket, bucketLender, lpAmount_, amount_, price, index_);
    }

    function removeCollateral(uint256 amount_, uint256 index_) external override returns (uint256 lpAmount_) {
        Bucket memory bucket = buckets[index_];
        if (amount_ > bucket.availableCollateral) revert RemoveCollateralInsufficientCollateral();

        _accruePoolInterest();

        uint256 price = _indexToPrice(index_);
        uint256 rate  = _exchangeRate(_valueAt(index_), bucket.availableCollateral, bucket.lpAccumulator, index_);
        lpAmount_     = Maths.rdiv((amount_ * price / 1e9), rate);

        BucketLender storage bucketLender = bucketLenders[index_][msg.sender];
        if (bucketLender.lpBalance == 0 || lpAmount_ > bucketLender.lpBalance) revert RemoveCollateralInsufficientLP(); // ensure user can actually remove that much

        _redeemLPForCollateral(bucket, bucketLender, lpAmount_, amount_, price, index_);
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

        (borrower.debt,) = _accrueBorrowerInterest(borrower.debt, borrower.inflatorSnapshot, inflatorSnapshot);

        uint256 lup = _lup();
        _updateInterestRateAndEMAs(curDebt, lup);

        if (_borrowerCollateralization(borrower.debt, borrower.collateral, lup) >= Maths.WAD) revert LiquidateBorrowerOk();

        uint256 thresholdPrice = borrower.debt * Maths.WAD / borrower.collateral;
        if (lup > thresholdPrice) revert KickLUPGreaterThanTP();

        uint256 poolPrice = borrowerDebt * Maths.WAD / pledgedCollateral;  // PTP
        // bondFactor = min(30%, max(1%, (poolPrice - thresholdPrice) / poolPrice))
        uint256 bondFactor = thresholdPrice >= poolPrice ? 0.01 * 1e18 : Maths.min(0.3 * 1e18, Maths.max(0.01 * 1e18, 1 * 1e18 - Maths.wdiv(thresholdPrice, poolPrice)));
        uint256 bondSize   = Maths.wmul(bondFactor, borrower.debt);

        uint128 kickTime = uint128(block.timestamp);
        liquidations[borrower_] = LiquidationInfo({
            kickTime:            kickTime,
            referencePrice:      _indexToPrice(_hpbIndex()),
            collateral:          borrower.collateral,
            debt:                borrower.debt,
            bondFactor:          bondFactor,
            bondSize:            bondSize
        });

        auctions.upsert(borrower_, kickTime);
        liquidationDebt += borrower.debt;

        loans.remove(borrower_);
        borrowerDebt -= borrower.debt;
        delete borrowers[borrower_];

        emit Kick(borrower_, borrower.debt, borrower.collateral);
        quoteToken().safeTransferFrom(msg.sender, address(this), bondSize / quoteTokenScale);
    }

    // TODO: Add reentrancy guard
    function take(address borrower_, uint256 amount_, bytes memory swapCalldata_) external override {
        Borrower        memory borrower    = borrowers[borrower_];
        LiquidationInfo memory liquidation = liquidations[borrower_];

        // check liquidation process status
        if (liquidation.kickTime == 0 || block.timestamp - uint256(liquidation.kickTime) <= 1 hours) revert TakeNotPastCooldown();
        if (_borrowerCollateralization(liquidation.debt, liquidation.collateral, _lup()) >= Maths.WAD) revert LiquidateBorrowerOk();

        // TODO: calculate using price decrease function and amount_
        // TODO: remove auction from queue if auctionDebt == 0;

        uint256 thresholdPrice = liquidation.debt * Maths.WAD / liquidation.collateral;
        uint256 timePassed = (block.timestamp - uint256(liquidation.kickTime) - 1 hours) / 3600;
        uint256 price = Maths.wdiv(Maths.WAD, Maths.wpow(2e18, timePassed));

        price = 10 * Maths.wmul(liquidation.referencePrice, price);

        //uint256 neutralPrice = Maths.wmul(thresholdPrice, Maths.wdiv(poolPriceEma, lupEma));
        ////uint256 BPF =  liquidation.bondFactor Maths.wdiv(neutralPrice - price, neutralPrice - thresholdPrice);

        //uint256 liquidationPrice = Maths.WAD;
        //uint256 collateralToPurchase = Maths.wdiv(amount_, liquidationPrice);

        //// Reduce liquidation's remaining collateral
        //liquidations[borrower_].collateral -= collateralToPurchase;

        //// Flash loan full amount to liquidate to borrower
        //collateral().safeTransfer(msg.sender, collateralToPurchase);

        //// Execute arbitrary code at msg.sender address, allowing atomic conversion of asset
        //msg.sender.call(swapCalldata_);

        //// Get current swap price
        //uint256 quoteTokenReturnAmount = _getQuoteTokenReturnAmount(uint256(liquidation.kickTime), uint256(liquidation.referencePrice), collateralToPurchase);

        //_repayDebt(borrower_, quoteTokenReturnAmount);

        //emit Take(borrower_, amount_, collateralToPurchase, 0);
    }


    /**************************/
    /*** Internal Functions ***/
    /**************************/

    function _redeemLPForCollateral(
        Bucket memory bucket,
        BucketLender storage bucketLender,
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

        _updateInterestRateAndEMAs(borrowerDebt, _lup());

        // move collateral from pool to lender
        emit RemoveCollateral(msg.sender, price_, amount_);
        collateral().safeTransfer(msg.sender, amount_ / collateralScale);
    }


    function _repayDebt(address borrower_, uint256 maxAmount_) internal {
        Borrower memory borrower = borrowers[borrower_];
        if (borrower.debt == 0) revert RepayNoDebt();

        uint256 curDebt = _accruePoolInterest();

        // update borrower accounting
        //TODO: check if loan is in liquidation, remove loan from liquidation if repaymentsaves it.
        (borrower.debt, borrower.inflatorSnapshot) = _accrueBorrowerInterest(borrower.debt, borrower.inflatorSnapshot, inflatorSnapshot);
        uint256 amount = Maths.min(borrower.debt, maxAmount_);
        borrower.debt -= amount;
        curDebt       -= amount;

        // update loan queue
        if (borrower.debt == 0) {
            loans.remove(borrower_);
        } else {
            if (loans.count - 1 != 0) if (borrower.debt < _poolMinDebtAmount(curDebt)) revert BorrowAmountLTMinDebt();
            uint256 thresholdPrice = _t0ThresholdPrice(borrower.debt, borrower.collateral, borrower.inflatorSnapshot);
            loans.upsert(borrower_, thresholdPrice);
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
