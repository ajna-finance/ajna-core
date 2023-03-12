// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.14;

import { ERC20Pool }                         from 'src/ERC20Pool.sol';
import { ERC20PoolFactory }                  from 'src/ERC20PoolFactory.sol';
import { PoolInfoUtils }                     from 'src/PoolInfoUtils.sol';
import { _borrowFeeRate, _depositFeeRate }   from 'src/libraries/helpers/PoolHelper.sol';

import "src/libraries/internal/Maths.sol";

import {
    LENDER_MIN_BUCKET_INDEX,
    LENDER_MAX_BUCKET_INDEX,
    BORROWER_MIN_BUCKET_INDEX,
    BaseHandler
} from './BaseHandler.sol';

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
    ) internal useTimestamps resetAllPreviousLocalState {
        numberOfCalls['UBBasicHandler.addQuoteToken']++;

        // Pre condition
        (uint256 lpBalanceBeforeAction, ) = _pool.lenderInfo(bucketIndex_, _actor);
        (uint256 poolDebt, , )   = _pool.debtInfo();
        uint256 lupIndex         = _pool.depositIndex(poolDebt);
        (uint256 interestRate, ) = _pool.interestRateInfo();

        try _pool.addQuoteToken(amount_, bucketIndex_, block.timestamp + 1 minutes) {
        
            // lender's deposit time updates when lender adds Quote token into pool
            lenderDepositTime[_actor][bucketIndex_] = block.timestamp;

            // deposit fee is charged if deposit is added below lup
            bool depositBelowLup = lupIndex != 0 && bucketIndex_ > lupIndex;
            if (depositBelowLup) {
                uint256 intialAmount = amount_;
                amount_ = Maths.wmul(
                    amount_,
                    Maths.WAD - _depositFeeRate(interestRate)
                );
                increaseInReserves += intialAmount - amount_;
            }

            shouldExchangeRateChange = false;

            _fenwickAdd(amount_, bucketIndex_);

            // Post condition
            (uint256 lpBalanceAfterAction, ) = _pool.lenderInfo(bucketIndex_, _actor);
            require(lpBalanceAfterAction > lpBalanceBeforeAction, "LP balance should increase");

        } catch (bytes memory err) {
            _ensurePoolError(err);
        }
    }

    function _removeQuoteToken(
        uint256 amount_,
        uint256 bucketIndex_
    ) internal useTimestamps resetAllPreviousLocalState {
        numberOfCalls['UBBasicHandler.removeQuoteToken']++;

        // Pre condition
        (uint256 lpBalanceBeforeAction, ) = _pool.lenderInfo(bucketIndex_, _actor);

        try _pool.removeQuoteToken(amount_, bucketIndex_) returns (uint256 removedAmount_, uint256) {

            _fenwickRemove(removedAmount_, bucketIndex_);

            shouldExchangeRateChange = false;

            // Post condition
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
    ) internal useTimestamps resetAllPreviousLocalState {
        (uint256 lps, ) = _pool.lenderInfo(fromIndex_, _actor);

        // restrict amount to move by available deposit inside bucket
        uint256 availableDeposit = _poolInfo.lpsToQuoteTokens(address(_pool), lps, fromIndex_);
        amount_ = Maths.min(amount_, availableDeposit);

        try _pool.moveQuoteToken(
            amount_,
            fromIndex_,
            toIndex_,
            block.timestamp + 1 minutes
        ) returns (uint256, uint256, uint256 movedAmount_) {
            // remove initial amount from index
            _fenwickRemove(amount_, fromIndex_);

            // add moved amount to index (could be subject of deposit fee penalty)
            _fenwickAdd(movedAmount_, toIndex_);

            (, uint256 fromBucketDepositTime) = _pool.lenderInfo(fromIndex_, _actor);
            (, uint256 toBucketDepositTime)   = _pool.lenderInfo(toIndex_,    _actor);
            
            // lender's deposit time updates when lender moves Quote token from one bucket to another
            lenderDepositTime[_actor][toIndex_] = Maths.max(fromBucketDepositTime, toBucketDepositTime);

            shouldExchangeRateChange = false;

            increaseInReserves += amount_ - movedAmount_; // if amount subject of deposit fee then reserves should increase

        } catch (bytes memory err) {
            _ensurePoolError(err);
        }
    }

    function _addCollateral(
        uint256 amount_,
        uint256 bucketIndex_
    ) internal useTimestamps resetAllPreviousLocalState {
        numberOfCalls['UBBasicHandler.addCollateral']++;

        shouldExchangeRateChange = false;

        // Pre condition
        (uint256 lpBalanceBeforeAction, ) = _pool.lenderInfo(bucketIndex_, _actor);

        _pool.addCollateral(amount_, bucketIndex_, block.timestamp + 1 minutes);

        // lender's deposit time updates when lender adds collateral token into pool
        lenderDepositTime[_actor][bucketIndex_] = block.timestamp;

        // Post condition
        (uint256 lpBalanceAfterAction, ) = _pool.lenderInfo(bucketIndex_, _actor);
        require(lpBalanceAfterAction > lpBalanceBeforeAction, "LP balance should increase");
    }

    function _removeCollateral(
        uint256 amount_,
        uint256 bucketIndex_
    ) internal useTimestamps resetAllPreviousLocalState {
        numberOfCalls['UBBasicHandler.removeCollateral']++;

        (uint256 lpBalanceBeforeAction, ) = _pool.lenderInfo(bucketIndex_, _actor);

        try _pool.removeCollateral(amount_, bucketIndex_) {

            shouldExchangeRateChange = false;

            // Post condition
            (uint256 lpBalanceAfterAction, ) = _pool.lenderInfo(bucketIndex_, _actor);
            require(lpBalanceAfterAction < lpBalanceBeforeAction, "LP balance should decrease");

        } catch (bytes memory err) {
            _ensurePoolError(err);
        }
    }

    function _increaseLPsAllowance(
        address receiver_,
        uint256 bucketIndex_,
        uint256 amount_
    ) internal useTimestamps resetAllPreviousLocalState {
        // approve as transferor
        address[] memory transferors = new address[](1);
        transferors[0] = receiver_;
        _pool.approveLPsTransferors(transferors);

        uint256[] memory buckets = new uint256[](1);
        buckets[0] = bucketIndex_;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = amount_;
        _pool.increaseLPsAllowance(receiver_, buckets, amounts);
    }

    function _transferLps(
        address sender_,
        address receiver_,
        uint256 bucketIndex_
    ) internal useTimestamps resetAllPreviousLocalState {
        uint256[] memory buckets = new uint256[](1);
        buckets[0] = bucketIndex_;

        changePrank(receiver_);

        try _pool.transferLPs(sender_, receiver_, buckets) {

            shouldExchangeRateChange = false;

            (, uint256 senderDepositTime)   = _pool.lenderInfo(bucketIndex_, sender_);
            (, uint256 receiverDepositTime) = _pool.lenderInfo(bucketIndex_, receiver_);

            // receiver's deposit time updates when receiver receives lps
            lenderDepositTime[receiver_][bucketIndex_] = Maths.max(senderDepositTime, receiverDepositTime);

        } catch (bytes memory err) {
            _ensurePoolError(err);
        }
    }

    /*********************************/
    /*** Borrower Helper Functions ***/
    /*********************************/

    function _pledgeCollateral(
        uint256 amount_
    ) internal useTimestamps resetAllPreviousLocalState {
        numberOfCalls['UBBasicHandler.pledgeCollateral']++;

        _pool.drawDebt(_actor, 0, 0, amount_);   

        shouldExchangeRateChange = false;

    }

    function _pullCollateral(
        uint256 amount_
    ) internal useTimestamps resetAllPreviousLocalState {
        numberOfCalls['UBBasicHandler.pullCollateral']++;

        try _pool.repayDebt(_actor, 0, amount_, _actor, 7388) {

            shouldExchangeRateChange = false;

        } catch (bytes memory err) {
            _ensurePoolError(err);
        }
    }
 
    function _drawDebt(
        uint256 amount_
    ) internal useTimestamps resetAllPreviousLocalState {
        numberOfCalls['UBBasicHandler.drawDebt']++;

        (uint256 poolDebt, , ) = _pool.debtInfo();

        // find bucket to borrow quote token
        uint256 bucket = _pool.depositIndex(amount_ + poolDebt) - 1;
        uint256 price = _poolInfo.indexToPrice(bucket);
        uint256 collateralToPledge = ((amount_ * 1e18 + price / 2) / price) * 101 / 100 + 1;

        try _pool.drawDebt(_actor, amount_, 7388, collateralToPledge) {

            shouldExchangeRateChange = false;

            (uint256 interestRate, ) = _pool.interestRateInfo();

            // reserve should increase by origination fee on draw debt
            increaseInReserves += Maths.wmul(
                amount_, _borrowFeeRate(interestRate)
            );

        } catch (bytes memory err) {
            _ensurePoolError(err);
        }

        // skip to make borrower undercollateralize
        vm.warp(block.timestamp + 200 days);
    }

    function _repayDebt(
        uint256 amountToRepay_
    ) internal useTimestamps resetAllPreviousLocalState {
        numberOfCalls['UBBasicHandler.repayDebt']++;

        try _pool.repayDebt(_actor, amountToRepay_, 0, _actor, 7388) {

            shouldExchangeRateChange = false;

        } catch (bytes memory err) {
            _ensurePoolError(err);
        }
    }
}
