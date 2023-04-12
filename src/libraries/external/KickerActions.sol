// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.14;

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
}                                   from '../../interfaces/pool/commons/IPoolState.sol';
import { KickResult }               from '../../interfaces/pool/commons/IPoolInternals.sol';
import { KickReserveAuctionParams } from '../../interfaces/pool/commons/IPoolReserveAuctionActions.sol';

import {
    _auctionPrice,
    _bondParams,
    _bpf,
    _claimableReserves,
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

    struct KickLocalVars {
        uint256 borrowerDebt;       // [WAD] the accrued debt of kicked borrower
        uint256 borrowerCollateral; // [WAD] amount of kicked borrower collateral
        uint256 neutralPrice;       // [WAD] neutral price recorded in kick action
        uint256 noOfLoans;          // number of loans and auctions in pool (used to calculate MOMP)
        uint256 momp;               // [WAD] MOMP of kicked auction
        uint256 bondFactor;         // [WAD] bond factor of kicked auction
        uint256 bondSize;           // [WAD] bond size of kicked auction
        uint256 t0KickPenalty;      // [WAD] t0 debt added as kick penalty
        uint256 kickPenalty;        // [WAD] current debt added as kick penalty
    }
    struct KickWithDepositLocalVars {
        uint256 amountToDebitFromDeposit; // [WAD] the amount of quote tokens used to kick and debited from lender deposit
        uint256 bucketCollateral;         // [WAD] amount of collateral in bucket
        uint256 bucketDeposit;            // [WAD] amount of quote tokens in bucket
        uint256 bucketLPs;                // [WAD] LPs of the bucket
        uint256 bucketPrice;              // [WAD] bucket price
        uint256 bucketRate;               // [WAD] bucket exchange rate
        uint256 bucketScale;              // [WAD] bucket scales
        uint256 bucketUnscaledDeposit;    // [WAD] unscaled amount of quote tokens in bucket
        uint256 lenderLPs;                // [WAD] LPs of lender in bucket
        uint256 redeemedLPs;              // [WAD] LPs used by kick action
    }

    /**************/
    /*** Events ***/
    /**************/

    // See `IPoolEvents` for descriptions
    event Kick(address indexed borrower, uint256 debt, uint256 collateral, uint256 bond);
    event RemoveQuoteToken(address indexed lender, uint256 indexed price, uint256 amount, uint256 lpRedeemed, uint256 lup);
    event KickReserveAuction(uint256 claimableReservesRemaining, uint256 auctionPrice, uint256 currentBurnEpoch);

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
     *  @notice Called to start borrower liquidation and to update the auctions queue.
     *  @param  poolState_       Current state of the pool.
     *  @param  borrowerAddress_ Address of the borrower to kick.
     *  @param  limitIndex_      Index of the lower bound of NP tolerated when kicking the auction.
     *  @return kickResult_      The result of the kick action.
     */
    function kick(
        AuctionsState storage auctions_,
        DepositsState storage deposits_,
        LoansState    storage loans_,
        PoolState calldata poolState_,
        address borrowerAddress_,
        uint256 limitIndex_
    ) external returns (
        KickResult memory
    ) {
        return _kick(
            auctions_,
            deposits_,
            loans_,
            poolState_,
            borrowerAddress_,
            limitIndex_,
            0
        );
    }

    /**
     *  @notice Called by lenders to kick loans using their deposits.
     *  @dev    write state:
     *              - Deposits.unscaledRemove (remove amount in Fenwick tree, from index):
     *                  - update values array state
     *              - decrement lender.lps accumulator
     *              - decrement bucket.lps accumulator
     *  @dev    emit events:
     *              - RemoveQuoteToken
     *  @param  poolState_  Current state of the pool.
     *  @param  index_      The deposit index from where lender removes liquidity.
     *  @param  limitIndex_ Index of the lower bound of NP tolerated when kicking the auction.
     *  @return kickResult_ The result of the kick action.
     */
    function kickWithDeposit(
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
        Bucket storage bucket = buckets_[index_];
        Lender storage lender = bucket.lenders[msg.sender];

        KickWithDepositLocalVars memory vars;

        if (bucket.bankruptcyTime < lender.depositTime) vars.lenderLPs = lender.lps;

        vars.bucketLPs             = bucket.lps;
        vars.bucketCollateral      = bucket.collateral;
        vars.bucketPrice           = _priceAt(index_);
        vars.bucketUnscaledDeposit = Deposits.unscaledValueAt(deposits_, index_);
        vars.bucketScale           = Deposits.scale(deposits_, index_);
        vars.bucketDeposit         = Maths.wmul(vars.bucketUnscaledDeposit, vars.bucketScale);

        // calculate max amount that can be removed (constrained by lender LPs in bucket, bucket deposit and the amount lender wants to remove)
        vars.bucketRate = Buckets.getExchangeRate(
            vars.bucketCollateral,
            vars.bucketLPs,
            vars.bucketDeposit,
            vars.bucketPrice
        );

        vars.amountToDebitFromDeposit = Maths.wmul(vars.lenderLPs, vars.bucketRate);  // calculate amount to remove based on lender LPs in bucket

        if (vars.amountToDebitFromDeposit > vars.bucketDeposit) vars.amountToDebitFromDeposit = vars.bucketDeposit; // cap the amount to remove at bucket deposit

        // revert if no amount that can be removed
        if (vars.amountToDebitFromDeposit == 0) revert InsufficientLiquidity();

        // kick top borrower
        kickResult_ = _kick(
            auctions_,
            deposits_,
            loans_,
            poolState_,
            Loans.getMax(loans_).borrower,
            limitIndex_,
            vars.amountToDebitFromDeposit
        );

        // amount to remove from deposit covers entire bond amount
        if (vars.amountToDebitFromDeposit > kickResult_.amountToCoverBond) {
            vars.amountToDebitFromDeposit = kickResult_.amountToCoverBond;                                 // cap amount to remove from deposit at amount to cover bond

            kickResult_.lup = Deposits.getLup(deposits_, poolState_.debt + vars.amountToDebitFromDeposit); // recalculate the LUP with the amount to cover bond
            kickResult_.amountToCoverBond = 0;                                                             // entire bond is covered from deposit, no additional amount to be send by lender
        } else {
            kickResult_.amountToCoverBond -= vars.amountToDebitFromDeposit;                                // lender should send additional amount to cover bond
        }

        // revert if the bucket price used to kick and remove is below new LUP
        if (vars.bucketPrice < kickResult_.lup) revert PriceBelowLUP();

        // remove amount from deposits
        if (vars.amountToDebitFromDeposit == vars.bucketDeposit && vars.bucketCollateral == 0) {
            // In this case we are redeeming the entire bucket exactly, and need to ensure bucket LPs are set to 0
            vars.redeemedLPs = vars.bucketLPs;

            Deposits.unscaledRemove(deposits_, index_, vars.bucketUnscaledDeposit);

        } else {
            vars.redeemedLPs = Maths.wdiv(vars.amountToDebitFromDeposit, vars.bucketRate);

            Deposits.unscaledRemove(
                deposits_,
                index_,
                Maths.wdiv(vars.amountToDebitFromDeposit, vars.bucketScale)
            );
        }

        // remove bucket LPs coresponding to the amount removed from deposits
        lender.lps -= vars.redeemedLPs;
        bucket.lps -= vars.redeemedLPs;

        emit RemoveQuoteToken(msg.sender, index_, vars.amountToDebitFromDeposit, vars.redeemedLPs, kickResult_.lup);
    }

    /*************************/
    /***  Reserve Auction  ***/
    /*************************/

    /**
     *  @notice See `IPoolReserveAuctionActions` for descriptions.
     *  @dev    write state:
     *              - update reserveAuction.unclaimed accumulator
     *              - update reserveAuction.kicked timestamp state
     *  @dev    reverts on:
     *          - no reserves to claim NoReserves()
     *  @dev    emit events:
     *              - KickReserveAuction
     */
    function kickReserveAuction(
        AuctionsState storage auctions_,
        ReserveAuctionState storage reserveAuction_,
        KickReserveAuctionParams calldata params_
    ) external returns (uint256 kickerAward_) {
        // retrieve timestamp of latest burn event and last burn timestamp
        uint256 latestBurnEpoch   = reserveAuction_.latestBurnEventEpoch;
        uint256 lastBurnTimestamp = reserveAuction_.burnEvents[latestBurnEpoch].timestamp;

        // check that at least two weeks have passed since the last reserve auction completed, and that the auction was not kicked within the past 72 hours
        if (block.timestamp < lastBurnTimestamp + 2 weeks || block.timestamp - reserveAuction_.kicked <= 72 hours) {
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

        kickerAward_ = Maths.wmul(0.01 * 1e18, claimable);

        curUnclaimedAuctionReserve += claimable - kickerAward_;

        if (curUnclaimedAuctionReserve == 0) revert NoReserves();

        reserveAuction_.unclaimed = curUnclaimedAuctionReserve;
        reserveAuction_.kicked    = block.timestamp;

        // increment latest burn event epoch and update burn event timestamp
        latestBurnEpoch += 1;

        reserveAuction_.latestBurnEventEpoch = latestBurnEpoch;
        reserveAuction_.burnEvents[latestBurnEpoch].timestamp = block.timestamp;

        emit KickReserveAuction(
            curUnclaimedAuctionReserve,
            _reserveAuctionPrice(block.timestamp),
            latestBurnEpoch
        );
    }

    /***************************/
    /***  Internal Functions ***/
    /***************************/

    /**
     *  @notice Called to start borrower liquidation and to update the auctions queue.
     *  @dev    write state:
     *              - _recordAuction:
     *                  - borrower -> liquidation mapping update
     *                  - increment auctions count accumulator
     *                  - increment auctions.totalBondEscrowed accumulator
     *                  - updates auction queue state
     *              - _updateKicker:
     *                  - update locked and claimable kicker accumulators
     *              - Loans.remove:
     *                  - delete borrower from indices => borrower address mapping
     *                  - remove loan from loans array
     *  @dev    emit events:
     *              - Kick
     *  @param  poolState_       Current state of the pool.
     *  @param  borrowerAddress_ Address of the borrower to kick.
     *  @param  limitIndex_      Index of the lower bound of NP tolerated when kicking the auction.
     *  @param  additionalDebt_  Additional debt to be used when calculating proposed LUP.
     *  @return kickResult_      The result of the kick action.
     */
    function _kick(
        AuctionsState storage auctions_,
        DepositsState storage deposits_,
        LoansState    storage loans_,
        PoolState calldata poolState_,
        address borrowerAddress_,
        uint256 limitIndex_,
        uint256 additionalDebt_
    ) internal returns (
        KickResult memory kickResult_
    ) {
        Borrower storage borrower = loans_.borrowers[borrowerAddress_];

        kickResult_.debtPreAction       = borrower.t0Debt;
        kickResult_.collateralPreAction = borrower.collateral;
        kickResult_.t0KickedDebt        = kickResult_.debtPreAction ;
        // add amount to remove to pool debt in order to calculate proposed LUP
        kickResult_.lup          = Deposits.getLup(deposits_, poolState_.debt + additionalDebt_);

        KickLocalVars memory vars;
        vars.borrowerDebt       = Maths.wmul(kickResult_.t0KickedDebt, poolState_.inflator);
        vars.borrowerCollateral = kickResult_.collateralPreAction;

        // revert if kick on a collateralized borrower
        if (_isCollateralized(vars.borrowerDebt, vars.borrowerCollateral, kickResult_.lup, poolState_.poolType)) {
            revert BorrowerOk();
        }

        // calculate auction params
        vars.neutralPrice = Maths.wmul(borrower.t0Np, poolState_.inflator);
        // check if NP is not less than price at the limit index provided by the kicker - done to prevent frontrunning kick auction call with a large amount of loan
        // which will make it harder for kicker to earn a reward and more likely that the kicker is penalized
        _revertIfPriceDroppedBelowLimit(vars.neutralPrice, limitIndex_);

        vars.noOfLoans = Loans.noOfLoans(loans_) + auctions_.noOfAuctions;

        vars.momp = _priceAt(
            Deposits.findIndexOfSum(
                deposits_,
                Maths.wdiv(poolState_.debt, vars.noOfLoans * 1e18)
            )
        );

        (vars.bondFactor, vars.bondSize) = _bondParams(
            vars.borrowerDebt,
            vars.borrowerCollateral,
            vars.momp
        );

        // record liquidation info
        _recordAuction(
            auctions_,
            borrowerAddress_,
            vars.bondSize,
            vars.bondFactor,
            vars.momp,
            vars.neutralPrice
        );

        // update kicker balances and get the difference needed to cover bond (after using any kick claimable funds if any)
        kickResult_.amountToCoverBond = _updateKicker(auctions_, vars.bondSize);

        // remove kicked loan from heap
        Loans.remove(loans_, borrowerAddress_, loans_.indices[borrowerAddress_]);

        // when loan is kicked, penalty of three months of interest is added
        vars.t0KickPenalty = Maths.wdiv(Maths.wmul(kickResult_.t0KickedDebt, poolState_.rate), 4 * 1e18);
        vars.kickPenalty   = Maths.wmul(vars.t0KickPenalty, poolState_.inflator);

        kickResult_.t0PoolDebt   = poolState_.t0Debt + vars.t0KickPenalty;
        kickResult_.t0KickedDebt += vars.t0KickPenalty;

        // update borrower debt with kicked debt penalty
        borrower.t0Debt = kickResult_.t0KickedDebt;

        emit Kick(
            borrowerAddress_,
            vars.borrowerDebt + vars.kickPenalty,
            vars.borrowerCollateral,
            vars.bondSize
        );
    }

    /**
     *  @notice Updates kicker balances.
     *  @dev    write state:
     *              - update locked and claimable kicker accumulators
     *  @param  bondSize_       Bond size to cover newly kicked auction.
     *  @return bondDifference_ The amount that kicker should send to pool to cover auction bond.
     */
    function _updateKicker(
        AuctionsState storage auctions_,
        uint256 bondSize_
    ) internal returns (uint256 bondDifference_){
        Kicker storage kicker = auctions_.kickers[msg.sender];

        kicker.locked += bondSize_;

        uint256 kickerClaimable = kicker.claimable;

        if (kickerClaimable >= bondSize_) {
            kicker.claimable -= bondSize_;

            // decrement total bond escrowed by bond size 
            auctions_.totalBondEscrowed -= bondSize_;
        } else {
            bondDifference_  = bondSize_ - kickerClaimable;
            kicker.claimable = 0;

            // decrement total bond escrowed by kicker claimable
            auctions_.totalBondEscrowed -= kickerClaimable;
        }
    }

    /**
     *  @notice Saves a new liquidation that was kicked.
     *  @dev    write state:
     *              - borrower -> liquidation mapping update
     *              - increment auctions count accumulator
     *              - updates auction queue state
     *  @param  borrowerAddress_ Address of the borrower that is kicked.
     *  @param  bondSize_        Bond size to cover newly kicked auction.
     *  @param  bondFactor_      Bond factor of the newly kicked auction.
     *  @param  momp_            Current pool MOMP.
     *  @param  neutralPrice_    Current pool Neutral Price.
     */
    function _recordAuction(
        AuctionsState storage auctions_,
        address borrowerAddress_,
        uint256 bondSize_,
        uint256 bondFactor_,
        uint256 momp_,
        uint256 neutralPrice_
    ) internal {
        Liquidation storage liquidation = auctions_.liquidations[borrowerAddress_];
        if (liquidation.kickTime != 0) revert AuctionActive();

        // record liquidation info
        liquidation.kicker       = msg.sender;
        liquidation.kickTime     = uint96(block.timestamp);
        liquidation.kickMomp     = uint96(momp_);
        liquidation.bondSize     = uint160(bondSize_);
        liquidation.bondFactor   = uint96(bondFactor_);
        liquidation.neutralPrice = uint96(neutralPrice_);

        // increment number of active auctions
        ++auctions_.noOfAuctions;

        // update totalBondEscrowed accumulator
        auctions_.totalBondEscrowed += bondSize_;

        // update auctions queue
        if (auctions_.head != address(0)) {
            // other auctions in queue, liquidation doesn't exist or overwriting.
            auctions_.liquidations[auctions_.tail].next = borrowerAddress_;
            liquidation.prev = auctions_.tail;
        } else {
            // first auction in queue
            auctions_.head = borrowerAddress_;
        }
        // update liquidation with the new ordering
        auctions_.tail = borrowerAddress_;
    }

}
