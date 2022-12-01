// SPDX-License-Identifier: MIT

pragma solidity 0.8.14;

import './interfaces/IERC20Pool.sol';
import './interfaces/IERC20Taker.sol';
import '../base/FlashloanablePool.sol';

import '@std/console.sol';

contract ERC20Pool is IERC20Pool, FlashloanablePool {
    using Auctions for Auctions.Data;
    using Buckets  for mapping(uint256 => Buckets.Bucket);
    using Deposits for Deposits.Data;
    using Loans    for Loans.Data;

    /***********************/
    /*** State Variables ***/
    /***********************/

    uint128 public override collateralScale;

    /****************************/
    /*** Initialize Functions ***/
    /****************************/

    function initialize(
        uint256 collateralScale_,
        uint256 rate_
    ) external override {
        if (poolInitializations != 0) revert AlreadyInitialized();

        collateralScale = uint128(collateralScale_);

        inflatorSnapshot           = uint208(10**18);
        lastInflatorSnapshotUpdate = uint48(block.timestamp);
        interestRate               = uint208(rate_);
        interestRateUpdate         = uint48(block.timestamp);

        loans.init();

        // increment initializations count to ensure these values can't be updated
        poolInitializations += 1;
    }

    /***********************************/
    /*** Borrower External Functions ***/
    /***********************************/

    function drawDebt(
        address borrower_,
        uint256 amountToBorrow_,
        uint256 limitIndex_,
        uint256 collateralToPledge_
    ) external {
        PoolState memory poolState = _accruePoolInterest();
        Loans.Borrower memory borrower = loans.getBorrowerInfo(borrower_);

        uint256 newLup = _lup(poolState.accruedDebt);

        // pledge collateral to pool
        if (collateralToPledge_ != 0) {

            borrower.collateral  += collateralToPledge_;
            poolState.collateral += collateralToPledge_;

            if (
                auctions.isActive(borrower_)
                &&
                _isCollateralized(
                    Maths.wmul(borrower.t0debt, poolState.inflator),
                    borrower.collateral,
                    newLup
                )
            )
            {
                // borrower becomes collateralized, remove debt from pool accumulator and settle auction
                t0DebtInAuction     -= borrower.t0debt;
                borrower.collateral = _settleAuction(borrower_, borrower.collateral);
            }

            pledgedCollateral = poolState.collateral;

            // move collateral from sender to pool
            _transferCollateralFrom(msg.sender, collateralToPledge_);
        }

        // borrow against pledged collateral
        // check both values to enable an intentional 0 borrow loan call to update borrower's loan state
        if (amountToBorrow_ != 0 || limitIndex_ != 0) {

            // if borrower auctioned then it cannot draw more debt
            auctions.revertIfActive(borrower_);

            uint256 borrowerDebt = Maths.wmul(borrower.t0debt, poolState.inflator);

            // add origination fee to the amount to borrow and add to borrower's debt
            uint256 debtChange   = Maths.wmul(amountToBorrow_, PoolUtils.feeRate(interestRate) + Maths.WAD);
            borrowerDebt += debtChange;
            _checkMinDebt(poolState.accruedDebt, borrowerDebt);

            // determine new lup index and revert if borrow happens at a price higher than the specified limit (lower index than lup index)
            uint256 lupId = _lupIndex(poolState.accruedDebt + amountToBorrow_);
            if (lupId > limitIndex_) revert LimitIndexReached();

            // calculate new lup and check borrow action won't push borrower into a state of under-collateralization
            newLup = PoolUtils.indexToPrice(lupId);
            if (
                !_isCollateralized(borrowerDebt, borrower.collateral, newLup)
            ) revert BorrowerUnderCollateralized();

            // check borrow won't push pool into a state of under-collateralization
            poolState.accruedDebt += debtChange;
            if (
                !_isCollateralized(poolState.accruedDebt, poolState.collateral, newLup)
            ) revert PoolUnderCollateralized();

            uint256 t0debtChange = Maths.wdiv(debtChange, poolState.inflator);
            borrower.t0debt += t0debtChange;

            t0poolDebt += t0debtChange;

            // move borrowed amount from pool to sender
            _transferQuoteToken(msg.sender, amountToBorrow_);

        }

        emit DrawDebt(borrower_, amountToBorrow_, collateralToPledge_, newLup);

        // update loan state
        loans.update(
            deposits,
            borrower_,
            true,
            borrower,
            poolState.accruedDebt,
            poolState.inflator,
            poolState.rate,
            newLup
        );

        // update pool global interest rate state
        _updateInterestParams(poolState, newLup);

        // if (poolState.accruedDebt != 0) {
        //     _updateInterestParams(poolState, newLup);
        // }
    }

    function pullCollateral(
        uint256 collateralAmountToPull_
    ) external override {
        _pullCollateral(collateralAmountToPull_);

        emit PullCollateral(msg.sender, collateralAmountToPull_);
        // move collateral from pool to sender
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

        emit AddCollateral(msg.sender, index_, collateralAmountToAdd_);
        // move required collateral from sender to pool
        _transferCollateralFrom(msg.sender, collateralAmountToAdd_);
    }

    function removeCollateral(
        uint256 maxAmount_,
        uint256 index_
    ) external override returns (uint256 collateralAmount_, uint256 lpAmount_) {
        auctions.revertIfAuctionClearable(loans);

        Buckets.Bucket storage bucket = buckets[index_];
        if (bucket.collateral == 0) revert InsufficientCollateral(); // revert if there's no collateral in bucket

        (uint256 lenderLpBalance, ) = buckets.getLenderInfo(index_, msg.sender);
        if (lenderLpBalance == 0) revert NoClaim();                  // revert if no LP to redeem

        PoolState memory poolState = _accruePoolInterest();
        uint256 bucketPrice = PoolUtils.indexToPrice(index_);
        uint256 exchangeRate = Buckets.getExchangeRate(
            bucket.collateral,
            bucket.lps,
            deposits.valueAt(index_),
            bucketPrice
        );

        // limit amount by what is available in the bucket
        collateralAmount_ = Maths.min(maxAmount_, bucket.collateral);

        // determine how much LP would be required to remove the requested amount
        uint256 requiredLPs = (collateralAmount_ * bucketPrice * 1e18 + exchangeRate / 2) / exchangeRate;

        // limit withdrawal by the lender's LPB
        if (requiredLPs < lenderLpBalance) {
            lpAmount_ = requiredLPs;
        } else {
            lpAmount_ = lenderLpBalance;
            collateralAmount_ = ((lpAmount_ * exchangeRate + 1e27 / 2) / 1e18 + bucketPrice / 2) / bucketPrice;
        }

        Buckets.removeCollateral(
            bucket,
            collateralAmount_,
            lpAmount_
        );

        _updateInterestParams(poolState, _lup(poolState.accruedDebt));

        emit RemoveCollateral(msg.sender, index_, collateralAmount_);
        // move collateral from pool to lender
        _transferCollateral(msg.sender, collateralAmount_);
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
        // revert if borrower's collateral is 0 or if maxCollateral to be taken is 0
        if (borrower.collateral == 0 || collateral_ == 0) revert InsufficientCollateral();

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
        pledgedCollateral = poolState.collateral;

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
