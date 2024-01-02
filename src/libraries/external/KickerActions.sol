// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.18;

import { Math }     from '@openzeppelin/contracts/utils/math/Math.sol';
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import { PoolType } from '../../interfaces/pool/IPool.sol';

import {
    AuctionsState,
    Borrower,
    Bucket,
    DepositsState,
    Kicker,
    Lender,
    Liquidation,
    LoansState,
    PoolState,
    ReserveAuctionState
}                             from '../../interfaces/pool/commons/IPoolState.sol';
import {
    KickResult,
    KickReserveAuctionParams
}                             from '../../interfaces/pool/commons/IPoolInternals.sol';

import {
    MAX_INFLATED_PRICE,
    COLLATERALIZATION_FACTOR,
    _bondParams,
    _borrowFeeRate,
    _claimableReserves,
    _htp,
    _isCollateralized,
    _priceAt,
    _reserveAuctionPrice
}                                   from '../helpers/PoolHelper.sol';
import {
    _revertIfPriceDroppedBelowLimit
}                                   from '../helpers/RevertsHelper.sol';

import { Buckets }  from '../internal/Buckets.sol';
import { Deposits } from '../internal/Deposits.sol';
import { Loans }    from '../internal/Loans.sol';
import { Maths }    from '../internal/Maths.sol';

/**
    @title  Auctions kicker actions library
    @notice External library containing kicker actions involving auctions within pool:
            - kick undercollateralized loans; start reserve auctions
 */
