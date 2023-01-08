// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.14;

import { Clone }           from '@clones/Clone.sol';
import { ReentrancyGuard } from '@openzeppelin/contracts/security/ReentrancyGuard.sol';
import { Multicall }       from '@openzeppelin/contracts/utils/Multicall.sol';
import { SafeERC20 }       from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20 }          from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {
    IPool,
    IPoolImmutables,
    IPoolLenderActions,
    IPoolState,
    IPoolLiquidationActions,
    IPoolReserveAuctionActions,
    IPoolDerivedState,
    IERC20Token
}                                    from '../interfaces/pool/IPool.sol';
import {
    PoolState,
    AuctionsState,
    DepositsState,
    LoansState,
    InflatorState,
    InterestState,
    PoolBalancesState,
    ReserveAuctionState,
    Bucket,
    BurnEvent,
    Liquidation
}                                    from '../interfaces/pool/commons/IPoolState.sol';
import {
    KickResult,
    RemoveQuoteParams,
    MoveQuoteParams,
    AddQuoteParams
}                                    from '../interfaces/pool/commons/IPoolInternals.sol';
import { StartReserveAuctionParams } from '../interfaces/pool/commons/IPoolReserveAuctionActions.sol';

import {
    _priceAt,
    _roundToScale
}                               from '../libraries/helpers/PoolHelper.sol';
import {
    _revertIfAuctionDebtLocked,
    _revertIfAuctionClearable
}                               from '../libraries/helpers/RevertsHelper.sol';

import { Buckets }  from '../libraries/internal/Buckets.sol';
import { Deposits } from '../libraries/internal/Deposits.sol';
import { Loans }    from '../libraries/internal/Loans.sol';
import { Maths }    from '../libraries/internal/Maths.sol';

import { Auctions }        from '../libraries/external/Auctions.sol';
import { BorrowerActions } from '../libraries/external/BorrowerActions.sol';
import { LenderActions }   from '../libraries/external/LenderActions.sol';
import { PoolCommons }     from '../libraries/external/PoolCommons.sol';

