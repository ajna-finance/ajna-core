// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.18;

import {
    _depositFeeRate,
    _roundToScale
}                   from 'src/libraries/helpers/PoolHelper.sol';
import { Maths }    from "src/libraries/internal/Maths.sol";

import { BaseHandler } from './BaseHandler.sol';

/**
 *  @dev this contract manages multiple lenders
 *  @dev methods in this contract are called in random order
 *  @dev randomly selects a lender contract to make a txn
 */ 
abstract contract UnboundedBasicPoolHandler is BaseHandler {

    /*******************************/
    /*** Lender Helper Functions ***/
    /*******************************/

    function _addQuoteToken(
        uint256 amount_,
        uint256 bucketIndex_
    ) internal updateLocalStateAndPoolInterest {
        numberOfCalls['UBBasicHandler.addQuoteToken']++;

        (uint256 lpBalanceBeforeAction, ) = _pool.lenderInfo(bucketIndex_, _actor);

        (uint256 inflator, )     = _pool.inflatorInfo();
        uint256 poolDebt         = Maths.wmul(_pool.totalT0Debt(), inflator);
        uint256 lupIndex         = _pool.depositIndex(poolDebt);
        (uint256 interestRate, ) = _pool.interestRateInfo();

        // ensure actor always has amount of quote to add
        _ensureQuoteAmount(_actor, amount_);

        try _pool.addQuoteToken(amount_, bucketIndex_, block.timestamp + 1 minutes, false) {

            // amount is rounded in pool to token scale
            amount_ = _roundToScale(amount_, _pool.quoteTokenScale());
        
            // **B5**: when adding quote tokens: lender deposit time  = timestamp of block when deposit happened
            lenderDepositTime[_actor][bucketIndex_] = block.timestamp;
            // **R3**: Exchange rates are unchanged by depositing quote token into a bucket
            exchangeRateShouldNotChange[bucketIndex_] = true;

            bool depositBelowLup = lupIndex != 0 && bucketIndex_ > lupIndex;
            if (depositBelowLup) {
                uint256 intialAmount = amount_;
                amount_ = Maths.wmul(
                    amount_,
                    Maths.WAD - _depositFeeRate(interestRate)
                );
                // **RE3**: Reserves increase only when depositing quote token into a bucket below LUP
                increaseInReserves += intialAmount - amount_;
            }

            _fenwickAdd(amount_, bucketIndex_);

            // Post action condition
            (uint256 lpBalanceAfterAction, ) = _pool.lenderInfo(bucketIndex_, _actor);
            require(lpBalanceAfterAction > lpBalanceBeforeAction, "LP balance should increase");

        } catch (bytes memory err) {
            _ensurePoolError(err);
        }
    }

    function _removeQuoteToken(
        uint256 amount_,
        uint256 bucketIndex_
    ) internal updateLocalStateAndPoolInterest {
        numberOfCalls['UBBasicHandler.removeQuoteToken']++;

        (uint256 lpBalanceBeforeAction, ) = _pool.lenderInfo(bucketIndex_, _actor);

        ( , , , uint256 deposit, ) = _pool.bucketInfo(bucketIndex_);
        fenwickDeposits[bucketIndex_] = deposit;

        try _pool.removeQuoteToken(amount_, bucketIndex_) returns (uint256 removedAmount_, uint256) {
            // **R4**: Exchange rates are unchanged by withdrawing deposit (quote token) from a bucket
            exchangeRateShouldNotChange[bucketIndex_] = true;

            _fenwickRemove(removedAmount_, bucketIndex_);

            // rounding in favour of pool goes to reserves
            increaseInReserves += removedAmount_ - _roundToScale(removedAmount_, _pool.quoteTokenScale());

            // Post action condition
            (uint256 lpBalanceAfterAction, ) = _pool.lenderInfo(bucketIndex_, _actor);
            require(lpBalanceAfterAction < lpBalanceBeforeAction, "LP balance should decrease");

        } catch (bytes memory err) {
            _ensurePoolError(err);
        }
    }

    function _moveQuoteToken(
        uint256 amount_,
        uint256 fromIndex_,
        uint256 toIndex_
    ) internal updateLocalStateAndPoolInterest {
        numberOfCalls['UBBasicHandler.moveQuoteToken']++;

        ( , , , uint256 fromDeposit, ) = _pool.bucketInfo(fromIndex_);
        fenwickDeposits[fromIndex_] = fromDeposit;

        try _pool.moveQuoteToken(
            amount_,
            fromIndex_,
            toIndex_,
            block.timestamp + 1 minutes,
            false
        ) returns (uint256, uint256, uint256 movedAmount_) {

            (, uint256 fromBucketDepositTime) = _pool.lenderInfo(fromIndex_, _actor);
            (, uint256 toBucketDepositTime)   = _pool.lenderInfo(toIndex_,    _actor);
            
            // **B5**: when moving quote tokens: lender deposit time = timestamp of block when move happened
            lenderDepositTime[_actor][toIndex_] = Maths.max(fromBucketDepositTime, toBucketDepositTime);
            // **RE3**: Reserves increase only when moving quote tokens into a bucket below LUP.
            // movedAmount_ can be greater than amount_ in case when bucket gets empty by moveQuoteToken
            if (amount_ > movedAmount_) increaseInReserves += amount_ - movedAmount_;

            _fenwickRemove(amount_, fromIndex_);
            _fenwickAdd(movedAmount_, toIndex_);

        } catch (bytes memory err) {
            _ensurePoolError(err);
        }
    }

    function _increaseLPAllowance(
        address receiver_,
        uint256 bucketIndex_,
        uint256 amount_
    ) internal updateLocalStateAndPoolInterest {
        numberOfCalls['UBBasicHandler.increaseLPAllowance']++;

        // approve as transferor
        address[] memory transferors = new address[](1);
        transferors[0] = receiver_;
        _pool.approveLPTransferors(transferors);

        uint256[] memory buckets = new uint256[](1);
        buckets[0] = bucketIndex_;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = amount_;
        _pool.increaseLPAllowance(receiver_, buckets, amounts);
    }

    function _transferLps(
        address sender_,
        address receiver_,
        uint256 bucketIndex_
    ) internal updateLocalStateAndPoolInterest {
        numberOfCalls['UBBasicHandler.transferLps']++;

        uint256[] memory buckets = new uint256[](1);
        buckets[0] = bucketIndex_;

        changePrank(receiver_);

        try _pool.transferLP(sender_, receiver_, buckets) {

            (, uint256 senderDepositTime)   = _pool.lenderInfo(bucketIndex_, sender_);
            (, uint256 receiverDepositTime) = _pool.lenderInfo(bucketIndex_, receiver_);

            // **B6**: when receiving transferred LP : receiver deposit time (`Lender.depositTime`) = max of sender and receiver deposit time
            lenderDepositTime[receiver_][bucketIndex_] = Maths.max(senderDepositTime, receiverDepositTime);

        } catch (bytes memory err) {
            _ensurePoolError(err);
        }
    }

    function _stampLoan() internal updateLocalStateAndPoolInterest {
        numberOfCalls['UBBasicHandler.stampLoan']++;
        try _pool.stampLoan() {
        } catch (bytes memory err) {
            _ensurePoolError(err);
        }
    }

    function _drawDebt(
        uint256 amount_
    ) internal virtual;
}
