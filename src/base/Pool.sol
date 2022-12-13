// SPDX-License-Identifier: MIT

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
    using Auctions  for Auctions.Data;
    using Buckets   for mapping(uint256 => Buckets.Bucket);
    using Deposits  for Deposits.Data;
    using Loans     for Loans.Data;
    using SafeERC20 for IERC20;

    /***********************/
    /*** State Variables ***/
    /***********************/

    uint208 internal inflatorSnapshot;           // [WAD]
    uint48  internal lastInflatorSnapshotUpdate; // [SEC]

    InterestParams       internal interestParams;
    ReserveAuctionParams internal reserveAuction;

    uint256 public override pledgedCollateral;  // [WAD]

    uint256 internal t0DebtInAuction; // Total debt in auction used to restrict LPB holder from withdrawing [WAD]
    uint256 internal t0poolDebt;      // Pool debt as if the whole amount was incurred upon the first loan. [WAD]

    uint256 internal poolInitializations;

    mapping(address => mapping(address => mapping(uint256 => uint256))) private _lpTokenAllowances; // owner address -> new owner address -> deposit index -> allowed amount

    Auctions.Data                      internal auctions;
    mapping(uint256 => Buckets.Bucket) internal buckets;   // deposit index -> bucket
    Deposits.Data                      internal deposits;
    Loans.Data                         internal loans;

    struct InterestParams {
        uint208 interestRate;       // [WAD]
        uint48  interestRateUpdate; // [SEC]
        uint256 debtEma;            // [WAD]
        uint256 lupColEma;          // [WAD]
    }

    struct ReserveAuctionParams {
        uint256 kicked;    // Time a Claimable Reserve Auction was last kicked.
        uint256 unclaimed; // Amount of claimable reserves which has not been taken in the Claimable Reserve Auction.
    }

    struct PoolState {
        uint256 accruedDebt;
        uint256 collateral;
        bool    isNewInterestAccrued;
        uint256 rate;
        uint256 inflator;
    }

    /******************/
    /*** Immutables ***/
    /******************/

    function collateralAddress() external pure override returns (address) {
        return _getArgAddress(0);
    }

    function quoteTokenAddress() external pure override returns (address) {
        return _getArgAddress(20);
    }

    function quoteTokenScale() external pure override returns (uint256) {
        return _getArgUint256(40);
    }


    /*********************************/
    /*** Lender External Functions ***/
    /*********************************/

    function addQuoteToken(
        uint256 quoteTokenAmountToAdd_,
        uint256 index_
    ) external override returns (uint256 bucketLPs_) {
        PoolState memory poolState = _accruePoolInterest();

        bucketLPs_ = LenderActions.addQuoteToken(
            buckets,
            deposits,
            quoteTokenAmountToAdd_,
            index_
        );

        uint256 newLup = _lup(poolState.accruedDebt);
        _updateInterestParams(poolState, newLup);

        emit AddQuoteToken(msg.sender, index_, quoteTokenAmountToAdd_, newLup);
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
            LenderActions.MoveQuoteParams(
                {
                    maxAmountToMove: maxAmountToMove_,
                    fromIndex:       fromIndex_,
                    toIndex:         toIndex_,
                    ptp:             _ptp(poolState.accruedDebt, poolState.collateral),
                    htp:             _htp(poolState.inflator),
                    poolDebt:        poolState.accruedDebt,
                    rate:            poolState.rate
                }
            )
        );

        _updateInterestParams(poolState, newLup);
    }

    function removeQuoteToken(
        uint256 maxAmount_,
        uint256 index_
    ) external override returns (uint256 removedAmount_, uint256 redeemedLPs_) {
        auctions.revertIfAuctionClearable(loans);

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
            LenderActions.RemoveQuoteParams(
                {
                    maxAmount: maxAmount_,
                    index:     index_,
                    ptp:       _ptp(poolState.accruedDebt, poolState.collateral),
                    htp:       _htp(poolState.inflator),
                    poolDebt:  poolState.accruedDebt,
                    rate:      poolState.rate
                }
            )
        );

        _updateInterestParams(poolState, newLup);

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
        Loans.Borrower memory borrower = loans.getBorrowerInfo(borrowerAddress_);

        (
            uint256 collateralAmount,
            uint256 t0repayAmount
        ) = Auctions.bucketTake(
            auctions,
            deposits,
            buckets,
            Auctions.BucketTakeParams(
                {
                    borrower:    borrowerAddress_,
                    collateral:  borrower.collateral,
                    t0debt:      borrower.t0debt,
                    inflator:    poolState.inflator,
                    depositTake: depositTake_,
                    index:       index_
                }
            )
        );

        borrower.collateral  -= collateralAmount; // collateral is removed from the loan
        poolState.collateral -= collateralAmount; // collateral is removed from pledged collateral accumulator

        _payLoan(t0repayAmount, poolState, borrowerAddress_, borrower);
        pledgedCollateral = poolState.collateral;

    }

    function settle(
        address borrowerAddress_,
        uint256 maxDepth_
    ) external override {
        PoolState memory poolState = _accruePoolInterest();
        Loans.Borrower storage borrower = loans.borrowers[borrowerAddress_];

        Auctions.SettleParams memory params = Auctions.SettleParams(
            {
                borrower:    borrowerAddress_,
                collateral:  borrower.collateral,
                t0debt:      borrower.t0debt,
                reserves:    Maths.wmul(t0poolDebt, poolState.inflator) 
                                + _getPoolQuoteTokenBalance()
                                - deposits.treeSum()
                                - auctions.totalBondEscrowed
                                - reserveAuction.unclaimed,
                inflator:    poolState.inflator,
                bucketDepth: maxDepth_
            }
        );
        (uint256 remainingCollateral, uint256 remainingt0Debt) = Auctions.settlePoolDebt(
            auctions,
            buckets,
            deposits,
            params
        );
        // slither-disable-next-line incorrect-equality
        if (remainingt0Debt == 0) remainingCollateral = _settleAuction(params.borrower, remainingCollateral);

        uint256 t0settledDebt = params.t0debt - remainingt0Debt;
        t0poolDebt      -= t0settledDebt;
        t0DebtInAuction -= t0settledDebt;

        poolState.collateral -= params.collateral - remainingCollateral;

        borrower.t0debt     = remainingt0Debt;
        borrower.collateral = remainingCollateral;

        pledgedCollateral = poolState.collateral;
        _updateInterestParams(poolState, _lup(poolState.accruedDebt));

        emit Settle(params.borrower, t0settledDebt);
    }

    function kick(address borrowerAddress_) external override {
        auctions.revertIfActive(borrowerAddress_);

        PoolState memory poolState = _accruePoolInterest();
        Loans.Borrower storage borrower = loans.borrowers[borrowerAddress_];
        uint256 borrowerT0debt = borrower.t0debt;

        Auctions.KickParams memory params = Auctions.KickParams(
            {
                borrower:     borrowerAddress_,
                debt:         Maths.wmul(borrowerT0debt, poolState.inflator),
                collateral:   borrower.collateral,
                momp:         _momp(poolState.accruedDebt, loans.noOfLoans()),
                neutralPrice: Maths.wmul(borrower.t0Np, poolState.inflator),
                rate:         poolState.rate
            }
        );

        uint256 lup = _lup(poolState.accruedDebt);
        if (
            _isCollateralized(params.debt , params.collateral, lup)
        ) revert BorrowerOk();

        // kick auction
        (uint256 kickAuctionAmount, uint256 kickPenalty) = Auctions.kick(
            auctions,
            params
        );

        // remove kicked loan from heap
        loans.remove(params.borrower, loans.indices[params.borrower]);

        poolState.accruedDebt += kickPenalty;
        // convert kick penalty to t0 amount, update borrower t0 debt and pool t0 debt accumulators
        kickPenalty     =  Maths.wdiv(kickPenalty, poolState.inflator);
        borrowerT0debt  += kickPenalty;
        borrower.t0debt = borrowerT0debt;
        t0DebtInAuction += borrowerT0debt;
        t0poolDebt      += kickPenalty;

        _updateInterestParams(poolState, lup);

        if(kickAuctionAmount != 0) _transferQuoteTokenFrom(msg.sender, kickAuctionAmount);
    }

    /*********************************/
    /*** Reserve Auction Functions ***/
    /*********************************/

    function startClaimableReserveAuction() external override {
        uint256 kickerAward = Auctions.startClaimableReserveAuction(
            auctions,
            reserveAuction,
            Auctions.StartReserveAuctionParams(
            {
                poolSize:    deposits.treeSum(),
                poolDebt:    t0poolDebt,
                poolBalance: _getPoolQuoteTokenBalance(),
                inflator:    inflatorSnapshot
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

        IERC20Token ajnaToken = IERC20Token(_getArgAddress(72));
        if (!ajnaToken.transferFrom(msg.sender, address(this), ajnaRequired)) revert ERC20TransferFailed();
        ajnaToken.burn(ajnaRequired);
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
        Loans.Borrower memory borrower = loans.getBorrowerInfo(borrowerAddress_);

        pledge_ = collateralToPledge_ != 0;
        borrow_ = amountToBorrow_ != 0 || limitIndex_ != 0;
        newLup_ = _lup(poolState.accruedDebt);

        uint256 borrowerDebt = Maths.wmul(borrower.t0debt, poolState.inflator);

        // pledge collateral to pool
        if (pledge_) {
            borrower.collateral  += collateralToPledge_;
            poolState.collateral += collateralToPledge_;

            if (
                auctions.isActive(borrowerAddress_)
                &&
                _isCollateralized(borrowerDebt, borrower.collateral, newLup_)
            )
            {
                // borrower becomes collateralized, remove debt from pool accumulator and settle auction
                t0DebtInAuction     -= borrower.t0debt;
                borrower.collateral = _settleAuction(borrowerAddress_, borrower.collateral);
            }
            pledgedCollateral += collateralToPledge_;
        }

        // borrow against pledged collateral
        // check both values to enable an intentional 0 borrow loan call to update borrower's loan state
        if (borrow_) {
            // only intended recipient can borrow quote
            if (borrowerAddress_ != msg.sender) revert BorrowerNotSender();
            // if borrower auctioned then it cannot draw more debt
            auctions.revertIfActive(msg.sender);

            // add origination fee to the amount to borrow and add to borrower's debt
            uint256 debtChange = Maths.wmul(amountToBorrow_, _feeRate(interestParams.interestRate) + Maths.WAD);
            borrowerDebt += debtChange;
            _checkMinDebt(poolState.accruedDebt, borrowerDebt);

            // determine new lup index and revert if borrow happens at a price higher than the specified limit (lower index than lup index)
            uint256 lupId = _lupIndex(poolState.accruedDebt + amountToBorrow_);
            if (lupId > limitIndex_) revert LimitIndexReached();

            // calculate new lup and check borrow action won't push borrower into a state of under-collateralization
            newLup_ = _priceAt(lupId);
            if (
                !_isCollateralized(borrowerDebt, borrower.collateral, newLup_)
            ) revert BorrowerUnderCollateralized();

            // check borrow won't push pool into a state of under-collateralization
            poolState.accruedDebt += debtChange;
            if (
                !_isCollateralized(poolState.accruedDebt, poolState.collateral, newLup_)
            ) revert PoolUnderCollateralized();

            uint256 t0DebtChange = Maths.wdiv(debtChange, poolState.inflator);
            borrower.t0debt += t0DebtChange;
            t0poolDebt      += t0DebtChange;
        }

        // update loan state
        uint256 loanId = loans.indices[borrowerAddress_];
        // stamp borrower t0Np
        borrower.t0Np = _t0Np(
            loanId,
            borrower.t0debt,
            borrower.collateral,
            borrowerDebt,
            poolState.inflator,
            poolState.rate,
            newLup_
        );
        loans.update(borrowerAddress_, borrower, loanId);

        // update pool global interest rate state
        _updateInterestParams(poolState, newLup_);
    }

    function _repayDebt(
        address borrowerAddress_,
        uint256 maxQuoteTokenAmountToRepay_,
        uint256 collateralAmountToPull_
    ) internal returns (uint256 quoteTokenToRepay_, uint256 newLup_) {
        PoolState memory poolState = _accruePoolInterest();
        Loans.Borrower memory borrower = loans.getBorrowerInfo(borrowerAddress_);

        newLup_ = _lup(poolState.accruedDebt);

        if (maxQuoteTokenAmountToRepay_ != 0) {
            if (borrower.t0debt == 0) revert NoDebt();

            uint256 t0repaidDebt = Maths.min(
                borrower.t0debt,
                Maths.wdiv(maxQuoteTokenAmountToRepay_, poolState.inflator)
            );
            (quoteTokenToRepay_, newLup_) = _payLoan(t0repaidDebt, poolState, borrowerAddress_, borrower);
        }

        if (collateralAmountToPull_ != 0) {
            // only intended recipient can pull collateral
            if (borrowerAddress_ != msg.sender) revert BorrowerNotSender();

            uint256 borrowerDebt = Maths.wmul(borrower.t0debt, poolState.inflator);

            uint256 encumberedCollateral = borrower.t0debt != 0 ? Maths.wdiv(borrowerDebt, newLup_) : 0;
            if (borrower.collateral - encumberedCollateral < collateralAmountToPull_) revert InsufficientCollateral();

            borrower.collateral  -= collateralAmountToPull_;
            poolState.collateral -= collateralAmountToPull_;

            // update loan state
            uint256 loanId = loans.indices[borrowerAddress_];
            // stamp borrower t0Np
            borrower.t0Np = _t0Np(
                loanId,
                borrower.t0debt,
                borrower.collateral,
                borrowerDebt,
                poolState.inflator,
                poolState.rate,
                newLup_
            );
            loans.update(msg.sender, borrower, loanId);

            pledgedCollateral = poolState.collateral;
            _updateInterestParams(poolState, newLup_);
        }
    }

    function _payLoan(
        uint256 t0repaidDebt_,
        PoolState memory poolState_,
        address borrowerAddress_,
        Loans.Borrower memory borrower_
    ) internal returns(
        uint256 quoteTokenAmountToRepay_, 
        uint256 newLup_
    ) {
        quoteTokenAmountToRepay_ = Maths.wmul(t0repaidDebt_, poolState_.inflator);
        uint256 borrowerDebt     = Maths.wmul(borrower_.t0debt, poolState_.inflator) - quoteTokenAmountToRepay_;
        poolState_.accruedDebt   -= quoteTokenAmountToRepay_;

        // check that paying the loan doesn't leave borrower debt under min debt amount
        _checkMinDebt(poolState_.accruedDebt, borrowerDebt);

        newLup_ = _lup(poolState_.accruedDebt);

        if (auctions.isActive(borrowerAddress_)) {
            if (_isCollateralized(borrowerDebt, borrower_.collateral, newLup_)) {
                // borrower becomes re-collateralized
                // remove entire borrower debt from pool auctions debt accumulator
                t0DebtInAuction -= borrower_.t0debt;
                // settle auction and update borrower's collateral with value after settlement
                borrower_.collateral = _settleAuction(borrowerAddress_, borrower_.collateral);
            } else {
                // partial repay, remove only the paid debt from pool auctions debt accumulator
                t0DebtInAuction -= t0repaidDebt_;
            }
        }
        
        borrower_.t0debt -= t0repaidDebt_;

        // update loan state, no need to stamp borrower t0Np in repay action
        uint256 loanId = loans.indices[borrowerAddress_];
        loans.update(borrowerAddress_, borrower_, loanId);

        t0poolDebt -= t0repaidDebt_;
        _updateInterestParams(poolState_, newLup_);
    }

    function _checkMinDebt(uint256 accruedDebt_,  uint256 borrowerDebt_) internal view {
        if (borrowerDebt_ != 0) {
            uint256 loansCount = loans.noOfLoans();
            if (
                loansCount >= 10
                &&
                (borrowerDebt_ < _minDebtAmount(accruedDebt_, loansCount))
            ) revert AmountLTMinDebt();
        }
    }

    /******************************/
    /*** Pool Virtual Functions ***/
    /******************************/

    /**
     *  @notice Collateralization calculation (implemented by each pool accordingly).
     *  @param debt_       Debt to calculate collateralization for.
     *  @param collateral_ Collateral to calculate collateralization for.
     *  @param price_      Price to calculate collateralization for.
     *  @return True if collateralization calculated is equal or greater than 1.
     */
    function _isCollateralized(
        uint256 debt_,
        uint256 collateral_,
        uint256 price_
    ) internal virtual returns (bool);

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
        uint256 t0Debt        = t0poolDebt;
        poolState_.collateral = pledgedCollateral;
        poolState_.inflator   = inflatorSnapshot;
        poolState_.rate       = interestParams.interestRate;

        if (t0Debt != 0) {
            // Calculate prior pool debt
            poolState_.accruedDebt = Maths.wmul(t0Debt, poolState_.inflator);

            uint256 elapsed = block.timestamp - lastInflatorSnapshotUpdate;
            poolState_.isNewInterestAccrued = elapsed != 0;

            if (poolState_.isNewInterestAccrued) {
                poolState_.inflator = PoolCommons.accrueInterest(
                    deposits,
                    poolState_.accruedDebt,
                    poolState_.collateral,
                    loans.getMax().thresholdPrice,
                    poolState_.inflator,
                    poolState_.rate,
                    elapsed
                );
                // After debt owed to lenders has accrued, calculate current debt owed by borrowers
                poolState_.accruedDebt = Maths.wmul(t0Debt, poolState_.inflator);
            }
        }
    }

    function _updateInterestParams(PoolState memory poolState_, uint256 lup_) internal {
        if (block.timestamp - interestParams.interestRateUpdate > 12 hours) {
            PoolCommons.updateInterestRate(interestParams, deposits, poolState_, lup_);
        }

        // update pool inflator
        if (poolState_.isNewInterestAccrued) {
            inflatorSnapshot           = uint208(poolState_.inflator);
            lastInflatorSnapshotUpdate = uint48(block.timestamp);
        // slither-disable-next-line incorrect-equality
        } else if (poolState_.accruedDebt == 0) {
            inflatorSnapshot           = uint208(Maths.WAD);
            lastInflatorSnapshotUpdate = uint48(block.timestamp);
        }
    }

    function _transferQuoteTokenFrom(address from_, uint256 amount_) internal {
        IERC20(_getArgAddress(20)).safeTransferFrom(from_, address(this), amount_ / _getArgUint256(40));
    }

    function _transferQuoteToken(address to_, uint256 amount_) internal {
        IERC20(_getArgAddress(20)).safeTransfer(to_, amount_ / _getArgUint256(40));
    }

    function _getPoolQuoteTokenBalance() internal view returns (uint256) {
        return IERC20(_getArgAddress(20)).balanceOf(address(this));
    }

    function _htp(uint256 inflator_) internal view returns (uint256) {
        return Maths.wmul(loans.getMax().thresholdPrice, inflator_);
    }

    function _momp(uint256 debt_, uint256 noOfLoans_) internal view returns (uint256) {
        return noOfLoans_ != 0 ? _priceAt(deposits.findIndexOfSum(Maths.wdiv(debt_, noOfLoans_ * 1e18))) : 0;
    }

    function _t0Np (
        uint256 loanId_,
        uint256 t0Debt_,
        uint256 collateral_,
        uint256 debt_,
        uint256 inflator_,
        uint256 rate_,
        uint256 lup_
    ) internal view returns (uint256 t0Np_) {
        if (t0Debt_ != 0 && collateral_ != 0) {
            // if loan id is 0 then it is a new loan, count it as part of total loans in pool
            uint256 noOfLoans = loanId_ != 0 ? loans.loans.length - 1 : loans.loans.length;
            uint256 thresholdPrice = debt_ * Maths.WAD / collateral_;
            uint256 curMomp = _momp(t0Debt_, noOfLoans);
            t0Np_ = (1e18 + rate_) * curMomp * thresholdPrice / lup_ / inflator_;
        }
    }

    function _lupIndex(uint256 debt_) internal view returns (uint256) {
        return deposits.findIndexOfSum(debt_);
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
        uint256 neutralPrice
    ) {
        return (
            auctions.liquidations[borrower_].kicker,
            auctions.liquidations[borrower_].bondFactor,
            auctions.liquidations[borrower_].bondSize,
            auctions.liquidations[borrower_].kickTime,
            auctions.liquidations[borrower_].kickMomp,
            auctions.liquidations[borrower_].neutralPrice
        );
    }

    function borrowerInfo(
        address borrower_
    ) external view override returns (uint256, uint256, uint256) {
        return (
            loans.borrowers[borrower_].t0debt,
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
            deposits.valueAt(index_),
            deposits.scale(index_)
        );
    }

    function debtInfo() external view returns (uint256, uint256, uint256) {
        uint256 pendingInflator = PoolCommons.pendingInflator(
            inflatorSnapshot,
            lastInflatorSnapshotUpdate,
            interestParams.interestRate
        );
        return (
            Maths.wmul(t0poolDebt, pendingInflator),
            Maths.wmul(t0poolDebt, inflatorSnapshot),
            Maths.wmul(t0DebtInAuction, inflatorSnapshot)
        );
    }

    function depositIndex(uint256 debt_) external view override returns (uint256) {
        return deposits.findIndexOfSum(debt_);
    }

    function depositSize() external view override returns (uint256) {
        return deposits.treeSum();
    }

    function depositUtilization(
        uint256 debt_,
        uint256 collateral_
    ) external view override returns (uint256) {
        return PoolCommons.utilization(deposits, debt_, collateral_);
    }

    function emasInfo() external view override returns (uint256, uint256) {
        return (
            interestParams.debtEma,
            interestParams.lupColEma
        );
    }

    function inflatorInfo() external view override returns (uint256, uint256) {
        return (
            inflatorSnapshot,
            lastInflatorSnapshotUpdate
        );
    }

    function interestRateInfo() external view returns (uint256, uint256) {
        return (
            interestParams.interestRate,
            interestParams.interestRateUpdate
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
    ) external view override returns (uint256, uint256) {
        return buckets.getLenderInfo(index_, lender_);
    }

    function loansInfo() external view override returns (address, uint256, uint256) {
        return (
            loans.getMax().borrower,
            Maths.wmul(loans.getMax().thresholdPrice, inflatorSnapshot),
            loans.noOfLoans()
        );
    }

    function reservesInfo() external view override returns (uint256, uint256, uint256) {
        return (
            auctions.totalBondEscrowed,
            reserveAuction.unclaimed,
            reserveAuction.kicked
        );
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
        uint256 t0AuctionDebt = t0DebtInAuction;
        if (t0AuctionDebt != 0 ) {
            // deposit in buckets within liquidation debt from the top-of-book down are frozen.
            if (index_ <= deposits.findIndexOfSum(Maths.wmul(t0AuctionDebt, inflator_))) revert RemoveDepositLockedByAuctionDebt();
        } 
    }
}
