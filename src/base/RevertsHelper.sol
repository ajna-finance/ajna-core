// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.14;

import { AuctionsState, LoansState, PoolBalancesState } from './interfaces/pool/IPoolState.sol';

import '../libraries/Loans.sol';
import '../libraries/Deposits.sol';
    /**
     *  @notice Head auction should be cleared prior of executing this action.
     */
    error AuctionNotCleared();
    /**
     *  @notice Borrower is attempting to create or modify a loan such that their loan's quote token would be less than the pool's minimum debt amount.
     */
    error AmountLTMinDebt();
    /**
     *  @notice User attempted a deposit which does not exceed the dust amount, or a withdrawal which leaves behind less than the dust amount.
     */
    error DustAmountNotExceeded();
    /**
     *  @notice Lender is attempting to remove quote tokens from a bucket that exists above active auction debt from top-of-book downward.
     */
    error RemoveDepositLockedByAuctionDebt();

    /**
     *  @notice Called by LPB removal functions assess whether or not LPB is locked.
     *  @param  index_    The deposit index from which LPB is attempting to be removed.
     *  @param  inflator_ The pool inflator used to properly assess t0 debt in auctions.
     */
    function _revertIfAuctionDebtLocked(
        DepositsState storage deposits_,
        PoolBalancesState storage poolBalances_,
        uint256 index_,
        uint256 inflator_
    ) view {
        uint256 t0AuctionDebt = poolBalances_.t0DebtInAuction;
        if (t0AuctionDebt != 0 ) {
            // deposit in buckets within liquidation debt from the top-of-book down are frozen.
            if (index_ <= Deposits.findIndexOfSum(deposits_, Maths.wmul(t0AuctionDebt, inflator_))) revert RemoveDepositLockedByAuctionDebt();
        } 
    }

    /**
     *  @notice Check if head auction is clearable (auction is kicked and 72 hours passed since kick time or auction still has debt but no remaining collateral).
     *  @notice Revert if auction is clearable
     */
    function _revertIfAuctionClearable(
        AuctionsState storage auctions_,
        LoansState    storage loans_
    ) view {
        address head     = auctions_.head;
        uint256 kickTime = auctions_.liquidations[head].kickTime;
        if (kickTime != 0) {
            if (block.timestamp - kickTime > 72 hours) revert AuctionNotCleared();

            Borrower storage borrower = loans_.borrowers[head];
            if (borrower.t0Debt != 0 && borrower.collateral == 0) revert AuctionNotCleared();
        }
    }

    function _revertOnMinDebt(
        LoansState storage loans_,
        uint256 poolDebt_,
        uint256 borrowerDebt_,
        uint256 quoteDust_
    ) view {
        if (borrowerDebt_ != 0) {
            uint256 loansCount = Loans.noOfLoans(loans_);
            if (loansCount >= 10) {
                if (borrowerDebt_ < _minDebtAmount(poolDebt_, loansCount)) revert AmountLTMinDebt();
            } else {
                if (borrowerDebt_ < quoteDust_)                            revert DustAmountNotExceeded();
            }
        }
    }
