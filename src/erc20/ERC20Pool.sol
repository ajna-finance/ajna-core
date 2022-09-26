// SPDX-License-Identifier: MIT

pragma solidity 0.8.14;

import { PRBMathSD59x18 } from "@prb-math/contracts/PRBMathSD59x18.sol";
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

    uint256 public override collateralScale;

    /****************************/
    /*** Initialize Functions ***/
    /****************************/

    function initialize(
        uint256 rate_,
        address ajnaTokenAddress_
    ) external {
        if (poolInitializations != 0) revert AlreadyInitialized();

        collateralScale = 10**(18 - collateral().decimals());
        quoteTokenScale = 10**(18 - quoteToken().decimals());

        ajnaTokenAddress           = ajnaTokenAddress_;
        inflatorSnapshot           = 10**18;
        lastInflatorSnapshotUpdate = block.timestamp;
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

    function pledgeCollateral(
        address borrower_,
        uint256 collateralAmountToPledge_
    ) external override {
        _pledgeCollateral(borrower_, collateralAmountToPledge_);

        // move collateral from sender to pool
        emit PledgeCollateral(borrower_, collateralAmountToPledge_);
        collateral().safeTransferFrom(msg.sender, address(this), collateralAmountToPledge_ / collateralScale);
    }

    function pullCollateral(
        uint256 collateralAmountToPull_
    ) external override {
        _pullCollateral(msg.sender, collateralAmountToPull_);

        // move collateral from pool to sender
        emit PullCollateral(msg.sender, collateralAmountToPull_);
        collateral().safeTransfer(msg.sender, collateralAmountToPull_ / collateralScale);
    }

    /*********************************/
    /*** Lender External Functions ***/
    /*********************************/

    function addCollateral(
        uint256 collateralAmountToAdd_,
        uint256 index_
    ) external override returns (uint256 bucketLPs_) {
        bucketLPs_ = _addCollateral(collateralAmountToAdd_, index_);

        // move required collateral from sender to pool
        emit AddCollateral(msg.sender, index_, collateralAmountToAdd_);
        collateral().safeTransferFrom(msg.sender, address(this), collateralAmountToAdd_ / collateralScale);
    }

    function moveCollateral(
        uint256 collateralAmountToMove_,
        uint256 fromIndex_,
        uint256 toIndex_
    ) external override returns (uint256 fromBucketLPs_, uint256 toBucketLPs_) {
        if (fromIndex_ == toIndex_) revert MoveCollateralToSamePrice();

        if (buckets.getCollateral(fromIndex_) < collateralAmountToMove_) revert MoveCollateralInsufficientCollateral();

        uint256 curDebt = _accruePoolInterest();

        fromBucketLPs_ = buckets.collateralToLPs(
            fromIndex_,
            _valueAt(fromIndex_),
            collateralAmountToMove_
        );
        (uint256 lpBalance, ) = lenders.getLenderInfo(
            fromIndex_,
            msg.sender
        );
        if (fromBucketLPs_ > lpBalance) revert MoveCollateralInsufficientLP();

        toBucketLPs_ = buckets.collateralToLPs(
            toIndex_,
            _valueAt(toIndex_),
            collateralAmountToMove_
        );

        // update lender accounting
        lenders.removeLPs(fromIndex_, msg.sender, fromBucketLPs_);
        lenders.addLPs(toIndex_, msg.sender, toBucketLPs_);
        // update buckets
        buckets.removeCollateral(fromIndex_, fromBucketLPs_, collateralAmountToMove_);
        buckets.addCollateral(toIndex_, toBucketLPs_, collateralAmountToMove_);

        _updateInterestRateAndEMAs(curDebt, _lup());

        emit MoveCollateral(msg.sender, fromIndex_, toIndex_, collateralAmountToMove_);
    }

    function removeAllCollateral(
        uint256 index_
    ) external override returns (uint256 collateralAmountRemoved_, uint256 redeemedLenderLPs_) {
        uint256 availableCollateral = buckets.getCollateral(index_);
        if (availableCollateral == 0) revert RemoveCollateralInsufficientCollateral();

        _accruePoolInterest();

        (uint256 lenderLPsBalance, ) = lenders.getLenderInfo(index_, msg.sender);
        (collateralAmountRemoved_, redeemedLenderLPs_) = buckets.lpsToCollateral(
            index_,
            _valueAt(index_),
            lenderLPsBalance,
            availableCollateral
        );
        if (collateralAmountRemoved_ == 0) revert RemoveCollateralNoClaim();

        // update lender accounting
        lenders.removeLPs(index_, msg.sender, redeemedLenderLPs_);
        // update bucket accounting
        buckets.removeCollateral(index_, redeemedLenderLPs_, collateralAmountRemoved_);

        _updateInterestRateAndEMAs(borrowerDebt, _lup());

        // move collateral from pool to lender
        emit RemoveCollateral(msg.sender, index_, collateralAmountRemoved_);
        collateral().safeTransfer(msg.sender, collateralAmountRemoved_ / collateralScale);
    }

    function removeCollateral(
        uint256 collateralAmountToRemove_,
        uint256 index_
    ) external override returns (uint256 bucketLPs_) {
        bucketLPs_ = _removeCollateral(collateralAmountToRemove_, index_);

        // move collateral from pool to lender
        emit RemoveCollateral(msg.sender, index_, collateralAmountToRemove_);
        collateral().safeTransfer(msg.sender, collateralAmountToRemove_ / collateralScale);
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

    

    // TODO: Add reentrancy guard
    function take(address borrower_, uint256 maxAmount_, bytes memory swapCalldata_) external override {
        Borrower    memory borrower    = borrowers[borrower_];
        Liquidation memory liquidation = liquidations[borrower_];

        (uint256 curDebt) = _accruePoolInterest();
        (borrower.debt,) = _accrueBorrowerInterest(borrower.debt, borrower.inflatorSnapshot, inflatorSnapshot);

        uint256 lup = _lup();
        _updateInterestRateAndEMAs(curDebt, lup);

        // check liquidation process status
        (,,bool auctionActive) = getAuction(borrower_);
        if (auctionActive != true) revert NoAuction();
        if (liquidation.kickTime == 0 || block.timestamp - uint256(liquidation.kickTime) <= 1 hours) revert TakeNotPastCooldown();
        if (_borrowerCollateralization(borrower.debt, borrower.collateral, lup) >= Maths.WAD) revert TakeBorrowerSafe();

        // Calculate BPF
        // TODO: remove auction from queue if auctionDebt == 0;
        uint256 price = _auctionPrice(liquidation.referencePrice, uint256(liquidation.kickTime));
        int256 bpf = _bpf(borrower, liquidation, price);

        // Calculate amounts
        uint256 amount = Maths.min(Maths.wmul(price, borrower.collateral), maxAmount_);
        uint256 repayAmount = Maths.wmul(amount, uint256(1e18 - bpf));
        int256 rewardOrPenalty;

        if (repayAmount >= borrower.debt) {
            repayAmount = borrower.debt;
            amount = Maths.wdiv(borrower.debt, uint256(1e18 - bpf));
        }

        if (bpf >= 0) {
            // Take is below neutralPrice, Kicker is rewarded
            rewardOrPenalty = int256(amount - repayAmount);
            liquidation.bondSize += amount - repayAmount;
 
        } else {     
            // Take is above neutralPrice, Kicker is penalized
            rewardOrPenalty = PRBMathSD59x18.mul(int256(amount), bpf);
            liquidation.bondSize -= uint256(-rewardOrPenalty);
        }


        borrowerDebt  -= repayAmount;
        borrower.debt -= repayAmount;

        // Reduce liquidation's remaining collateral
        borrower.collateral -= Maths.wdiv(amount, price);
        pledgedCollateral -= Maths.wdiv(amount, price);

        // If recollateralized remove loan from auction
        if (borrower.collateral != 0 && _borrowerCollateralization(borrower.debt, borrower.collateral, lup) >= Maths.WAD) {
            _removeAuction(borrower_);

            if (borrower.debt != 0) {
                if (loans.count - 1 != 0) if (borrower.debt < _poolMinDebtAmount(curDebt)) revert BorrowAmountLTMinDebt();
                uint256 thresholdPrice = _t0ThresholdPrice(
                    borrower.debt,
                    borrower.collateral,
                    borrower.inflatorSnapshot
                );
                loans.upsert(borrower_, thresholdPrice);

                uint256 numLoans     = (loans.count - 1) * 1e18;
                borrower.mompFactor  = numLoans > 0 ? Maths.wdiv(_momp(numLoans), borrower.inflatorSnapshot): 0;
            }
        }

        borrowers[borrower_] = borrower;
        liquidations[borrower_] = liquidation;

        // TODO: implement flashloan functionality
        // Flash loan full amount to liquidate to borrower
        // Execute arbitrary code at msg.sender address, allowing atomic conversion of asset
        //msg.sender.call(swapCalldata_);
        // Get current swap price
        //uint256 quoteTokenReturnAmount = _getQuoteTokenReturnAmount(uint256(liquidation.kickTime), uint256(liquidation.referencePrice), collateralToPurchase);

        emit Take(borrower_, amount, Maths.wdiv(amount, price), rewardOrPenalty);
        collateral().safeTransfer(msg.sender, Maths.wdiv(amount, price));
        quoteToken().safeTransferFrom(msg.sender, address(this), amount / quoteTokenScale);
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
