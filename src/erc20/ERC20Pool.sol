// SPDX-License-Identifier: MIT

pragma solidity 0.8.14;

import '@openzeppelin/contracts/token/ERC20/ERC20.sol';
import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';

import './interfaces/IERC20Pool.sol';

import '../base/Pool.sol';

import '../libraries/Heap.sol';
import '../libraries/Maths.sol';
import '../libraries/Book.sol';
import '../libraries/Actors.sol';

contract ERC20Pool is IERC20Pool, Pool {
    using SafeERC20 for ERC20;
    using Book      for mapping(uint256 => Book.Bucket);
    using Book      for Book.Deposits;
    using Actors    for mapping(uint256 => mapping(address => Actors.Lender));
    using Actors    for mapping(address => Actors.Borrower);
    using Heap      for Heap.Data;
    using Queue     for Queue.Data;

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
    ) external override {
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

        PoolState memory poolState = _getPoolState();

        uint256 fromBucketCollateral;
        (fromBucketLPs_, fromBucketCollateral) = buckets.collateralToLPs(
            fromIndex_,
            deposits.valueAt(fromIndex_),
            collateralAmountToMove_
        );
        if (fromBucketCollateral < collateralAmountToMove_) revert MoveCollateralInsufficientCollateral();

        (uint256 lpBalance, ) = lenders.getLenderInfo(
            fromIndex_,
            msg.sender
        );
        if (fromBucketLPs_ > lpBalance) revert MoveCollateralInsufficientLP();

        (toBucketLPs_, ) = buckets.collateralToLPs(
            toIndex_,
            deposits.valueAt(toIndex_),
            collateralAmountToMove_
        );

        // update lender accounting
        lenders.removeLPs(fromIndex_, msg.sender, fromBucketLPs_);
        lenders.addLPs(toIndex_, msg.sender, toBucketLPs_);
        // update buckets
        buckets.removeCollateral(fromIndex_, fromBucketLPs_, collateralAmountToMove_);
        buckets.addCollateral(toIndex_, toBucketLPs_, collateralAmountToMove_);

        _updatePool(poolState, _lup(poolState.accruedDebt));

        emit MoveCollateral(msg.sender, fromIndex_, toIndex_, collateralAmountToMove_);
    }

    function removeAllCollateral(
        uint256 index_
    ) external override returns (uint256 collateralAmountRemoved_, uint256 redeemedLenderLPs_) {

        PoolState memory poolState = _getPoolState();

        (uint256 lenderLPsBalance, ) = lenders.getLenderInfo(index_, msg.sender);
        (collateralAmountRemoved_, redeemedLenderLPs_) = buckets.lpsToCollateral(
            index_,
            deposits.valueAt(index_),
            lenderLPsBalance
        );
        if (collateralAmountRemoved_ == 0) revert RemoveCollateralNoClaim();

        // update lender accounting
        lenders.removeLPs(index_, msg.sender, redeemedLenderLPs_);
        // update bucket accounting
        buckets.removeCollateral(index_, redeemedLenderLPs_, collateralAmountRemoved_);

        _updatePool(poolState, _lup(poolState.accruedDebt));

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
    function take(address borrower_, uint256 maxCollateral_, bytes memory swapCalldata_) external override {

        (
            uint256 borrowerAccruedDebt,
            uint256 borrowerPledgedCollateral,
            uint256 borrowerMompFactor,
            uint256 liquidationBondSize,
            int256  rewardOrPenalty,
            PoolState memory poolState,
            uint256 amount,
            uint256 price
        ) = _take(borrower_, maxCollateral_);

        // Reduce liquidation's remaining collateral
        // TODO: refactor collateral
        pledgedCollateral         -= maxCollateral_;
        borrowerPledgedCollateral -= Maths.wdiv(amount, price);

        uint256 newLup = _lup(pledgedCollateral);
        // update loan queue
        if (borrowerPledgedCollateral != 0 && PoolUtils.collateralization(borrowerAccruedDebt, borrowerPledgedCollateral, newLup) >= Maths.WAD) {
            auctions.remove(borrower_);

            if (borrowerAccruedDebt > 0) {
                uint256 loansCount = loans.count - 1;
                if (loansCount != 0
                    &&
                    (borrowerAccruedDebt < PoolUtils.minDebtAmount(poolState.accruedDebt, loansCount))
                ) revert BorrowAmountLTMinDebt();

                uint256 thresholdPrice = PoolUtils.t0ThresholdPrice(
                    borrowerAccruedDebt,
                    borrowerPledgedCollateral,
                    poolState.inflator
                );
                loans.upsert(borrower_, thresholdPrice);
            } 
        }

        uint256 numLoans   = (loans.count - 1) * 1e18;
        borrowerMompFactor = numLoans > 0 ? Maths.wdiv(_momp(numLoans), poolState.inflator): 0;

        borrowers.update(
            borrower_,
            borrowerAccruedDebt,
            borrowerPledgedCollateral,
            borrowerMompFactor,
            poolState.inflator);
        
        _updatePool(poolState, newLup);
        liquidations[borrower_].bondSize = liquidationBondSize;

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

    //function kick(address borrower_) external override {
    //    PoolState memory poolState = _getPoolState();

    //    (uint256 borrowerAccruedDebt, uint256 borrowerPledgedCollateral) = borrowers.getBorrowerInfo(
    //        borrower_,
    //        poolState.inflator
    //    );
    //    if (borrowerAccruedDebt == 0) revert KickNoDebt();

    //    uint256 lup = _lup(poolState.accruedDebt);

    //    if (
    //        PoolUtils.collateralization(
    //            borrowerAccruedDebt,
    //            borrowerPledgedCollateral,
    //            lup
    //        ) >= Maths.WAD
    //    ) revert LiquidateBorrowerOk();

    //    uint256 thresholdPrice = borrowerAccruedDebt * Maths.WAD / borrowerPledgedCollateral;
    //    if (lup > thresholdPrice) revert KickLUPGreaterThanTP();

    //    borrowers.updateDebt(
    //        borrower_,
    //        borrowerAccruedDebt,
    //        poolState.inflator
    //    );

    //    _updatePool(poolState, lup);

    //    liquidations[borrower_] = Liquidation({
    //        kickTime:            uint128(block.timestamp),
    //        referencePrice:      uint128(_hpbIndex()),
    //        remainingCollateral: borrowerPledgedCollateral,
    //        remainingDebt:       borrowerAccruedDebt
    //    });

    //    // TODO: Uncomment when needed
    //    // uint256 poolPrice      = borrowerDebt * Maths.WAD / pledgedCollateral;  // PTP

    //    // TODO: Post liquidation bond (use max bond factor of 1% but leave todo to revisit)
    //    // TODO: Account for repossessed collateral
    //    liquidationBondEscrowed += Maths.wmul(borrowerAccruedDebt, 0.01 * 1e18);

    //    // Post the liquidation bond
    //    // Repossess the borrowers collateral, initialize the auction cooldown timer

    //    emit Kick(borrower_, borrowerAccruedDebt, borrowerPledgedCollateral);
    //}
    

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
