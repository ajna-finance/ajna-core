// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.14;

import { Maths } from 'src/libraries/internal/Maths.sol';

import { BaseHandler } from './BaseHandler.sol';

abstract contract UnboundedLiquidationPoolHandler is BaseHandler {

    /*******************************/
    /*** Kicker Helper Functions ***/
    /*******************************/

    function _kickAuction(
        address borrower_
    ) internal updateLocalStateAndPoolInterest {
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
    ) internal updateLocalStateAndPoolInterest {
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
    ) internal updateLocalStateAndPoolInterest {

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
    ) internal updateLocalStateAndPoolInterest {
        numberOfCalls['UBLiquidationHandler.takeAuction']++;

        (address kicker, , , , , , , , , ) = _pool.auctionInfo(borrower_);

        (uint256 borrowerDebtBeforeTake, , ) = _poolInfo.borrowerInfo(address(_pool), borrower_);
        uint256 totalBondBeforeTake          = _getKickerBond(kicker);
        uint256 totalBalanceBeforeTake       = _quote.balanceOf(address(_pool)) * 10**(18 - _quote.decimals());
        
        try _pool.take(borrower_, amount_, taker_, bytes("")) {

            (uint256 borrowerDebtAfterTake, , ) = _poolInfo.borrowerInfo(address(_pool), borrower_);
            uint256 totalBondAfterTake          = _getKickerBond(kicker);
            uint256 totalBalanceAfterTake       = _quote.balanceOf(address(_pool)) * 10**(18 - _quote.decimals());

            if (borrowerDebtBeforeTake > borrowerDebtAfterTake) {
                // **RE7**: Reserves decrease with debt covered by take.
                decreaseInReserves += borrowerDebtBeforeTake - borrowerDebtAfterTake;
            } else {
                // **RE7**: Reserves increase by take penalty on first take.
                increaseInReserves += borrowerDebtAfterTake - borrowerDebtBeforeTake;
            }

            if (totalBondBeforeTake > totalBondAfterTake) {
                // **RE7**: Reserves increase by bond penalty on take.
                increaseInReserves += totalBondBeforeTake - totalBondAfterTake;
            } else {
                // **RE7**: Reserves decrease by bond reward on take.
                decreaseInReserves += totalBondAfterTake - totalBondBeforeTake;
            }

            // **RE7**: Reserves increase with the quote token paid by taker.
            increaseInReserves += totalBalanceAfterTake - totalBalanceBeforeTake;

            if (!alreadyTaken[borrower_]) {
                alreadyTaken[borrower_] = true;

                firstTake = true;

            } else firstTake = false;

            // reset taken flag in case auction was settled by take action
            _auctionSettleStateReset(borrower_);

        } catch (bytes memory err) {
            _ensurePoolError(err);
        }
    }

    function _bucketTake(
        address taker_,
        address borrower_,
        bool depositTake_,
        uint256 bucketIndex_
    ) internal updateLocalStateAndPoolInterest {
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

            // **B7**: when awarded bucket take LP : taker deposit time = timestamp of block when award happened
            if (takerLpsAfterTake > takerLpsBeforeTake) lenderDepositTime[taker_][bucketIndex_] = block.timestamp;

            if (kickerLpsAfterTake > kickerLpsBeforeTake) {
                // **B7**: when awarded bucket take LP : kicker deposit time = timestamp of block when award happened
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

}
