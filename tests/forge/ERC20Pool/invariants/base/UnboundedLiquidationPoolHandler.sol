// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.14;

import { _priceAt }          from 'src/libraries/helpers/PoolHelper.sol';
import { MAX_FENWICK_INDEX } from 'src/libraries/helpers/PoolHelper.sol';

import 'src/libraries/internal/Maths.sol';

import {
    LENDER_MIN_BUCKET_INDEX,
    LENDER_MAX_BUCKET_INDEX,
    BaseHandler
} from './BaseHandler.sol';

abstract contract UnboundedLiquidationPoolHandler is BaseHandler {

    /*******************************/
    /*** Kicker Helper Functions ***/
    /*******************************/

    function _kickAuction(
        address borrower_
    ) internal useTimestamps updateLocalStateAndPoolInterest {
        numberOfCalls['UBLiquidationHandler.kickAuction']++;

        (uint256 borrowerDebt, , ) = _poolInfo.borrowerInfo(address(_pool), borrower_);
        (uint256 interestRate, )   = _pool.interestRateInfo();

        try _pool.kick(borrower_, 7388) {

            // **RE9**:  Reserves increase by 3 months of interest when a loan is kicked
            increaseInReserves += Maths.wmul(borrowerDebt, Maths.wdiv(interestRate, 4 * 1e18));

        } catch (bytes memory err) {
            _ensurePoolError(err);
        }
    }

    function _kickWithDeposit(
        uint256 bucketIndex_
    ) internal useTimestamps updateLocalStateAndPoolInterest {
        (address maxBorrower, , )              = _pool.loansInfo();
        (uint256 borrowerDebt, , )             = _poolInfo.borrowerInfo(address(_pool), maxBorrower);
        (uint256 interestRate, )               = _pool.interestRateInfo();
        ( , , , uint256 depositBeforeAction, ) = _pool.bucketInfo(bucketIndex_);

        try _pool.kickWithDeposit(bucketIndex_, 7388) {

            ( , , , uint256 depositAfterAction, ) = _pool.bucketInfo(bucketIndex_);

            // **RE9**:  Reserves increase by 3 months of interest when a loan is kicked
            increaseInReserves += Maths.wmul(borrowerDebt, Maths.wdiv(interestRate, 4 * 1e18));

            _fenwickRemove(depositBeforeAction - depositAfterAction, bucketIndex_);

        } catch (bytes memory err) {
            _ensurePoolError(err);
        }
    }

    function _withdrawBonds(
        address kicker_,
        uint256 maxAmount_
    ) internal useTimestamps updateLocalStateAndPoolInterest {

        try _pool.withdrawBonds(kicker_, maxAmount_) {

        } catch (bytes memory err) {
            _ensurePoolError(err);
        }
    }

    /******************************/
    /*** Taker Helper Functions ***/
    /******************************/

    function _takeAuction(
        address borrower_,
        uint256 amount_,
        address taker_
    ) internal useTimestamps updateLocalStateAndPoolInterest {
        numberOfCalls['UBLiquidationHandler.takeAuction']++;

        (uint256 borrowerDebt, , )         = _poolInfo.borrowerInfo(address(_pool), borrower_);
        (address kicker, , , , , , , , , ) = _pool.auctionInfo(borrower_);

        uint256 totalBondBeforeTake = _getKickerBond(kicker);
        
        try _pool.take(borrower_, amount_, taker_, bytes("")) {

            uint256 totalBondAfterTake = _getKickerBond(kicker);

            if (totalBondBeforeTake > totalBondAfterTake) {
                // **RE7**: Reserves increase by bond penalty on take.
                increaseInReserves += totalBondBeforeTake - totalBondAfterTake;
            } else {
                // **RE7**: Reserves decrease by bond reward on take.
                decreaseInReserves += totalBondAfterTake - totalBondBeforeTake;
            }

            _updateCurrentTakeState(borrower_, borrowerDebt);

        } catch (bytes memory err) {
            _ensurePoolError(err);
        }
    }

    function _bucketTake(
        address taker_,
        address borrower_,
        bool depositTake_,
        uint256 bucketIndex_
    ) internal useTimestamps updateLocalStateAndPoolInterest {
        numberOfCalls['UBLiquidationHandler.bucketTake']++;

        (uint256 borrowerDebt, , ) = _poolInfo.borrowerInfo(address(_pool), borrower_);

        (address kicker, , , , , , , , , )     = _pool.auctionInfo(borrower_);
        (uint256 kickerLpsBeforeTake, )        = _pool.lenderInfo(bucketIndex_, kicker);
        (uint256 takerLpsBeforeTake, )         = _pool.lenderInfo(bucketIndex_, _actor);
        ( , , , uint256 depositBeforeAction, ) = _pool.bucketInfo(bucketIndex_);

        uint256 totalBondBeforeTake = _getKickerBond(kicker);

        try _pool.bucketTake(borrower_, depositTake_, bucketIndex_) {

            (uint256 kickerLpsAfterTake, )        = _pool.lenderInfo(bucketIndex_, kicker);
            (uint256 takerLpsAfterTake, )         = _pool.lenderInfo(bucketIndex_, _actor);
            ( , , , uint256 depositAfterAction, ) = _pool.bucketInfo(bucketIndex_);

            // **B7**: when awarded bucket take LPs : taker deposit time = timestamp of block when award happened
            if (takerLpsAfterTake > takerLpsBeforeTake) lenderDepositTime[taker_][bucketIndex_] = block.timestamp;

            if (kickerLpsAfterTake > kickerLpsBeforeTake) {
                // **B7**: when awarded bucket take LPs : kicker deposit time = timestamp of block when award happened
                lenderDepositTime[kicker][bucketIndex_] = block.timestamp;
            } else {
                // **RE7**: Reserves increase by bond penalty on take.
                increaseInReserves += _getKickerBond(kicker) - totalBondBeforeTake;
            }

            // **R7**: Exchange rates are unchanged under depositTakes
            // **R8**: Exchange rates are unchanged under arbTakes
            exchangeRateShouldNotChange[bucketIndex_] = true;

            _fenwickRemove(depositBeforeAction - depositAfterAction, bucketIndex_);

            _updateCurrentTakeState(borrower_, borrowerDebt);

        } catch (bytes memory err) {
            _ensurePoolError(err);
        }
    }

    /********************************/
    /*** Settler Helper Functions ***/
    /********************************/

    function _settleAuction(
        address borrower_,
        uint256 maxDepth_
    ) internal useTimestamps updateLocalStateAndPoolInterest {
        (
            uint256 borrowerT0Debt,
            uint256 collateral,
        ) = _pool.borrowerInfo(borrower_);
        (uint256 reservesBeforeAction, , , , )= _poolInfo.poolReservesInfo(address(_pool));

        try _pool.settle(borrower_, maxDepth_) {

            (uint256 inflator, ) = _pool.inflatorInfo();
            uint256 depositUsed;

            // settle borrower debt with exchanging borrower collateral with quote tokens starting from hpb
            while (maxDepth_ != 0 && borrowerT0Debt != 0 && collateral != 0) {
                uint256 bucketIndex       = fenwickIndexForSum(1 + depositUsed);
                uint256 maxSettleableDebt = Maths.wmul(collateral, _priceAt(bucketIndex));

                if (bucketIndex != MAX_FENWICK_INDEX) {
                    // debt is greater than bucket deposit then exchange all deposit with collateral
                    if (Maths.wmul(borrowerT0Debt, inflator) > fenwickDeposits[bucketIndex] && maxSettleableDebt >= fenwickDeposits[bucketIndex]) {
                        borrowerT0Debt              -= Maths.wdiv(fenwickDeposits[bucketIndex], inflator);
                        collateral                  -= Maths.wdiv(fenwickDeposits[bucketIndex], _priceAt(bucketIndex));
                        depositUsed                 += fenwickDeposits[bucketIndex];
                        fenwickDeposits[bucketIndex] = 0;
                    }
                    // collateral value is greater than borrower debt then exchange collateral with deposit
                    else if (maxSettleableDebt >= Maths.wmul(borrowerT0Debt, inflator)) {
                        fenwickDeposits[bucketIndex] -= Maths.wmul(borrowerT0Debt, inflator);
                        collateral                   -= Maths.wdiv(Maths.wmul(borrowerT0Debt, inflator), _priceAt(bucketIndex));
                        depositUsed                  += Maths.wmul(borrowerT0Debt, inflator);
                        borrowerT0Debt               = 0;
                    }
                    // exchange all collateral with deposit
                    else {
                        fenwickDeposits[bucketIndex] -= maxSettleableDebt;
                        depositUsed                  += maxSettleableDebt;
                        collateral                   = 0;
                        borrowerT0Debt               -= Maths.wdiv(maxSettleableDebt, inflator);
                    }
                } else collateral = 0;

                maxDepth_ -= 1;
            }

            // if collateral becomes 0 and still debt is left, settle debt by reserves and hpb making buckets bankrupt
            if (borrowerT0Debt != 0 && collateral == 0) {

                (uint256 reservesAfterAction, , , , )= _poolInfo.poolReservesInfo(address(_pool));
                // **RE12**: Reserves decrease by amount of reserve used to settle a auction
                decreaseInReserves = reservesBeforeAction - reservesAfterAction;

                borrowerT0Debt -= Maths.min(decreaseInReserves, borrowerT0Debt);

                while (maxDepth_ != 0 && borrowerT0Debt != 0) {
                    uint256 bucketIndex = fenwickIndexForSum(1 + depositUsed);

                    if (bucketIndex != MAX_FENWICK_INDEX) {
                        // debt is greater than bucket deposit
                        if (Maths.wmul(borrowerT0Debt, inflator) > (fenwickDeposits[bucketIndex])) {
                            borrowerT0Debt              -= Maths.wdiv(fenwickDeposits[bucketIndex], inflator);
                            depositUsed                 += fenwickDeposits[bucketIndex];
                            fenwickDeposits[bucketIndex] = 0;
                        }
                        // bucket deposit is greater than debt
                        else {
                            fenwickDeposits[bucketIndex] -= Maths.wmul(borrowerT0Debt, inflator);
                            depositUsed                  += Maths.wmul(borrowerT0Debt, inflator);
                            borrowerT0Debt               = 0;
                        }
                    }

                    maxDepth_ -= 1;
                }
            }

        } catch (bytes memory err) {
            _ensurePoolError(err);
        }
    }
}
