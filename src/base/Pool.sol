// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.14;

import '@clones/Clone.sol';
import '@openzeppelin/contracts/security/ReentrancyGuard.sol';
import '@openzeppelin/contracts/utils/Multicall.sol';
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import './interfaces/IPool.sol';

import './PoolHelper.sol';

import '../libraries/Buckets.sol';
import '../libraries/Deposits.sol';
import '../libraries/Loans.sol';

import '../libraries/external/Auctions.sol';
import '../libraries/external/LenderActions.sol';
import '../libraries/external/PoolCommons.sol';

abstract contract Pool is Clone, ReentrancyGuard, Multicall, IPool {
    using SafeERC20 for IERC20;

    /*****************/
    /*** Constants ***/
    /*****************/

    // immutable args offset
    uint256 internal constant POOL_TYPE          = 0;
    uint256 internal constant AJNA_ADDRESS       = 1;
    uint256 internal constant COLLATERAL_ADDRESS = 21;
    uint256 internal constant QUOTE_ADDRESS      = 41;
    uint256 internal constant QUOTE_SCALE        = 61;

    /***********************/
    /*** State Variables ***/
    /***********************/

    InflatorState              internal inflatorState;
    InterestState              internal interestState;
    PoolBalancesState          internal poolBalances;
    ReserveAuctionState        internal reserveAuction;

    AuctionsState              internal auctions;
    mapping(uint256 => Bucket) internal buckets;   // deposit index -> bucket
    DepositsState              internal deposits;
    LoansState                 internal loans;

    uint256 internal poolInitializations;
    mapping(address => mapping(address => mapping(uint256 => uint256))) private _lpTokenAllowances; // owner address -> new owner address -> deposit index -> allowed amount

    /******************/
    /*** Immutables ***/
    /******************/

    function poolType() external pure override returns (uint8) {
        return _getArgUint8(POOL_TYPE);
    }

    function collateralAddress() external pure override returns (address) {
        return _getArgAddress(COLLATERAL_ADDRESS);
    }

    function quoteTokenAddress() external pure override returns (address) {
        return _getArgAddress(QUOTE_ADDRESS);
    }

    function quoteTokenScale() external pure override returns (uint256) {
        return _getArgUint256(QUOTE_SCALE);
    }


    /*********************************/
    /*** Lender External Functions ***/
    /*********************************/

    function addQuoteToken(
        uint256 quoteTokenAmountToAdd_,
        uint256 index_
    ) external override returns (uint256 bucketLPs_) {
        PoolState memory poolState = _accruePoolInterest();

        uint256 newLup;
        (bucketLPs_, newLup) = LenderActions.addQuoteToken(
            buckets,
            deposits,
            quoteTokenAmountToAdd_,
            index_,
            poolState.debt
        );

        // update pool interest rate state
        _updateInterestState(poolState, newLup);

        // move quote token amount from lender to pool
        _transferQuoteTokenFrom(msg.sender, quoteTokenAmountToAdd_);
    }

    function approveLpOwnership(
        address allowedNewOwner_,
        uint256 index_,
        uint256 lpsAmountToApprove_
    ) external {
        _lpTokenAllowances[msg.sender][allowedNewOwner_][index_] = lpsAmountToApprove_;
    }

    function moveQuoteToken(
        uint256 maxAmountToMove_,
        uint256 fromIndex_,
        uint256 toIndex_
    ) external override returns (uint256 fromBucketLPs_, uint256 toBucketLPs_) {
        PoolState memory poolState = _accruePoolInterest();
        _revertIfAuctionDebtLocked(fromIndex_, poolState.inflator);

        uint256 newLup;
        (
            fromBucketLPs_,
            toBucketLPs_,
            newLup
        ) = LenderActions.moveQuoteToken(
            buckets,
            deposits,
            poolState,
            MoveQuoteParams(
                {
                    maxAmountToMove: maxAmountToMove_,
                    fromIndex:       fromIndex_,
                    toIndex:         toIndex_,
                    thresholdPrice:  Loans.getMax(loans).thresholdPrice
                }
            )
        );

        // update pool interest rate state
        _updateInterestState(poolState, newLup);
    }

    function removeQuoteToken(
        uint256 maxAmount_,
        uint256 index_
    ) external override returns (uint256 removedAmount_, uint256 redeemedLPs_) {
        Auctions.revertIfAuctionClearable(auctions, loans);

        PoolState memory poolState = _accruePoolInterest();
        _revertIfAuctionDebtLocked(index_, poolState.inflator);

        uint256 newLup;
        (
            removedAmount_,
            redeemedLPs_,
            newLup
        ) = LenderActions.removeQuoteToken(
            buckets,
            deposits,
            poolState,
            RemoveQuoteParams(
                {
                    maxAmount:      maxAmount_,
                    index:          index_,
                    thresholdPrice: Loans.getMax(loans).thresholdPrice
                }
            )
        );

        // update pool interest rate state
        _updateInterestState(poolState, newLup);

        // move quote token amount from pool to lender
        _transferQuoteToken(msg.sender, removedAmount_);
    }

    function transferLPTokens(
        address owner_,
        address newOwner_,
        uint256[] calldata indexes_
    ) external override {
        LenderActions.transferLPTokens(
            buckets,
            _lpTokenAllowances,
            owner_,
            newOwner_,
            indexes_
        );
    }

    function withdrawBonds() external {
        uint256 claimable = auctions.kickers[msg.sender].claimable;
        auctions.kickers[msg.sender].claimable = 0;
        _transferQuoteToken(msg.sender, claimable);
    }

    /*****************************/
    /*** Liquidation Functions ***/
    /*****************************/

    function bucketTake(
        address borrowerAddress_,
        bool    depositTake_,
        uint256 index_
    ) external override {

        PoolState memory poolState = _accruePoolInterest();
        Borrower  memory borrower = Loans.getBorrowerInfo(loans, borrowerAddress_);

        (
            uint256 collateralAmount,
            uint256 t0RepayAmount
        ) = Auctions.bucketTake(
            auctions,
            deposits,
            buckets,
            BucketTakeParams(
                {
                    borrower:    borrowerAddress_,
                    collateral:  borrower.collateral,
                    t0Debt:      borrower.t0Debt,
                    inflator:    poolState.inflator,
                    depositTake: depositTake_,
                    index:       index_
                }
            )
        );

        _takeFromLoan(poolState, borrower, borrowerAddress_, collateralAmount, t0RepayAmount);
    }

    function settle(
        address borrowerAddress_,
        uint256 maxDepth_
    ) external override {
        PoolState memory poolState = _accruePoolInterest();

        uint256 assets = Maths.wmul(poolBalances.t0Debt, poolState.inflator) + _getPoolQuoteTokenBalance();
        uint256 liabilities = Deposits.treeSum(deposits) + auctions.totalBondEscrowed + reserveAuction.unclaimed;

        Borrower storage borrower = loans.borrowers[borrowerAddress_];

        SettleParams memory params = SettleParams(
            {
                borrower:    borrowerAddress_,
                collateral:  borrower.collateral,
                t0Debt:      borrower.t0Debt,
                reserves:    (assets > liabilities) ? (assets-liabilities) : 0,
                inflator:    poolState.inflator,
                bucketDepth: maxDepth_
            }
        );
        (uint256 remainingCollateral, uint256 t0RemainingDebt) = Auctions.settlePoolDebt(
            auctions,
            buckets,
            deposits,
            params
        );

        // slither-disable-next-line incorrect-equality
        if (t0RemainingDebt == 0) remainingCollateral = _settleAuction(params.borrower, remainingCollateral);

        // update borrower state
        borrower.t0Debt     = t0RemainingDebt;
        borrower.collateral = remainingCollateral;

        // update pool balances state
        uint256 t0SettledDebt        = params.t0Debt - t0RemainingDebt;
        poolBalances.t0Debt          -= t0SettledDebt;
        poolBalances.t0DebtInAuction -= t0SettledDebt;

        uint256 settledCollateral      = params.collateral - remainingCollateral;
        poolBalances.pledgedCollateral -= settledCollateral;

        // update pool interest rate state
        poolState.collateral -= settledCollateral;
        _updateInterestState(poolState, _lup(poolState.debt));
    }

    function kick(address borrowerAddress_) external override {
        PoolState memory poolState = _accruePoolInterest();

        // kick auction
        KickResult memory result = Auctions.kick(
            auctions,
            deposits,
            loans,
            poolState,
            borrowerAddress_
        );

        // update pool balances state
        poolBalances.t0DebtInAuction += result.t0KickedDebt;
        poolBalances.t0Debt          += result.t0KickPenalty;

        // update pool interest rate state
        poolState.debt += result.kickPenalty;
        _updateInterestState(poolState, result.lup);

        if(result.amountToCoverBond != 0) _transferQuoteTokenFrom(msg.sender, result.amountToCoverBond);
    }

    function kickWithDeposit(
        uint256 index_
    ) external override {
        PoolState memory poolState = _accruePoolInterest();

        // kick auctions
        (KickResult memory result) = Auctions.kickWithDeposit(
            auctions,
            deposits,
            buckets,
            loans,
            poolState,
            index_
        );

        // update pool balances state
        poolBalances.t0Debt          += result.t0KickPenalty;
        poolBalances.t0DebtInAuction += result.t0KickedDebt;

        // update pool interest rate state
        poolState.debt += result.kickPenalty;
        _updateInterestState(poolState, result.lup);

        // transfer from kicker to pool the difference to cover bond
        if(result.amountToCoverBond != 0) _transferQuoteTokenFrom(msg.sender, result.amountToCoverBond);
    }

    /*********************************/
    /*** Reserve Auction Functions ***/
    /*********************************/

    function startClaimableReserveAuction() external override {
        uint256 kickerAward = Auctions.startClaimableReserveAuction(
            auctions,
            reserveAuction,
            StartReserveAuctionParams(
                {
                    poolSize:    Deposits.treeSum(deposits),
                    poolDebt:    poolBalances.t0Debt,
                    poolBalance: _getPoolQuoteTokenBalance(),
                    inflator:    inflatorState.inflator
                }
            )
        );
        _transferQuoteToken(msg.sender, kickerAward);
    }

    function takeReserves(uint256 maxAmount_) external override returns (uint256 amount_) {
        uint256 ajnaRequired;
        (amount_, ajnaRequired) = Auctions.takeReserves(
            reserveAuction,
            maxAmount_
        );

        IERC20(_getArgAddress(AJNA_ADDRESS)).safeTransferFrom(msg.sender, address(this), ajnaRequired);
        IERC20Token(_getArgAddress(AJNA_ADDRESS)).burn(ajnaRequired);
        _transferQuoteToken(msg.sender, amount_);
    }

    /***********************************/
    /*** Borrower Internal Functions ***/
    /***********************************/

    function _drawDebt(
        address borrowerAddress_,
        uint256 amountToBorrow_,
        uint256 limitIndex_,
        uint256 collateralToPledge_
    ) internal returns (bool pledge_, bool borrow_, uint256 newLup_) {
        PoolState memory poolState = _accruePoolInterest();
        Borrower  memory borrower = Loans.getBorrowerInfo(loans, borrowerAddress_);

        pledge_ = collateralToPledge_ != 0;
        borrow_ = amountToBorrow_ != 0 || limitIndex_ != 0;
        newLup_ = _lup(poolState.debt);

        uint256 borrowerDebt = Maths.wmul(borrower.t0Debt, poolState.inflator);
        // loan can only be in auction when pledging more collateral
        // if loan in auction and more debt to draw then borrower collateralization check should revert
        bool inAuction;

        // pledge collateral to pool
        if (pledge_) {
            // add new amount of collateral to pledge to borrower balance
            borrower.collateral  += collateralToPledge_;

            uint256 t0DebtInAuctionChange;
            // load loan's auction state
            inAuction = Auctions.isActive(auctions, borrowerAddress_);
            // if loan is auctioned and becomes collateralized by newly pledged collateral then settle auction
            if (
                inAuction
                &&
                _isCollateralized(borrowerDebt, borrower.collateral, newLup_, poolState.poolType)
            )
            {
                // borrower becomes collateralized, remove debt from pool accumulator and settle auction
                t0DebtInAuctionChange = borrower.t0Debt;
                borrower.collateral   = _settleAuction(borrowerAddress_, borrower.collateral);
                // auction was settled, reset inAuction flag
                inAuction = false;
            }

            // add new amount of collateral to pledge to pool balance
            poolState.collateral += collateralToPledge_;

            // update pool balances state
            if (t0DebtInAuctionChange != 0) {
                poolBalances.t0DebtInAuction -= t0DebtInAuctionChange;
            }
            poolBalances.pledgedCollateral += collateralToPledge_;
        }

        // borrow against pledged collateral
        // check both values to enable an intentional 0 borrow loan call to update borrower's loan state
        if (borrow_) {
            // only intended recipient can borrow quote
            if (borrowerAddress_ != msg.sender) revert BorrowerNotSender();

            // add origination fee to the amount to borrow and add to borrower's debt
            uint256 debtChange = Maths.wmul(amountToBorrow_, _feeRate(poolState.rate) + Maths.WAD);
            borrowerDebt   += debtChange;

            // check that drawing debt doesn't leave borrower debt under min debt amount
            _revertOnMinDebt(poolState.debt, borrowerDebt);

            // add debt change to pool's debt
            poolState.debt += debtChange;
            // determine new lup index and revert if borrow happens at a price higher than the specified limit (lower index than lup index)
            uint256 lupId = _lupIndex(poolState.debt);
            if (lupId > limitIndex_) revert LimitIndexReached();

            // calculate new lup and check borrow action won't push borrower into a state of under-collateralization
            // this check also covers the scenario when loan is already auctioned
            newLup_ = _priceAt(lupId);
            if (
                !_isCollateralized(borrowerDebt, borrower.collateral, newLup_, poolState.poolType)
            ) revert BorrowerUnderCollateralized();

            uint256 t0DebtChange = Maths.wdiv(debtChange, poolState.inflator);
            borrower.t0Debt += t0DebtChange;

            // update pool balances state
            poolBalances.t0Debt += t0DebtChange;
        }

        // update loan state
        Loans.update(
            loans,
            auctions,
            deposits,
            borrower,
            borrowerAddress_,
            borrowerDebt,
            poolState.rate,
            newLup_,
            inAuction,
            true
        );

        // update pool interest rate state
        _updateInterestState(poolState, newLup_);
    }

    function _repayDebt(
        address borrowerAddress_,
        uint256 maxQuoteTokenAmountToRepay_,
        uint256 collateralAmountToPull_
    ) internal returns (uint256 quoteTokenToRepay_, uint256 newLup_) {
        PoolState memory poolState = _accruePoolInterest();
        Borrower  memory borrower = Loans.getBorrowerInfo(loans, borrowerAddress_);

        bool repay = maxQuoteTokenAmountToRepay_ != 0;
        bool pull  = collateralAmountToPull_ != 0;

        uint256 borrowerDebt = Maths.wmul(borrower.t0Debt, poolState.inflator);
        // loan can only be in auction when repaying debt
        // if loan in auction and pull collateral attempted then borrower collateralization check should revert
        bool inAuction;

        if (repay) {
            if (borrower.t0Debt == 0) revert NoDebt();

            uint256 t0RepaidDebt = Maths.min(
                borrower.t0Debt,
                Maths.wdiv(maxQuoteTokenAmountToRepay_, poolState.inflator)
            );
            quoteTokenToRepay_ = Maths.wmul(t0RepaidDebt, poolState.inflator);
            poolState.debt     -= quoteTokenToRepay_;
            borrowerDebt       -= quoteTokenToRepay_;

            // check that paying the loan doesn't leave borrower debt under min debt amount
            _revertOnMinDebt(poolState.debt, borrowerDebt);

            newLup_ = _lup(poolState.debt);
            inAuction = Auctions.isActive(auctions, borrowerAddress_);

            uint256 t0DebtInAuctionChange;
            if (inAuction) {
                if (_isCollateralized(borrowerDebt, borrower.collateral, newLup_, poolState.poolType)) {
                    // borrower becomes re-collateralized
                    // remove entire borrower debt from pool auctions debt accumulator
                    t0DebtInAuctionChange = borrower.t0Debt;
                    // settle auction and update borrower's collateral with value after settlement
                    borrower.collateral   = _settleAuction(borrowerAddress_, borrower.collateral);
                    inAuction = false;
                } else {
                    // partial repay, remove only the paid debt from pool auctions debt accumulator
                    t0DebtInAuctionChange = t0RepaidDebt;
                }
            }

            borrower.t0Debt -= t0RepaidDebt;

            // update pool balances state
            poolBalances.t0Debt -= t0RepaidDebt;
            if (t0DebtInAuctionChange != 0) {
                poolBalances.t0DebtInAuction -= t0DebtInAuctionChange;
            }
        }

        if (pull) {
            // only intended recipient can pull collateral
            if (borrowerAddress_ != msg.sender) revert BorrowerNotSender();

            // calculate LUP only if it wasn't calculated by repay action
            if (!repay) newLup_ = _lup(poolState.debt);

            uint256 encumberedCollateral = borrower.t0Debt != 0 ? Maths.wdiv(borrowerDebt, newLup_) : 0;
            if (borrower.collateral - encumberedCollateral < collateralAmountToPull_) revert InsufficientCollateral();

            borrower.collateral  -= collateralAmountToPull_;
            poolState.collateral -= collateralAmountToPull_;

            // update pool balances state
            poolBalances.pledgedCollateral = poolState.collateral;
        }

        // update loan state
        Loans.update(
            loans,
            auctions,
            deposits,
            borrower,
            borrowerAddress_,
            borrowerDebt,
            poolState.rate,
            newLup_,
            inAuction,
            pull // stamp borrower t0Np only for pull collateral action
        );

        // update pool interest rate state
        _updateInterestState(poolState, newLup_);
    }

    /***********************************/
    /*** Auctions Internal Functions ***/
    /***********************************/

    /**
     *  @notice Updates loan with result of a take action. Settles auction if borrower becomes collateralized.
     *  @notice Saves loan state, t0 debt and collateral pledged pool accumulators and updates pool interest state.
     *  @param  poolState_        Current state of the pool.
     *  @param  borrower_         Details of the borrower whose loan is taken.
     *  @param  borrowerAddress_  Address of the borrower whose loan is taken.
     *  @param  collateralAmount_ Collateral amount that was taken from borrower.
     *  @param  t0RepaidDebt_     Amount of t0 debt repaid by take action.
    */
    function _takeFromLoan(
        PoolState memory poolState_,
        Borrower memory borrower_,
        address borrowerAddress_,
        uint256 collateralAmount_,
        uint256 t0RepaidDebt_
    ) internal {

        borrower_.collateral  -= collateralAmount_; // collateral is removed from the loan
        poolState_.collateral -= collateralAmount_; // collateral is removed from pledged collateral accumulator

        uint256 borrowerDebt = Maths.wmul(borrower_.t0Debt, poolState_.inflator);
        {
            uint256 repaidDebt = Maths.wmul(t0RepaidDebt_, poolState_.inflator);
            borrowerDebt       -= repaidDebt;
            poolState_.debt    -= repaidDebt;
        }

        // check that taking from loan doesn't leave borrower debt under min debt amount
        _revertOnMinDebt(poolState_.debt, borrowerDebt);

        uint256 newLup = _lup(poolState_.debt);
        bool inAuction = true;

        uint256 t0DebtInAuctionChange;
        if (_isCollateralized(borrowerDebt, borrower_.collateral, newLup, poolState_.poolType)) {
            // borrower becomes re-collateralized
            // remove entire borrower debt from pool auctions debt accumulator
            t0DebtInAuctionChange = borrower_.t0Debt;
            // settle auction and update borrower's collateral with value after settlement
            borrower_.collateral = _settleAuction(borrowerAddress_, borrower_.collateral);
            inAuction = false;
        } else {
            // partial repay, remove only the paid debt from pool auctions debt accumulator
            t0DebtInAuctionChange = t0RepaidDebt_;
        }
        
        borrower_.t0Debt -= t0RepaidDebt_;

        // update loan state, no need to stamp borrower t0Np in take loan action
        Loans.update(
            loans,
            auctions,
            deposits,
            borrower_,
            borrowerAddress_,
            borrowerDebt,
            poolState_.rate,
            newLup,
            inAuction,
            false
        );

        // update pool balances state
        poolBalances.t0Debt            -= t0RepaidDebt_;
        poolBalances.t0DebtInAuction   -= t0DebtInAuctionChange;
        poolBalances.pledgedCollateral = poolState_.collateral;

        // update pool interest rate state
        _updateInterestState(poolState_, newLup);
    }

    /******************************/
    /*** Pool Virtual Functions ***/
    /******************************/

    /**
     *  @notice Settle an auction when it exits the auction queue (implemented by each pool accordingly).
     *  @param  borrowerAddress_    Address of the borrower that exits auction.
     *  @param  borrowerCollateral_ Borrower collateral amount before auction exit.
     *  @return Remaining borrower collateral after auction exit.
     */
    function _settleAuction(
        address borrowerAddress_,
        uint256 borrowerCollateral_
    ) internal virtual returns (uint256);

    /*****************************/
    /*** Pool Helper Functions ***/
    /*****************************/

    function _accruePoolInterest() internal returns (PoolState memory poolState_) {
        uint256 t0Debt        = poolBalances.t0Debt;
        poolState_.collateral = poolBalances.pledgedCollateral;
        poolState_.inflator   = inflatorState.inflator;
        poolState_.rate       = interestState.interestRate;
        poolState_.poolType   = _getArgUint8(POOL_TYPE);

        if (t0Debt != 0) {
            // Calculate prior pool debt
            poolState_.debt = Maths.wmul(t0Debt, poolState_.inflator);

            uint256 elapsed = block.timestamp - inflatorState.inflatorUpdate;
            poolState_.isNewInterestAccrued = elapsed != 0;

            if (poolState_.isNewInterestAccrued) {
                poolState_.inflator = PoolCommons.accrueInterest(
                    deposits,
                    poolState_,
                    Loans.getMax(loans).thresholdPrice,
                    elapsed
                );
                // After debt owed to lenders has accrued, calculate current debt owed by borrowers
                poolState_.debt = Maths.wmul(t0Debt, poolState_.inflator);
            }
        }
    }

    function _updateInterestState(PoolState memory poolState_, uint256 lup_) internal {
        if (block.timestamp - interestState.interestRateUpdate > 12 hours) {
            PoolCommons.updateInterestRate(interestState, deposits, poolState_, lup_);
        }

        // update pool inflator
        if (poolState_.isNewInterestAccrued) {
            inflatorState.inflator       = uint208(poolState_.inflator);
            inflatorState.inflatorUpdate = uint48(block.timestamp);
        // slither-disable-next-line incorrect-equality
        } else if (poolState_.debt == 0) {
            inflatorState.inflator       = uint208(Maths.WAD);
            inflatorState.inflatorUpdate = uint48(block.timestamp);
        }
    }

    /**
     *  @notice Called by LPB removal functions assess whether or not LPB is locked.
     *  @param  index_    The deposit index from which LPB is attempting to be removed.
     *  @param  inflator_ The pool inflator used to properly assess t0 debt in auctions.
     */
    function _revertIfAuctionDebtLocked(
        uint256 index_,
        uint256 inflator_
    ) internal view {
        uint256 t0AuctionDebt = poolBalances.t0DebtInAuction;
        if (t0AuctionDebt != 0 ) {
            // deposit in buckets within liquidation debt from the top-of-book down are frozen.
            if (index_ <= Deposits.findIndexOfSum(deposits, Maths.wmul(t0AuctionDebt, inflator_))) revert RemoveDepositLockedByAuctionDebt();
        } 
    }

    function _revertOnMinDebt(uint256 poolDebt_, uint256 borrowerDebt_) internal view {
        if (borrowerDebt_ != 0) {
            uint256 loansCount = Loans.noOfLoans(loans);
            if (
                loansCount >= 10
                &&
                (borrowerDebt_ < _minDebtAmount(poolDebt_, loansCount))
            ) revert AmountLTMinDebt();
        }
    }

    function _transferQuoteTokenFrom(address from_, uint256 amount_) internal {
        IERC20(_getArgAddress(QUOTE_ADDRESS)).safeTransferFrom(from_, address(this), amount_ / _getArgUint256(QUOTE_SCALE));
    }

    function _transferQuoteToken(address to_, uint256 amount_) internal {
        IERC20(_getArgAddress(QUOTE_ADDRESS)).safeTransfer(to_, amount_ / _getArgUint256(QUOTE_SCALE));
    }

    function _getPoolQuoteTokenBalance() internal view returns (uint256) {
        return IERC20(_getArgAddress(QUOTE_ADDRESS)).balanceOf(address(this));
    }

    function _lupIndex(uint256 debt_) internal view returns (uint256) {
        return Deposits.findIndexOfSum(deposits, debt_);
    }

    function _lup(uint256 debt_) internal view returns (uint256) {
        return _priceAt(_lupIndex(debt_));
    }

    /**************************/
    /*** External Functions ***/
    /**************************/

    function auctionInfo(
        address borrower_
    ) external 
    view override returns (
        address kicker,
        uint256 bondFactor,
        uint256 bondSize,
        uint256 kickTime,
        uint256 kickMomp,
        uint256 neutralPrice,
        address head,
        address next,
        address prev
    ) {
        Liquidation memory liquidation = auctions.liquidations[borrower_];
        return (
            liquidation.kicker,
            liquidation.bondFactor,
            liquidation.bondSize,
            liquidation.kickTime,
            liquidation.kickMomp,
            liquidation.neutralPrice,
            auctions.head,
            liquidation.next,
            liquidation.prev
        );
    }

    function borrowerInfo(
        address borrower_
    ) external view override returns (uint256, uint256, uint256) {
        return (
            loans.borrowers[borrower_].t0Debt,
            loans.borrowers[borrower_].collateral,
            loans.borrowers[borrower_].t0Np
        );
    }

    function bucketInfo(
        uint256 index_
    ) external view override returns (uint256, uint256, uint256, uint256, uint256) {
        return (
            buckets[index_].lps,
            buckets[index_].collateral,
            buckets[index_].bankruptcyTime,
            Deposits.valueAt(deposits, index_),
            Deposits.scale(deposits, index_)
        );
    }

    function debtInfo() external view returns (uint256, uint256, uint256) {
        uint256 pendingInflator = PoolCommons.pendingInflator(
            inflatorState.inflator,
            inflatorState.inflatorUpdate,
            interestState.interestRate
        );
        return (
            Maths.wmul(poolBalances.t0Debt, pendingInflator),
            Maths.wmul(poolBalances.t0Debt, inflatorState.inflator),
            Maths.wmul(poolBalances.t0DebtInAuction, inflatorState.inflator)
        );
    }

    function depositIndex(uint256 debt_) external view override returns (uint256) {
        return Deposits.findIndexOfSum(deposits, debt_);
    }

    function depositSize() external view override returns (uint256) {
        return Deposits.treeSum(deposits);
    }

    function depositUtilization(
        uint256 debt_,
        uint256 collateral_
    ) external view override returns (uint256) {
        return PoolCommons.utilization(deposits, debt_, collateral_);
    }

    function emasInfo() external view override returns (uint256, uint256) {
        return (
            interestState.debtEma,
            interestState.lupColEma
        );
    }

    function inflatorInfo() external view override returns (uint256, uint256) {
        return (
            inflatorState.inflator,
            inflatorState.inflatorUpdate
        );
    }

    function interestRateInfo() external view returns (uint256, uint256) {
        return (
            interestState.interestRate,
            interestState.interestRateUpdate
        );
    }

    function kickerInfo(
        address kicker_
    ) external view override returns (uint256, uint256) {
        return(
            auctions.kickers[kicker_].claimable,
            auctions.kickers[kicker_].locked
        );
    }

    function lenderInfo(
        uint256 index_,
        address lender_
    ) external view override returns (uint256 lpBalance_, uint256 depositTime_) {
        depositTime_ = buckets[index_].lenders[lender_].depositTime;
        if (buckets[index_].bankruptcyTime < depositTime_) lpBalance_ = buckets[index_].lenders[lender_].lps;
    }

    function loanInfo(
        uint256 loanId_
    ) external view override returns (address, uint256) {
        return (
            Loans.getByIndex(loans, loanId_).borrower,
            Loans.getByIndex(loans, loanId_).thresholdPrice
        );
    }

    function loansInfo() external view override returns (address, uint256, uint256) {
        return (
            Loans.getMax(loans).borrower,
            Maths.wmul(Loans.getMax(loans).thresholdPrice, inflatorState.inflator),
            Loans.noOfLoans(loans)
        );
    }

    function pledgedCollateral() external view override returns (uint256) {
        return poolBalances.pledgedCollateral;
    }

    function reservesInfo() external view override returns (uint256, uint256, uint256) {
        return (
            auctions.totalBondEscrowed,
            reserveAuction.unclaimed,
            reserveAuction.kicked
        );
    }
}
