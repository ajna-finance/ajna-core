// SPDX-License-Identifier: MIT

pragma solidity 0.8.14;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import './interfaces/IERC20Pool.sol';
import './interfaces/IERC20Taker.sol';
import '../base/FlashloanablePool.sol';

contract ERC20Pool is IERC20Pool, FlashloanablePool {
    using Auctions  for Auctions.Data;
    using Deposits  for Deposits.Data;
    using Loans     for Loans.Data;
    using SafeERC20 for IERC20;

    /****************************/
    /*** Initialize Functions ***/
    /****************************/

    function initialize(
        uint256 rate_
    ) external override {
        if (poolInitializations != 0) revert AlreadyInitialized();

        inflatorSnapshot           = uint208(10**18);
        lastInflatorSnapshotUpdate = uint48(block.timestamp);

        interestParams.interestRate       = uint208(rate_);
        interestParams.interestRateUpdate = uint48(block.timestamp);

        loans.init();

        // increment initializations count to ensure these values can't be updated
        poolInitializations += 1;
    }

    /******************/
    /*** Immutables ***/
    /******************/

    function collateralScale() external pure override returns (uint256) {
        return _getArgUint256(92);
    }

    /***********************************/
    /*** Borrower External Functions ***/
    /***********************************/

    function drawDebt(
        address borrowerAddress_,
        uint256 amountToBorrow_,
        uint256 limitIndex_,
        uint256 collateralToPledge_
    ) external {
        (
            bool pledge,
            bool borrow,
            uint256 newLup
        ) = _drawDebt(
            borrowerAddress_,
            amountToBorrow_,
            limitIndex_,
            collateralToPledge_
        );

        emit DrawDebt(borrowerAddress_, amountToBorrow_, collateralToPledge_, newLup);

        // move collateral from sender to pool
        if (pledge) _transferCollateralFrom(msg.sender, collateralToPledge_);
        // move borrowed amount from pool to sender
        if (borrow) _transferQuoteToken(msg.sender, amountToBorrow_);
    }

    function repayDebt(
        address borrowerAddress_,
        uint256 maxQuoteTokenAmountToRepay_,
        uint256 collateralAmountToPull_
    ) external {
        (uint256 quoteTokenToRepay, uint256 newLup) = _repayDebt(borrowerAddress_, maxQuoteTokenAmountToRepay_, collateralAmountToPull_);

        emit RepayDebt(borrowerAddress_, quoteTokenToRepay, collateralAmountToPull_, newLup);

        if (quoteTokenToRepay != 0) {
            // move amount to repay from sender to pool
            _transferQuoteTokenFrom(msg.sender, quoteTokenToRepay);
        }
        if (collateralAmountToPull_ != 0) {
            // move collateral from pool to sender
            _transferCollateral(msg.sender, collateralAmountToPull_);
        }
    }

    /************************************/
    /*** Flashloan External Functions ***/
    /************************************/

    function flashLoan(
        IERC3156FlashBorrower receiver_,
        address token_,
        uint256 amount_,
        bytes calldata data_
    ) external override(IERC3156FlashLender, FlashloanablePool) nonReentrant returns (bool) {
        if (token_ == _getArgAddress(20)) return _flashLoanQuoteToken(receiver_, token_, amount_, data_);

        if (token_ == _getArgAddress(0)) {
            _transferCollateral(address(receiver_), amount_);            
            
            if (receiver_.onFlashLoan(msg.sender, token_, amount_, 0, data_) != 
                keccak256("ERC3156FlashBorrower.onFlashLoan")) revert FlashloanCallbackFailed();

            _transferCollateralFrom(address(receiver_), amount_);
            return true;
        }

        revert FlashloanUnavailableForToken();
    }

    function flashFee(
        address token_,
        uint256
    ) external pure override(IERC3156FlashLender, FlashloanablePool) returns (uint256) {
        if (token_ == _getArgAddress(20) || token_ == _getArgAddress(0)) return 0;
        revert FlashloanUnavailableForToken();
    }

    function maxFlashLoan(
        address token_
    ) external view override(IERC3156FlashLender, FlashloanablePool) returns (uint256 maxLoan_) {
        if (token_ == _getArgAddress(20) || token_ == _getArgAddress(0)) {
            maxLoan_ = IERC20Token(token_).balanceOf(address(this));
        }
    }

    /*********************************/
    /*** Lender External Functions ***/
    /*********************************/

    function addCollateral(
        uint256 collateralAmountToAdd_,
        uint256 index_
    ) external override returns (uint256 bucketLPs_) {
        PoolState memory poolState = _accruePoolInterest();

        bucketLPs_ = LenderActions.addCollateral(
            buckets,
            deposits,
            collateralAmountToAdd_,
            index_
        );

        _updateInterestParams(poolState, _lup(poolState.accruedDebt));

        emit AddCollateral(msg.sender, index_, collateralAmountToAdd_);
        // move required collateral from sender to pool
        _transferCollateralFrom(msg.sender, collateralAmountToAdd_);
    }

    function removeCollateral(
        uint256 maxAmount_,
        uint256 index_
    ) external override returns (uint256 collateralAmount_, uint256 lpAmount_) {
        auctions.revertIfAuctionClearable(loans);

        PoolState memory poolState = _accruePoolInterest();

        (collateralAmount_, lpAmount_) = LenderActions.removeMaxCollateral(
            buckets,
            deposits,
            maxAmount_,
            index_
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

        Auctions.TakeParams memory params = Auctions.TakeParams(
            {
                borrower:       borrowerAddress_,
                collateral:     borrower.collateral,
                t0debt:         borrower.t0debt,
                takeCollateral: collateral_,
                inflator:       poolState.inflator
            }
        );
        (
            uint256 collateralAmount,
            uint256 quoteTokenAmount,
            uint256 t0repayAmount,
        ) = Auctions.take(
            auctions,
            params
        );

        borrower.collateral  -= collateralAmount;
        poolState.collateral -= collateralAmount;

        _payLoan(t0repayAmount, poolState, params.borrower, borrower);
        pledgedCollateral = poolState.collateral;

        _transferCollateral(callee_, collateralAmount);

        if (data_.length != 0) {
            IERC20Taker(callee_).atomicSwapCallback(
                collateralAmount / _getArgUint256(92), 
                quoteTokenAmount / _getArgUint256(40), 
                data_
            );
        }

        _transferQuoteTokenFrom(callee_, quoteTokenAmount);
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
        IERC20(_getArgAddress(0)).safeTransferFrom(from_, address(this), amount_ / _getArgUint256(92));
    }

    function _transferCollateral(address to_, uint256 amount_) internal {
        IERC20(_getArgAddress(0)).safeTransfer(to_, amount_ / _getArgUint256(92));
    }
}