/**
 *  @title  Pool Contract
 *  @dev    Base contract and entrypoint for commong logic of both ERC20 and ERC721 pools.
 */
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

    AuctionsState       internal auctions;
    DepositsState       internal deposits;
    LoansState          internal loans;
    InflatorState       internal inflatorState;
    InterestState       internal interestState;
    PoolBalancesState   internal poolBalances;
    ReserveAuctionState internal reserveAuction;

    mapping(uint256 => Bucket) internal buckets;   // deposit index -> bucket

    bool internal isPoolInitialized;

    mapping(address => mapping(address => mapping(uint256 => uint256))) private _lpTokenAllowances; // owner address -> new owner address -> deposit index -> allowed amount

    /******************/
    /*** Immutables ***/
    /******************/

    /// @inheritdoc IPoolImmutables
    function poolType() external pure override returns (uint8) {
        return _getArgUint8(POOL_TYPE);
    }

    /// @inheritdoc IPoolImmutables
    function collateralAddress() external pure override returns (address) {
        return _getArgAddress(COLLATERAL_ADDRESS);
    }

    /// @inheritdoc IPoolImmutables
    function quoteTokenAddress() external pure override returns (address) {
        return _getArgAddress(QUOTE_ADDRESS);
    }

    /// @inheritdoc IPoolImmutables
    function quoteTokenScale() external pure override returns (uint256) {
        return _getArgUint256(QUOTE_SCALE);
    }

    function quoteTokenDust() external pure override returns (uint256) {
        return _getArgUint256(QUOTE_SCALE);
    }


    /*********************************/
    /*** Lender External Functions ***/
    /*********************************/

    /// @inheritdoc IPoolLenderActions
    function addQuoteToken(
        uint256 quoteTokenAmountToAdd_,
        uint256 index_
    ) external override nonReentrant returns (uint256 bucketLPs_) {
        PoolState memory poolState = _accruePoolInterest();

        // round to token precision
        quoteTokenAmountToAdd_ = _roundToScale(quoteTokenAmountToAdd_, poolState.quoteDustLimit);

        uint256 newLup;
        (bucketLPs_, newLup) = LenderActions.addQuoteToken(
            buckets,
            deposits,
            poolState,
            AddQuoteParams({
                amount: quoteTokenAmountToAdd_,
                index:  index_
            })
        );

        // update pool interest rate state
        _updateInterestState(poolState, newLup);

        // move quote token amount from lender to pool
        _transferQuoteTokenFrom(msg.sender, quoteTokenAmountToAdd_);
    }

    /**
     *  @inheritdoc IPoolLenderActions
     *  @dev write state:
     *          - _lpTokenAllowances mapping
     */
    function approveLpOwnership(
        address allowedNewOwner_,
        uint256 index_,
        uint256 lpsAmountToApprove_
    ) external nonReentrant {
        _lpTokenAllowances[msg.sender][allowedNewOwner_][index_] = lpsAmountToApprove_;
    }

    /// @inheritdoc IPoolLenderActions
    function moveQuoteToken(
        uint256 maxAmountToMove_,
        uint256 fromIndex_,
        uint256 toIndex_
    ) external override nonReentrant returns (uint256 fromBucketLPs_, uint256 toBucketLPs_) {
        PoolState memory poolState = _accruePoolInterest();

        _revertIfAuctionDebtLocked(deposits, poolBalances, fromIndex_, poolState.inflator);

        uint256 newLup;
        (
            fromBucketLPs_,
            toBucketLPs_,
            newLup
        ) = LenderActions.moveQuoteToken(
            buckets,
            deposits,
            poolState,
            MoveQuoteParams({
                maxAmountToMove: maxAmountToMove_,
                fromIndex:       fromIndex_,
                toIndex:         toIndex_,
                thresholdPrice:  Loans.getMax(loans).thresholdPrice
            })
        );

        // update pool interest rate state
        _updateInterestState(poolState, newLup);
    }

    /// @inheritdoc IPoolLenderActions
    function removeQuoteToken(
        uint256 maxAmount_,
        uint256 index_
    ) external override nonReentrant returns (uint256 removedAmount_, uint256 redeemedLPs_) {
        _revertIfAuctionClearable(auctions, loans);

        PoolState memory poolState = _accruePoolInterest();

        _revertIfAuctionDebtLocked(deposits, poolBalances, index_, poolState.inflator);

        uint256 newLup;
        (
            removedAmount_,
            redeemedLPs_,
            newLup
        ) = LenderActions.removeQuoteToken(
            buckets,
            deposits,
            poolState,
            RemoveQuoteParams({
                maxAmount:      maxAmount_,
                index:          index_,
                thresholdPrice: Loans.getMax(loans).thresholdPrice
            })
        );

        // update pool interest rate state
        _updateInterestState(poolState, newLup);

        // move quote token amount from pool to lender
        _transferQuoteToken(msg.sender, removedAmount_);
    }

    /// @inheritdoc IPoolLenderActions
    function transferLPs(
        address owner_,
        address newOwner_,
        uint256[] calldata indexes_
    ) external override nonReentrant {
        LenderActions.transferLPs(
            buckets,
            _lpTokenAllowances,
            owner_,
            newOwner_,
            indexes_
        );
    }

    /*****************************/
    /*** Liquidation Functions ***/
    /*****************************/

    /**
     *  @inheritdoc IPoolLiquidationActions
     *  @dev write state:
     *       - increment poolBalances.t0DebtInAuction and poolBalances.t0Debt accumulators
     */
    function kick(
        address borrowerAddress_
    ) external override nonReentrant {
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

    /**
     *  @inheritdoc IPoolLiquidationActions
     *  @dev write state:
     *       - increment poolBalances.t0DebtInAuction and poolBalances.t0Debt accumulators
     */
    function kickWithDeposit(
        uint256 index_
    ) external override nonReentrant {
        PoolState memory poolState = _accruePoolInterest();

        // kick auctions
        KickResult memory result = Auctions.kickWithDeposit(
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

    /**
     *  @inheritdoc IPoolLiquidationActions
     *  @dev write state:
     *       - reset kicker's claimable accumulator
     */
    function withdrawBonds() external {
        uint256 claimable = auctions.kickers[msg.sender].claimable;
        auctions.kickers[msg.sender].claimable = 0;
        _transferQuoteToken(msg.sender, claimable);
    }

    /*********************************/
    /*** Reserve Auction Functions ***/
    /*********************************/

    /**
     *  @inheritdoc IPoolReserveAuctionActions
     *  @dev  write state:
     *          - increment latestBurnEpoch counter
     *          - update reserveAuction.latestBurnEventEpoch and burn event timestamp state
     *  @dev reverts on:
     *          - 2 weeks not passed ReserveAuctionTooSoon()
     *  @dev emit events:
     *          - ReserveAuction
     */
    function startClaimableReserveAuction() external override nonReentrant {
        // retrieve timestamp of latest burn event and last burn timestamp
        uint256 latestBurnEpoch   = reserveAuction.latestBurnEventEpoch;
        uint256 lastBurnTimestamp = reserveAuction.burnEvents[latestBurnEpoch].timestamp;

        // check that at least two weeks have passed since the last reserve auction completed, and that the auction was not kicked within the past 72 hours
        if (block.timestamp < lastBurnTimestamp + 2 weeks || block.timestamp - reserveAuction.kicked <= 72 hours) {
            revert ReserveAuctionTooSoon();
        }

        // start a new claimable reserve auction, passing in relevant parameters such as the current pool size, debt, balance, and inflator value
        uint256 kickerAward = Auctions.startClaimableReserveAuction(
            auctions,
            reserveAuction,
            StartReserveAuctionParams({
                poolSize:    Deposits.treeSum(deposits),
                poolDebt:    poolBalances.t0Debt,
                poolBalance: _getPoolQuoteTokenBalance(),
                inflator:    inflatorState.inflator
            })
        );

        // increment latest burn event epoch and update burn event timestamp
        latestBurnEpoch += 1;

        reserveAuction.latestBurnEventEpoch = latestBurnEpoch;
        reserveAuction.burnEvents[latestBurnEpoch].timestamp = block.timestamp;

        // transfer kicker award to msg.sender
        _transferQuoteToken(msg.sender, kickerAward);
    }

    /**
     *  @inheritdoc IPoolReserveAuctionActions
     *  @dev  write state:
     *          - increment reserveAuction.totalAjnaBurned accumulator
     *          - update burn event totalInterest and totalBurned accumulators
     */
    function takeReserves(
        uint256 maxAmount_
    ) external override nonReentrant returns (uint256 amount_) {
        uint256 ajnaRequired;
        (amount_, ajnaRequired) = Auctions.takeReserves(
            reserveAuction,
            maxAmount_
        );

        uint256 totalBurned = reserveAuction.totalAjnaBurned + ajnaRequired;
        
        // accumulate additional ajna burned
        reserveAuction.totalAjnaBurned = totalBurned;

        uint256 burnEventEpoch = reserveAuction.latestBurnEventEpoch;

        // record burn event information to enable querying by staking rewards
        BurnEvent storage burnEvent = reserveAuction.burnEvents[burnEventEpoch];
        burnEvent.totalInterest = reserveAuction.totalInterestEarned;
        burnEvent.totalBurned   = totalBurned;

        // burn required number of ajna tokens to take quote from reserves
        IERC20(_getArgAddress(AJNA_ADDRESS)).safeTransferFrom(msg.sender, address(this), ajnaRequired);

        IERC20Token(_getArgAddress(AJNA_ADDRESS)).burn(ajnaRequired);

        // transfer quote token to caller
        _transferQuoteToken(msg.sender, amount_);
    }

    /*****************************/
    /*** Pool Helper Functions ***/
    /*****************************/

    /**
     *  @notice Accrues pool interest in current block and returns pool details.
     *  @dev    external libraries call:
     *              - PoolCommons.accrueInterest   
     *  @dev    write state:
     *              - PoolCommons.accrueInterest:
     *                  - Deposits.mult (scale Fenwick tree with new interest accrued):
     *                      - update scaling array state 
     *              - increment reserveAuction.totalInterestEarned accumulator
     *  @return poolState_ Struct containing pool details.
     */
    function _accruePoolInterest() internal returns (PoolState memory poolState_) {
	    // retrieve t0Debt amount from poolBalances struct
        uint256 t0Debt = poolBalances.t0Debt;

	    // initialize fields of poolState_ struct with initial values
        poolState_.collateral     = poolBalances.pledgedCollateral;
        poolState_.inflator       = inflatorState.inflator;
        poolState_.rate           = interestState.interestRate;
        poolState_.poolType       = _getArgUint8(POOL_TYPE);
        poolState_.quoteDustLimit = _getArgUint256(QUOTE_SCALE);

	    // check if t0Debt is not equal to 0, indicating that there is debt to be tracked for the pool
        if (t0Debt != 0) {
            // Calculate prior pool debt
            poolState_.debt = Maths.wmul(t0Debt, poolState_.inflator);

	        // calculate elapsed time since inflator was last updated
            uint256 elapsed = block.timestamp - inflatorState.inflatorUpdate;

	        // set isNewInterestAccrued field to true if elapsed time is not 0, indicating that new interest may have accrued
            poolState_.isNewInterestAccrued = elapsed != 0;

            // if new interest may have accrued, call accrueInterest function and update inflator and debt fields of poolState_ struct
            if (poolState_.isNewInterestAccrued) {
                (uint256 newInflator, uint256 newInterest) = PoolCommons.accrueInterest(
                    deposits,
                    poolState_,
                    Loans.getMax(loans).thresholdPrice,
                    elapsed
                );
                poolState_.inflator = newInflator;
                // After debt owed to lenders has accrued, calculate current debt owed by borrowers
                poolState_.debt = Maths.wmul(t0Debt, poolState_.inflator);

                // update total interest earned accumulator with the newly accrued interest
                reserveAuction.totalInterestEarned += newInterest;
            }
        }
    }

    /**
     *  @notice Update interest rate and inflator of the pool.
     *  @dev    external libraries call:
     *              - PoolCommons.updateInterestRate     
     *  @dev    write state:
     *              - PoolCommons.updateInterestRate 
     *                  - interest debt and lup * collateral EMAs accumulators
     *                  - interest rate accumulator and interestRateUpdate state
     *              - pool inflator and inflatorUpdate state
     *  @dev    emit events:
     *              - PoolCommons.updateInterestRate:
     *                  - UpdateInterestRate
     *  @param  poolState_ Struct containing pool details.
     *  @param  lup_       Current LUP in pool.
     */
    function _updateInterestState(
        PoolState memory poolState_,
        uint256 lup_
    ) internal {
        // if it has been more than 12 hours since the last interest rate update, call updateInterestRate function
        if (block.timestamp - interestState.interestRateUpdate > 12 hours) {
            PoolCommons.updateInterestRate(interestState, deposits, poolState_, lup_);
        }

        // update pool inflator
        if (poolState_.isNewInterestAccrued) {
            inflatorState.inflator       = uint208(poolState_.inflator);
            inflatorState.inflatorUpdate = uint48(block.timestamp);
        // if the debt in the current pool state is 0, also update the inflator and inflatorUpdate fields in inflatorState
        // slither-disable-next-line incorrect-equality
        } else if (poolState_.debt == 0) {
            inflatorState.inflator       = uint208(Maths.WAD);
            inflatorState.inflatorUpdate = uint48(block.timestamp);
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

    function _lup(uint256 debt_) internal view returns (uint256) {
        return _priceAt(Deposits.findIndexOfSum(deposits, debt_));
    }

    /**************************/
    /*** External Functions ***/
    /**************************/

    /// @inheritdoc IPoolState
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

    /// @inheritdoc IPoolState
    function borrowerInfo(
        address borrower_
    ) external view override returns (uint256, uint256, uint256) {
        return (
            loans.borrowers[borrower_].t0Debt,
            loans.borrowers[borrower_].collateral,
            loans.borrowers[borrower_].t0Np
        );
    }

    /// @inheritdoc IPoolState
    function bucketInfo(
        uint256 index_
    ) external view override returns (uint256, uint256, uint256, uint256, uint256) {
        uint256 scale = Deposits.scale(deposits, index_);
        return (
            buckets[index_].lps,
            buckets[index_].collateral,
            buckets[index_].bankruptcyTime,
            Maths.wmul(scale, Deposits.unscaledValueAt(deposits, index_)),
            scale
        );
    }

    /// @inheritdoc IPoolDerivedState
    function bucketExchangeRate(
        uint256 index_
    ) external view returns (uint256 exchangeRate_) {
        Bucket storage bucket = buckets[index_];

        exchangeRate_ = Buckets.getExchangeRate(
            bucket.collateral,
            bucket.lps,
            Deposits.valueAt(deposits, index_),
            _priceAt(index_)
        );
    }

    /// @inheritdoc IPoolState
    function currentBurnEpoch() external view returns (uint256) {
        return reserveAuction.latestBurnEventEpoch;
    }

    /// @inheritdoc IPoolState
    function burnInfo(uint256 burnEventEpoch_) external view returns (uint256, uint256, uint256) {
        BurnEvent memory burnEvent = reserveAuction.burnEvents[burnEventEpoch_];

        return (
            burnEvent.timestamp,
            burnEvent.totalInterest,
            burnEvent.totalBurned
        );
    }

    /// @inheritdoc IPoolState
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

    /// @inheritdoc IPoolDerivedState
    function depositIndex(uint256 debt_) external view override returns (uint256) {
        return Deposits.findIndexOfSum(deposits, debt_);
    }

    /// @inheritdoc IPoolDerivedState
    function depositSize() external view override returns (uint256) {
        return Deposits.treeSum(deposits);
    }

    /// @inheritdoc IPoolDerivedState
    function depositUtilization(
        uint256 debt_,
        uint256 collateral_
    ) external view override returns (uint256) {
        return PoolCommons.utilization(deposits, debt_, collateral_);
    }

    /// @inheritdoc IPoolState
    function emasInfo() external view override returns (uint256, uint256) {
        return (
            interestState.debtEma,
            interestState.lupColEma
        );
    }

    /// @inheritdoc IPoolState
    function inflatorInfo() external view override returns (uint256, uint256) {
        return (
            inflatorState.inflator,
            inflatorState.inflatorUpdate
        );
    }

    /// @inheritdoc IPoolState
    function interestRateInfo() external view returns (uint256, uint256) {
        return (
            interestState.interestRate,
            interestState.interestRateUpdate
        );
    }

    /// @inheritdoc IPoolState
    function kickerInfo(
        address kicker_
    ) external view override returns (uint256, uint256) {
        return(
            auctions.kickers[kicker_].claimable,
            auctions.kickers[kicker_].locked
        );
    }

    /// @inheritdoc IPoolState
    function lenderInfo(
        uint256 index_,
        address lender_
    ) external view override returns (uint256 lpBalance_, uint256 depositTime_) {
        depositTime_ = buckets[index_].lenders[lender_].depositTime;
        if (buckets[index_].bankruptcyTime < depositTime_) lpBalance_ = buckets[index_].lenders[lender_].lps;
    }

    /// @inheritdoc IPoolState
    function loanInfo(
        uint256 loanId_
    ) external view override returns (address, uint256) {
        return (
            Loans.getByIndex(loans, loanId_).borrower,
            Loans.getByIndex(loans, loanId_).thresholdPrice
        );
    }

    /// @inheritdoc IPoolState
    function loansInfo() external view override returns (address, uint256, uint256) {
        return (
            Loans.getMax(loans).borrower,
            Maths.wmul(Loans.getMax(loans).thresholdPrice, inflatorState.inflator),
            Loans.noOfLoans(loans)
        );
    }

    /// @inheritdoc IPoolState
    function pledgedCollateral() external view override returns (uint256) {
        return poolBalances.pledgedCollateral;
    }

    /// @inheritdoc IPoolState
    function reservesInfo() external view override returns (uint256, uint256, uint256) {
        return (
            auctions.totalBondEscrowed,
            reserveAuction.unclaimed,
            reserveAuction.kicked
        );
    }
}
