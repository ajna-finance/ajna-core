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

    function pledgeCollateral(
        address borrower_,
        uint256 collateralAmountToPledge_
    ) external override {
        _pledgeCollateral(borrower_, collateralAmountToPledge_);

        // move collateral from sender to pool
        emit PledgeCollateral(borrower_, collateralAmountToPledge_);
        _transferCollateralFrom(msg.sender, collateralAmountToPledge_);
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
            fromBucket,
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

        (uint256 lenderLPsBalance, ) = buckets.getLenderInfo(
            index_,
            msg.sender
        );

        PoolState memory poolState = _accruePoolInterest();

        Buckets.Bucket storage bucket = buckets[index_];
        (collateralAmountRemoved_, redeemedLenderLPs_) = Buckets.lpsToCollateral(
            bucket,
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

    function arbTake(
        address borrowerAddress_,
        uint256 index_
    ) external override {
        Loans.Borrower memory borrower  = loans.getBorrowerInfo(borrowerAddress_);
        if (borrower.collateral == 0) revert InsufficientCollateral(); // revert if borrower's collateral is 0

        PoolState memory poolState = _accruePoolInterest();
        uint256 bucketDeposit = deposits.valueAt(index_);
        if (bucketDeposit == 0) revert InsufficientLiquidity(); // revert if no quote tokens in arbed bucket

        Auctions.Liquidation storage liquidation = auctions.liquidations[borrowerAddress_];
        (
            uint256 quoteTokenAmount,
            uint256 t0repaidDebt,
            uint256 collateralArbed,
            uint256 auctionPrice,
            uint256 bondChange,
            bool isRewarded
        ) = auctions.arbTake(liquidation, borrower, bucketDeposit, poolState.inflator);

        uint256 depositAmountToRemove = quoteTokenAmount;
        // bucket operations
        {
            // cannot arb with a price lower than or equal with the auction price
            uint256 bucketPrice = PoolUtils.indexToPrice(index_);
            if (auctionPrice >= bucketPrice) revert AuctionPriceGteQArbPrice();

            Buckets.Bucket storage bucket = buckets[index_];
            uint256 bucketExchangeRate = Buckets.getExchangeRate(
                bucket,
                bucketDeposit,
                bucketPrice
            );

            // taker is awarded collateral * (bucket price - auction price) worth (in quote token terms) units of LPB in the bucket
            Buckets.addLPs(
                bucket,
                msg.sender,
                Maths.wrdivr(
                    Maths.wmul(collateralArbed, bucketPrice - auctionPrice),
                    bucketExchangeRate
                )
            );
            // the bondholder/kicker is awarded bond change worth of LPB in the bucket
            if (isRewarded) {
                Buckets.addLPs(
                    bucket,
                    liquidation.kicker,
                    Maths.wrdivr(bondChange, bucketExchangeRate)
                );
                depositAmountToRemove -= bondChange;
            }

            // collateral is moved to the bucket’s claimable collateral
            bucket.collateral += collateralArbed;
        }

        // quote tokens are removed from the bucket’s deposit
        deposits.remove(index_, depositAmountToRemove);

        // collateral is ewmoved from the loan
        borrower.collateral -= collateralArbed;
        _payLoan(t0repaidDebt, poolState, borrowerAddress_, borrower);

        emit ArbTake(borrowerAddress_, index_, quoteTokenAmount, collateralArbed, bondChange, isRewarded);
    }

    function depositTake(address borrower_, uint256 amount_, uint256 index_) external override {
        // TODO: implement
        emit DepositTake(borrower_, index_, amount_, 0, 0);
    }

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

        (
            uint256 quoteTokenAmount,
            uint256 t0repaidDebt,
            uint256 collateralTaken,
            ,
            uint256 bondChange,
            bool isRewarded
        ) = auctions.take(borrowerAddress_, borrower, collateral_, poolState.inflator);

        borrower.collateral  -= collateralTaken;
        poolState.collateral -= collateralTaken;

        _payLoan(t0repaidDebt, poolState, borrowerAddress_, borrower);

        emit Take(borrowerAddress_, quoteTokenAmount, collateralTaken, bondChange, isRewarded);

        // TODO: implement flashloan functionality
        // Flash loan full amount to liquidate to borrower
        // Execute arbitrary code at msg.sender address, allowing atomic conversion of asset
        //msg.sender.call(swapCalldata_);

        _transferQuoteTokenFrom(msg.sender, quoteTokenAmount);
        _transferCollateral(msg.sender, collateralTaken);
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