library KickerActions {

    /*************************/
    /*** Local Var Structs ***/
    /*************************/

    /// @dev Struct used for `kick` function local vars.
    struct KickLocalVars {
        uint256 borrowerDebt;          // [WAD] the accrued debt of kicked borrower
        uint256 borrowerCollateral;    // [WAD] amount of kicked borrower collateral
        uint256 t0ReserveSettleAmount; // [WAD] Amount of t0Debt that could be settled via reserves in an auction
        uint256 borrowerNpTpRatio;     // [WAD] borrower NP to TP ratio
        uint256 neutralPrice;          // [WAD] neutral price recorded in kick action
        uint256 htp;                   // [WAD] highest threshold price (including the collateralization factor) in pool
        uint256 referencePrice;        // [WAD] used to calculate auction start price
        uint256 bondFactor;            // [WAD] bond factor of kicked auction
        uint256 bondSize;              // [WAD] bond size of kicked auction
        uint256 debtToCollateral;      // [WAD] borrower debt to collateral at kick time
    }

    /// @dev Struct used for `lenderKick` function local vars.
    struct LenderKickLocalVars {
        uint256 bucketDeposit;  // [WAD] amount of quote tokens in bucket
        uint256 bucketPrice;    // [WAD] bucket price
        uint256 entitledAmount; // [WAD] amount that lender is entitled to remove at specified index
        uint256 lenderLP;       // [WAD] LP of lender in bucket
    }

    /**************/
    /*** Events ***/
    /**************/

    // See `IPoolEvents` for descriptions
    event BondWithdrawn(address indexed kicker, address indexed receiver, uint256 amount);
    event BucketBankruptcy(uint256 indexed index, uint256 lpForfeited);
    event Kick(address indexed borrower, uint256 debt, uint256 collateral, uint256 bond);
    event KickReserveAuction(uint256 claimableReservesRemaining, uint256 auctionPrice, uint256 currentBurnEpoch);
    event RemoveQuoteToken(address indexed lender, uint256 indexed price, uint256 amount, uint256 lpRedeemed, uint256 lup);

    /**************/
    /*** Errors ***/
    /**************/

    // See `IPoolErrors` for descriptions
    error AuctionActive();
    error BorrowerOk();
    error InsufficientLiquidity();
    error NoReserves();
    error PriceBelowLUP();
    error ReserveAuctionTooSoon();

    /***************************/
    /***  External Functions ***/
    /***************************/

    /**
     *  @notice See `IPoolKickerActions` for descriptions.
     *  @return kickResult_ The `KickResult` struct result of the kick action.
     */
    function kick(
        AuctionsState storage auctions_,
        DepositsState storage deposits_,
        LoansState    storage loans_,
        PoolState calldata poolState_,
        address borrowerAddress_,
        uint256 limitIndex_
    ) external returns (
        KickResult memory kickResult_
    ) {
        uint256 curLup = Deposits.getLup(deposits_, poolState_.debt);

        kickResult_ = _kick(
            auctions_,
            loans_,
            poolState_,
            borrowerAddress_,
            limitIndex_,
            curLup // proposed LUP is the current pool LUP
        );
        // return current LUP in pool
        kickResult_.lup = curLup;
    }

    /**
     *  @notice See `IPoolKickerActions` for descriptions.
     *  @dev    === Reverts on ===
     *  @dev    bucket price below current pool `LUP` `PriceBelowLUP()`
     *  @dev    insufficient deposit to kick auction `InsufficientLiquidity()`
     *  @return kickResult_ The `KickResult` struct result of the kick action.
     */
    function lenderKick(
        AuctionsState storage auctions_,
        DepositsState storage deposits_,
        mapping(uint256 => Bucket) storage buckets_,
        LoansState storage loans_,
        PoolState calldata poolState_,
        uint256 index_,
        uint256 limitIndex_
    ) external returns (
        KickResult memory kickResult_
    ) {
        LenderKickLocalVars memory vars;

        vars.bucketPrice = _priceAt(index_);

        // revert if the bucket price is below current LUP
        uint256 curLup = Deposits.getLup(deposits_, poolState_.debt);
        if (vars.bucketPrice < curLup) revert PriceBelowLUP();

        Bucket storage bucket = buckets_[index_];
        Lender storage lender = bucket.lenders[msg.sender];

        vars.lenderLP      = bucket.bankruptcyTime < lender.depositTime ? lender.lps : 0;
        vars.bucketDeposit = Deposits.valueAt(deposits_, index_);

        // calculate amount lender is entitled in current bucket (based on lender LP in bucket)
        vars.entitledAmount = Buckets.lpToQuoteTokens(
            bucket.collateral,
            bucket.lps,
            vars.bucketDeposit,
            vars.lenderLP,
            vars.bucketPrice,
            Math.Rounding.Down
        );

        // cap the amount entitled at bucket deposit
        if (vars.entitledAmount > vars.bucketDeposit) vars.entitledAmount = vars.bucketDeposit;

        // revert if no entitled amount
        if (vars.entitledAmount == 0) revert InsufficientLiquidity();

        // add amount to remove to pool debt in order to calculate proposed LUP
        // this simulates LUP movement with additional debt
        uint256 proposedLup =  Deposits.getLup(deposits_, poolState_.debt + vars.entitledAmount);

        // kick top borrower
        kickResult_ = _kick(
            auctions_,
            loans_,
            poolState_,
            Loans.getMax(loans_).borrower,
            limitIndex_,
            proposedLup
        );
        // return current LUP in pool
        kickResult_.lup = curLup;
    }

    /*************************/
    /***  Reserve Auction  ***/
    /*************************/

    /**
     *  @notice See `IPoolKickerActions` for descriptions.
     *  @dev    === Write state ===
     *  @dev    update `reserveAuction.unclaimed` accumulator
     *  @dev    update `reserveAuction.kicked` timestamp state
     *  @dev    === Reverts on ===
     *  @dev    no reserves to claim `NoReserves()`
     *  @dev    5 days not passed `ReserveAuctionTooSoon()`
     *  @dev    === Emit events ===
     *  @dev    - `KickReserveAuction`
     */
    function kickReserveAuction(
        AuctionsState storage auctions_,
        ReserveAuctionState storage reserveAuction_,
        KickReserveAuctionParams calldata params_
    ) external {
        // retrieve timestamp of latest burn event and last burn timestamp
        uint256 latestBurnEpoch = reserveAuction_.latestBurnEventEpoch;

        // check that at least five days have passed since the last reserve auction was kicked
        if (block.timestamp < reserveAuction_.kicked + 120 hours) {
            revert ReserveAuctionTooSoon();
        }

        uint256 curUnclaimedAuctionReserve = reserveAuction_.unclaimed;

        uint256 claimable = _claimableReserves(
            Maths.wmul(params_.t0PoolDebt, params_.inflator),
            params_.poolSize,
            auctions_.totalBondEscrowed,
            curUnclaimedAuctionReserve,
            params_.poolBalance
        );

        curUnclaimedAuctionReserve += claimable;

        if (curUnclaimedAuctionReserve == 0) revert NoReserves();

        reserveAuction_.unclaimed          = curUnclaimedAuctionReserve;
        reserveAuction_.kicked             = block.timestamp;
        reserveAuction_.lastKickedReserves = curUnclaimedAuctionReserve;

        // increment latest burn event epoch and update burn event timestamp
        latestBurnEpoch += 1;

        reserveAuction_.latestBurnEventEpoch = latestBurnEpoch;
        reserveAuction_.burnEvents[latestBurnEpoch].timestamp = block.timestamp;

        emit KickReserveAuction(
            curUnclaimedAuctionReserve,
            _reserveAuctionPrice(block.timestamp, curUnclaimedAuctionReserve),
            latestBurnEpoch
        );
    }

    function withdrawBonds(
        AuctionsState storage auctions_,
        address recipient_,
        uint256 maxAmount_
    ) external returns (uint256 amount_) {
        uint256 claimable = auctions_.kickers[msg.sender].claimable;

        // the amount to claim is constrained by the claimable balance of sender
        // claiming escrowed bonds is not constraiend by the pool balance
        amount_ = Maths.min(maxAmount_, claimable);

        // revert if no amount to claim
        if (amount_ == 0) revert InsufficientLiquidity();

        // decrement total bond escrowed
        auctions_.totalBondEscrowed             -= amount_;
        auctions_.kickers[msg.sender].claimable -= amount_;

        emit BondWithdrawn(msg.sender, recipient_, amount_);
    }

    /***************************/
    /***  Internal Functions ***/
    /***************************/

    /**
     *  @notice Called to start borrower liquidation and to update the auctions queue.
     *  @dev    === Write state ===
     *  @dev    - `_recordAuction`:
     *  @dev      `borrower -> liquidation` mapping update
     *  @dev      increment `auctions count` accumulator
     *  @dev      increment `auctions.totalBondEscrowed` accumulator
     *  @dev      updates auction queue state
     *  @dev    - `_updateEscrowedBonds`:
     *  @dev      update `locked` and `claimable` kicker accumulators
     *  @dev    - `Loans.remove`:
     *  @dev      delete borrower from `indices => borrower` address mapping
     *  @dev      remove loan from loans array
     *  @dev    === Emit events ===
     *  @dev    - `Kick`
     *  @param  auctions_        Struct for pool auctions state.
     *  @param  loans_           Struct for pool loans state.
     *  @param  poolState_       Current state of the pool.
     *  @param  borrowerAddress_ Address of the borrower to kick.
     *  @param  limitIndex_      Index of the lower bound of `NP` tolerated when kicking the auction.
     *  @param  proposedLup_     Proposed `LUP` in pool.
     *  @return kickResult_      The `KickResult` struct result of the kick action.
     */
    function _kick(
        AuctionsState storage auctions_,
        LoansState    storage loans_,
        PoolState calldata poolState_,
        address borrowerAddress_,
        uint256 limitIndex_,
        uint256 proposedLup_
    ) internal returns (
        KickResult memory kickResult_
    ) {
        Liquidation storage liquidation = auctions_.liquidations[borrowerAddress_];
        // revert if liquidation is active
        if (liquidation.kickTime != 0) revert AuctionActive();

        Borrower storage borrower = loans_.borrowers[borrowerAddress_];

        kickResult_.t0KickedDebt        = borrower.t0Debt;
        kickResult_.collateralPreAction = borrower.collateral;

        KickLocalVars memory vars;
        vars.borrowerDebt          = Maths.wmul(kickResult_.t0KickedDebt, poolState_.inflator);
        vars.borrowerCollateral    = kickResult_.collateralPreAction;
        vars.t0ReserveSettleAmount = Maths.wmul(kickResult_.t0KickedDebt, _borrowFeeRate(poolState_.rate)) / 2;
        vars.borrowerNpTpRatio     = borrower.npTpRatio;

        // revert if kick on a collateralized borrower
        if (_isCollateralized(vars.borrowerDebt, vars.borrowerCollateral, proposedLup_, poolState_.poolType)) {
            revert BorrowerOk();
        }

        // calculate auction params
        // neutral price = Tp * Np to Tp ratio
        // neutral price is capped at 50 * max pool price
        vars.neutralPrice = Maths.min(
            Math.mulDiv(Maths.wmul(vars.borrowerDebt, COLLATERALIZATION_FACTOR), 
            vars.borrowerNpTpRatio, vars.borrowerCollateral),
            MAX_INFLATED_PRICE
        );
        // check if NP is not less than price at the limit index provided by the kicker - done to prevent frontrunning kick auction call with a large amount of loan
        // which will make it harder for kicker to earn a reward and more likely that the kicker is penalized
        _revertIfPriceDroppedBelowLimit(vars.neutralPrice, limitIndex_);

        vars.htp            = _htp(Loans.getMax(loans_).t0DebtToCollateral, poolState_.inflator);
        vars.referencePrice = Maths.min(Maths.max(vars.htp, vars.neutralPrice), MAX_INFLATED_PRICE);

        (vars.bondFactor, vars.bondSize) = _bondParams(
            vars.borrowerDebt,
            vars.borrowerNpTpRatio
        );

        vars.debtToCollateral = Maths.wdiv(vars.borrowerDebt, vars.borrowerCollateral);

        // record liquidation info
        _recordAuction(
            auctions_,
            liquidation,
            borrowerAddress_,
            vars.bondSize,
            vars.bondFactor,
            vars.referencePrice,
            vars.neutralPrice,
            vars.debtToCollateral,
            vars.t0ReserveSettleAmount
        );

        // update escrowed bonds balances and get the difference needed to cover bond (after using any kick claimable funds if any)
        kickResult_.amountToCoverBond = _updateEscrowedBonds(auctions_, vars.bondSize);

        // remove kicked loan from heap
        Loans.remove(loans_, borrowerAddress_, loans_.indices[borrowerAddress_]);

        emit Kick(
            borrowerAddress_,
            vars.borrowerDebt,
            vars.borrowerCollateral,
            vars.bondSize
        );
    }

    /**
     *  @notice Updates escrowed bonds balances, reuse kicker claimable funds and calculates difference needed to cover new bond.
     *  @dev    === Write state ===
     *  @dev    update `locked` and `claimable` kicker accumulators
     *  @dev    update `totalBondEscrowed` accumulator
     *  @param  auctions_       Struct for pool auctions state.
     *  @param  bondSize_       Bond size to cover newly kicked auction.
     *  @return bondDifference_ The amount that kicker should send to pool to cover auction bond.
     */
    function _updateEscrowedBonds(
        AuctionsState storage auctions_,
        uint256 bondSize_
    ) internal returns (uint256 bondDifference_){
        Kicker storage kicker = auctions_.kickers[msg.sender];

        kicker.locked += bondSize_;

        uint256 kickerClaimable = kicker.claimable;

        if (kickerClaimable >= bondSize_) {
            // no need to update total bond escrowed as bond is covered by kicker claimable (which is already tracked by accumulator)
            kicker.claimable -= bondSize_;
        } else {
            bondDifference_  = bondSize_ - kickerClaimable;
            kicker.claimable = 0;

            // increment total bond escrowed by amount needed to cover bond difference
            auctions_.totalBondEscrowed += bondDifference_;
        }
    }

    /**
     *  @notice Saves in storage a new liquidation that was kicked.
     *  @dev    === Write state ===
     *  @dev    `borrower -> liquidation` mapping update
     *  @dev    increment auctions count accumulator
     *  @dev    updates auction queue state
     *  @param  auctions_              Struct for pool auctions state.
     *  @param  liquidation_           Struct for current auction state.
     *  @param  borrowerAddress_       Address of the borrower that is kicked.
     *  @param  bondSize_              Bond size to cover newly kicked auction.
     *  @param  bondFactor_            Bond factor of the newly kicked auction.
     *  @param  referencePrice_        Used to calculate auction start price.
     *  @param  neutralPrice_          Current pool `Neutral Price`.
     *  @param  debtToCollateral_      Borrower debt to collateral at time of kick.
     *  @param  t0ReserveSettleAmount_ Amount of t0Debt that could be settled via reserves in auction
     */
    function _recordAuction(
        AuctionsState storage auctions_,
        Liquidation storage liquidation_,
        address borrowerAddress_,
        uint256 bondSize_,
        uint256 bondFactor_,
        uint256 referencePrice_,
        uint256 neutralPrice_,
        uint256 debtToCollateral_,
        uint256 t0ReserveSettleAmount_
    ) internal {
        // record liquidation info
        liquidation_.kicker                = msg.sender;
        liquidation_.kickTime              = uint96(block.timestamp);
        liquidation_.bondSize              = SafeCast.toUint160(bondSize_);
        liquidation_.bondFactor            = SafeCast.toUint96(bondFactor_);
        liquidation_.neutralPrice          = SafeCast.toUint96(neutralPrice_);
        liquidation_.debtToCollateral      = debtToCollateral_;
        liquidation_.t0ReserveSettleAmount = t0ReserveSettleAmount_;

        // increment number of active auctions
        ++auctions_.noOfAuctions;

        // update auctions queue
        if (auctions_.head != address(0)) {
            // other auctions in queue, liquidation doesn't exist or overwriting.
            address tail = auctions_.tail;
            auctions_.liquidations[tail].next = borrowerAddress_;
            liquidation_.prev = tail;
            liquidation_.referencePrice = SafeCast.toUint96(Maths.max(referencePrice_, auctions_.liquidations[tail].referencePrice));
        } else {
            // first auction in queue
            auctions_.head = borrowerAddress_;
            liquidation_.referencePrice = SafeCast.toUint96(referencePrice_);
        }
        // update liquidation with the new ordering
        auctions_.tail = borrowerAddress_;
    }

}
