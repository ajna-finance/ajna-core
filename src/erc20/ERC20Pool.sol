// SPDX-License-Identifier: MIT

pragma solidity 0.8.14;

import './interfaces/IERC20Pool.sol';
import '../base/Pool.sol';

contract ERC20Pool is IERC20Pool, Pool {
    using Auctions for Auctions.Data;
    using Buckets  for mapping(uint256 => Buckets.Bucket);
    using Deposits for Deposits.Data;
    using Loans    for Loans.Data;

    /***********************/
    /*** State Variables ***/
    /***********************/

    uint256 public override collateralScale;

    /****************************/
    /*** Initialize Functions ***/
    /****************************/

    function initialize(
        uint256 collateralScale_,
        uint256 rate_
    ) external override {
        if (poolInitializations != 0) revert AlreadyInitialized();

        collateralScale = collateralScale_;

        inflatorSnapshot           = 10**18;
        lastInflatorSnapshotUpdate = block.timestamp;
        interestRate               = rate_;
        interestRateUpdate         = block.timestamp;

        loans.init();

        // increment initializations count to ensure these values can't be updated
        poolInitializations += 1;
    }

    /***********************************/
    /*** Borrower External Functions ***/
    /***********************************/

    // function pledgeCollateral(
    //     address borrower_,
    //     uint256 collateralAmountToPledge_
    // ) external override {
    //     _pledgeCollateral(borrower_, collateralAmountToPledge_);

    //     // move collateral from sender to pool
    //     emit PledgeCollateral(borrower_, collateralAmountToPledge_);
    //     _transferCollateralFrom(msg.sender, collateralAmountToPledge_);
    // }

    function drawDebt(
        address borrower_,
        uint256 amountToBorrow_,
        uint256 limitIndex_,
        uint256 collateralToPledge_
    ) external {
        PoolState memory poolState = _accruePoolInterest();

        // pledge collateral to pool
        if (collateralToPledge_ != 0) {
            _pledgeCollateral(poolState, borrower_, collateralToPledge_);

            // move collateral from sender to pool
            emit PledgeCollateral(borrower_, collateralToPledge_);
            _transferCollateralFrom(borrower_, collateralToPledge_);
        }

        // borrow against pledged collateral
        if (amountToBorrow_ != 0) _borrow(poolState, amountToBorrow_, limitIndex_);
    }

    function pullCollateral(
        uint256 collateralAmountToPull_
    ) external override {
        _pullCollateral(collateralAmountToPull_);

        // move collateral from pool to sender
        emit PullCollateral(msg.sender, collateralAmountToPull_);
        _transferCollateral(msg.sender, collateralAmountToPull_);
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
        _transferCollateralFrom(msg.sender, collateralAmountToAdd_);
    }

    function moveCollateral(
        uint256 collateralAmountToMove_,
        uint256 fromIndex_,
        uint256 toIndex_
    ) external override returns (uint256 fromBucketLPs_, uint256 toBucketLPs_) {
        if (fromIndex_ == toIndex_) revert MoveToSamePrice();

        Buckets.Bucket storage fromBucket = buckets[fromIndex_];
        if (fromBucket.collateral < collateralAmountToMove_) revert InsufficientCollateral();

        PoolState memory poolState = _accruePoolInterest();

        fromBucketLPs_= Buckets.collateralToLPs(
            fromBucket.collateral,
            fromBucket.lps,
            deposits.valueAt(fromIndex_),
            collateralAmountToMove_,
            PoolUtils.indexToPrice(fromIndex_)
        );

        (uint256 lpBalance, ) = buckets.getLenderInfo(
            fromIndex_,
            msg.sender
        );
        if (fromBucketLPs_ > lpBalance) revert InsufficientLPs();

        Buckets.removeCollateral(
            fromBucket,
            collateralAmountToMove_,
            fromBucketLPs_
        );
        toBucketLPs_ = Buckets.addCollateral(
            buckets[toIndex_],
            deposits.valueAt(toIndex_),
            collateralAmountToMove_,
            PoolUtils.indexToPrice(toIndex_)
        );

        _updatePool(poolState, _lup(poolState.accruedDebt));

        emit MoveCollateral(msg.sender, fromIndex_, toIndex_, collateralAmountToMove_);
    }

    function removeAllCollateral(
        uint256 index_
    ) external override returns (uint256 collateralAmountRemoved_, uint256 redeemedLenderLPs_) {
        auctions.revertIfAuctionClearable(loans);

        (uint256 lenderLPsBalance, ) = buckets.getLenderInfo(
            index_,
            msg.sender
        );

        PoolState memory poolState = _accruePoolInterest();

        Buckets.Bucket storage bucket = buckets[index_];
        (collateralAmountRemoved_, redeemedLenderLPs_) = Buckets.lpsToCollateral(
            bucket.collateral,
            bucket.lps,
            deposits.valueAt(index_),
            lenderLPsBalance,
            PoolUtils.indexToPrice(index_)
        );
        if (collateralAmountRemoved_ == 0) revert NoClaim();

        Buckets.removeCollateral(
            bucket,
            collateralAmountRemoved_,
            redeemedLenderLPs_)
        ;

        _updatePool(poolState, _lup(poolState.accruedDebt));

        // move collateral from pool to lender
        emit RemoveCollateral(msg.sender, index_, collateralAmountRemoved_);
        _transferCollateral(msg.sender, collateralAmountRemoved_);
    }

    function removeCollateral(
        uint256 collateralAmountToRemove_,
        uint256 index_
    ) external override returns (uint256 bucketLPs_) {
        bucketLPs_ = _removeCollateral(collateralAmountToRemove_, index_);

        // move collateral from pool to lender
        emit RemoveCollateral(msg.sender, index_, collateralAmountToRemove_);
        _transferCollateral(msg.sender, collateralAmountToRemove_);
    }

    /*******************************/
    /*** Pool External Functions ***/
    /*******************************/

    /**
     *  @notice Performs take checks, calculates amounts and bpf reward / penalty.
     *  @dev Internal support method assisting in the ERC20 and ERC721 pool take calls.
     *  @param borrowerAddress_   Address of the borower take is being called upon.
     *  @param collateral_        Max amount of collateral to take, submited by the taker.
     */
    function take(
        address borrowerAddress_,
        uint256 collateral_,
        bytes memory swapCalldata_
    ) external override {
        PoolState      memory poolState = _accruePoolInterest();
        Loans.Borrower memory borrower  = loans.getBorrowerInfo(borrowerAddress_);
        if (borrower.collateral == 0 || collateral_ == 0) revert InsufficientCollateral(); // revert if borrower's collateral is 0 or if maxCollateral to be taken is 0

        Auctions.TakeParams memory params = Auctions.take(
            auctions,
            borrowerAddress_,
            borrower,
            collateral_,
            poolState.inflator
        );

        borrower.collateral  -= params.collateralAmount;
        poolState.collateral -= params.collateralAmount;

        _payLoan(params.t0repayAmount, poolState, borrowerAddress_, borrower);

        emit Take(
            borrowerAddress_,
            params.quoteTokenAmount,
            params.collateralAmount,
            params.bondChange,
            params.isRewarded
        );

        // TODO: implement flashloan functionality
        // Flash loan full amount to liquidate to borrower
        // Execute arbitrary code at msg.sender address, allowing atomic conversion of asset
        //msg.sender.call(swapCalldata_);

        _transferQuoteTokenFrom(msg.sender, params.quoteTokenAmount);
        _transferCollateral(msg.sender, params.collateralAmount);
    }

    /************************/
    /*** Helper Functions ***/
    /************************/

    function _transferCollateralFrom(address from_, uint256 amount_) internal {
        if (!IERC20Token(_getArgAddress(0)).transferFrom(from_, address(this), amount_ / collateralScale)) revert ERC20TransferFailed();
    }

    function _transferCollateral(address to_, uint256 amount_) internal {
        if (!IERC20Token(_getArgAddress(0)).transfer(to_, amount_ / collateralScale)) revert ERC20TransferFailed();
    }
}
