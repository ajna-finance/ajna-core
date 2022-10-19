// SPDX-License-Identifier: MIT

pragma solidity 0.8.14;

import '@openzeppelin/contracts/token/ERC20/ERC20.sol';
import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';

import './interfaces/IERC20Pool.sol';

import '../base/Pool.sol';

contract ERC20Pool is IERC20Pool, Pool {
    using SafeERC20 for ERC20;
    using Buckets   for mapping(uint256 => Buckets.Bucket);
    using Deposits  for Deposits.Data;
    using Loans     for Loans.Data;

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
        if (poolInitializations != 0)         revert AlreadyInitialized();
        if (ajnaTokenAddress_ == address(0))  revert Token0xAddress();

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
        _pullCollateral(collateralAmountToPull_);

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
        if (fromIndex_ == toIndex_) revert MoveToSamePrice();

        PoolState memory poolState = _accruePoolInterest();

        uint256 fromBucketCollateral;
        (fromBucketLPs_, fromBucketCollateral) = buckets.collateralToLPs(
            deposits.valueAt(fromIndex_),
            collateralAmountToMove_,
            fromIndex_
        );
        if (fromBucketCollateral < collateralAmountToMove_) revert InsufficientCollateral();

        (uint256 lpBalance, ) = buckets.getLenderInfo(
            fromIndex_,
            msg.sender
        );
        if (fromBucketLPs_ > lpBalance) revert InsufficientLPs();

        buckets.removeCollateral(collateralAmountToMove_, fromBucketLPs_, fromIndex_);
        toBucketLPs_ = buckets.addCollateral(deposits.valueAt(toIndex_), collateralAmountToMove_, toIndex_);

        _updatePool(poolState, 0, _lup(poolState.accruedDebt));

        emit MoveCollateral(msg.sender, fromIndex_, toIndex_, collateralAmountToMove_);
    }

    function removeAllCollateral(
        uint256 index_
    ) external override returns (uint256 collateralAmountRemoved_, uint256 redeemedLenderLPs_) {

        PoolState memory poolState = _accruePoolInterest();

        (uint256 lenderLPsBalance, ) = buckets.getLenderInfo(index_, msg.sender);
        (collateralAmountRemoved_, redeemedLenderLPs_) = buckets.lpsToCollateral(
            deposits.valueAt(index_),
            lenderLPsBalance,
            index_
        );
        if (collateralAmountRemoved_ == 0) revert NoClaim();

        buckets.removeCollateral(collateralAmountRemoved_, redeemedLenderLPs_, index_);
        _updatePool(poolState, 0, _lup(poolState.accruedDebt));

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

    function take(
        address borrower_,
        uint256 maxCollateral_,
        bytes memory swapCalldata_
    ) external override {
        uint256 collateralTaken = _take(borrower_, maxCollateral_);

        // TODO: implement flashloan functionality
        // Flash loan full amount to liquidate to borrower
        // Execute arbitrary code at msg.sender address, allowing atomic conversion of asset
        //msg.sender.call(swapCalldata_);

        collateral().safeTransfer(msg.sender, collateralTaken);
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
