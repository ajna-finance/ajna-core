// SPDX-License-Identifier: MIT

pragma solidity 0.8.14;

import './interfaces/IERC20Pool.sol';
import './interfaces/IERC20Taker.sol';
import '../base/FlashloanablePool.sol';

contract ERC20Pool is IERC20Pool, FlashloanablePool {
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

    function take(
        address        borrowerAddress_,
        uint256        collateral_,
        address        callee_,
        bytes calldata data_
    ) external override nonReentrant {
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

        emit Take(
            borrowerAddress_,
            params.quoteTokenAmount,
            params.collateralAmount,
            params.bondChange,
            params.isRewarded
        );

        _payLoan(params.t0repayAmount, poolState, borrowerAddress_, borrower);

        _transferCollateral(callee_, params.collateralAmount);

        if (data_.length != 0) {
            IERC20Taker(callee_).atomicSwapCallback(
                params.collateralAmount / collateralScale, 
                params.quoteTokenAmount / _getArgUint256(40), 
                data_
            );
        }

        _transferQuoteTokenFrom(callee_, params.quoteTokenAmount);
    }

    /*******************************/
    /*** Pool Override Functions ***/
    /*******************************/

    /**
     *  @notice ERC20 collateralization calculation.
     *  @param debt_       Debt to calculate collateralization for.
     *  @param collateral_ Collateral to calculate collateralization for.
     *  @param price_      Price to calculate collateralization for.
     *  @return True if collateralization calculated is equal or greater than 1.
     */
    function _isCollateralized(
        uint256 debt_,
        uint256 collateral_,
        uint256 price_
    ) internal pure override returns (bool) {
        return Maths.wmul(collateral_, price_) >= debt_;
    }

   /**
     *  @notice Settle an ERC20 pool auction, remove from auction queue and emit event.
     *  @param borrowerAddress_    Address of the borrower that exits auction.
     *  @param borrowerCollateral_ Borrower collateral amount before auction exit.
     *  @return floorCollateral_   Remaining borrower collateral after auction exit.
     */
    function _settleAuction(
        address borrowerAddress_,
        uint256 borrowerCollateral_
    ) internal override returns (uint256) {
        Auctions.settleERC20Auction(auctions, borrowerAddress_);
        emit AuctionSettle(borrowerAddress_, borrowerCollateral_);
        return borrowerCollateral_;
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
