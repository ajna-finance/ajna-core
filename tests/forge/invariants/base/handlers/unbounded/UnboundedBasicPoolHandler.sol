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

        // ensure actor always has amount of quote to add
        _ensureQuoteAmount(_actor, amount_);

        LenderInfo memory lenderInfoBeforeAdd = _getLenderInfo(bucketIndex_, _actor);

        try _pool.addQuoteToken(
            amount_,
            bucketIndex_,
            block.timestamp + 1 minutes
        ) returns (uint256, uint256 addedAmount_) {
            // amount is rounded in pool to token scale
            amount_ = _roundToScale(amount_, _pool.quoteTokenScale());

            // **RE3**: Reserves increase when depositing quote token
            increaseInReserves += amount_ - addedAmount_;
        
            // **B5**: when adding quote tokens: lender deposit time  = timestamp of block when deposit happened
            lenderDepositTime[_actor][bucketIndex_] = block.timestamp;

            // **R3**: Exchange rates are unchanged by depositing quote token into a bucket
            exchangeRateShouldNotChange[bucketIndex_] = true;

            _fenwickAdd(addedAmount_, bucketIndex_);

            LenderInfo memory lenderInfoAfterAdd = _getLenderInfo(bucketIndex_, _actor);
            // Post action condition
            require(
                lenderInfoAfterAdd.lpBalance > lenderInfoBeforeAdd.lpBalance,
                "LP balance should increase"
            );
        } catch (bytes memory err) {
            _ensurePoolError(err);
        }
    }

    function _removeQuoteToken(
        uint256 amount_,
        uint256 bucketIndex_
    ) internal updateLocalStateAndPoolInterest {
        numberOfCalls['UBBasicHandler.removeQuoteToken']++;

        // record fenwick tree state before action
        fenwickDeposits[bucketIndex_] = _getBucketInfo(bucketIndex_).deposit;

        LenderInfo memory lenderInfoBeforeRemove = _getLenderInfo(bucketIndex_, _actor);

        try _pool.removeQuoteToken(
            amount_,
            bucketIndex_
        ) returns (uint256 removedAmount_, uint256) {
            // **R4**: Exchange rates are unchanged by withdrawing deposit (quote token) from a bucket
            exchangeRateShouldNotChange[bucketIndex_] = true;

            _fenwickRemove(removedAmount_, bucketIndex_);

            // rounding in favour of pool goes to reserves
            increaseInReserves += removedAmount_ - _roundToScale(removedAmount_, _pool.quoteTokenScale());

            LenderInfo memory lenderInfoAfterRemove = _getLenderInfo(bucketIndex_, _actor);
            // Post action condition
            require(
                lenderInfoAfterRemove.lpBalance < lenderInfoBeforeRemove.lpBalance,
                "LP balance should decrease"
            );
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

        // record fenwick tree state before action
        fenwickDeposits[fromIndex_] = _getBucketInfo(fromIndex_).deposit;

        try _pool.moveQuoteToken(
            amount_,
            fromIndex_,
            toIndex_,
            block.timestamp + 1 minutes
        ) returns (uint256, uint256, uint256 movedAmount_) {
            // **B5**: when moving quote tokens: lender deposit time = timestamp of block when move happened
            lenderDepositTime[_actor][toIndex_] = Maths.max(
                _getLenderInfo(fromIndex_, _actor).depositTime,
                _getLenderInfo(toIndex_, _actor).depositTime
            );

            // **RE3**: Reserves increase only when moving quote tokens into a lower-priced bucket
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

        _pool.increaseLPAllowance(
            receiver_,
            buckets,
            amounts
        );
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

        try _pool.transferLP(
            sender_,
            receiver_,
            buckets
        ) {
            // **B6**: when receiving transferred LP : receiver deposit time (`Lender.depositTime`) = max of sender and receiver deposit time
            lenderDepositTime[receiver_][bucketIndex_] = Maths.max(
                _getLenderInfo(bucketIndex_, sender_).depositTime,
                _getLenderInfo(bucketIndex_, receiver_).depositTime
            );
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
