// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.14;

import { ERC20Pool }                         from 'src/ERC20Pool.sol';
import { ERC20PoolFactory }                  from 'src/ERC20PoolFactory.sol';
import { PoolInfoUtils }                     from 'src/PoolInfoUtils.sol';
import { _borrowFeeRate, _depositFeeRate }   from 'src/libraries/helpers/PoolHelper.sol';
import { Maths }                             from "src/libraries/internal/Maths.sol";

import { UnboundedBasicPoolHandler } from "../../../base/handlers/unbounded/UnboundedBasicPoolHandler.sol";
import { BaseERC20PoolHandler }      from './BaseERC20PoolHandler.sol';

/**
 *  @dev this contract manages multiple lenders
 *  @dev methods in this contract are called in random order
 *  @dev randomly selects a lender contract to make a txn
 */ 
abstract contract UnboundedBasicERC20PoolHandler is UnboundedBasicPoolHandler, BaseERC20PoolHandler {

    /*******************************/
    /*** Lender Helper Functions ***/
    /*******************************/

    function _addCollateral(
        uint256 amount_,
        uint256 bucketIndex_
    ) internal updateLocalStateAndPoolInterest {
        numberOfCalls['UBBasicHandler.addCollateral']++;

        (uint256 lpBalanceBeforeAction, ) = _erc20Pool.lenderInfo(bucketIndex_, _actor);

        try _erc20Pool.addCollateral(amount_, bucketIndex_, block.timestamp + 1 minutes) {
            // **B5**: when adding collateral: lender deposit time = timestamp of block when deposit happened
            lenderDepositTime[_actor][bucketIndex_] = block.timestamp;
            // **R5**: Exchange rates are unchanged by adding collateral token into a bucket
            exchangeRateShouldNotChange[bucketIndex_] = true;

            // Post action condition
            (uint256 lpBalanceAfterAction, ) = _erc20Pool.lenderInfo(bucketIndex_, _actor);
            require(lpBalanceAfterAction > lpBalanceBeforeAction, "LP balance should increase");
        } catch (bytes memory err) {
            _ensurePoolError(err);
        }
    }

    function _removeCollateral(
        uint256 amount_,
        uint256 bucketIndex_
    ) internal updateLocalStateAndPoolInterest {
        numberOfCalls['UBBasicHandler.removeCollateral']++;

        (uint256 lpBalanceBeforeAction, ) = _erc20Pool.lenderInfo(bucketIndex_, _actor);

        try _erc20Pool.removeCollateral(amount_, bucketIndex_) {

            // **R6**: Exchange rates are unchanged by removing collateral token from a bucket
            exchangeRateShouldNotChange[bucketIndex_] = true;

            // Post action condition
            (uint256 lpBalanceAfterAction, ) = _erc20Pool.lenderInfo(bucketIndex_, _actor);
            require(lpBalanceAfterAction < lpBalanceBeforeAction, "LP balance should decrease");

        } catch (bytes memory err) {
            _ensurePoolError(err);
        }
    }

    /*********************************/
    /*** Borrower Helper Functions ***/
    /*********************************/

    function _pledgeCollateral(
        uint256 amount_
    ) internal updateLocalStateAndPoolInterest {
        numberOfCalls['UBBasicHandler.pledgeCollateral']++;

        // **R1**: Exchange rates are unchanged by pledging collateral
        for (uint256 bucketIndex = LENDER_MIN_BUCKET_INDEX; bucketIndex <= LENDER_MAX_BUCKET_INDEX; bucketIndex++) {
            exchangeRateShouldNotChange[bucketIndex] = true;
        }

        try _erc20Pool.drawDebt(_actor, 0, 0, amount_) {
        } catch (bytes memory err) {
            _ensurePoolError(err);
        }
    }

    function _pullCollateral(
        uint256 amount_
    ) internal updateLocalStateAndPoolInterest {
        numberOfCalls['UBBasicHandler.pullCollateral']++;

        // **R2**: Exchange rates are unchanged by pulling collateral
        for (uint256 bucketIndex = LENDER_MIN_BUCKET_INDEX; bucketIndex <= LENDER_MAX_BUCKET_INDEX; bucketIndex++) {
            exchangeRateShouldNotChange[bucketIndex] = true;
        }

        try _erc20Pool.repayDebt(_actor, 0, amount_, _actor, 7388) {

        } catch (bytes memory err) {
            _ensurePoolError(err);
        }
    }
 
    function _drawDebt(
        uint256 amount_
    ) internal virtual override updateLocalStateAndPoolInterest {
        numberOfCalls['UBBasicHandler.drawDebt']++;

        (uint256 poolDebt, , , ) = _erc20Pool.debtInfo();

        // find bucket to borrow quote token
        uint256 bucket = _erc20Pool.depositIndex(amount_ + poolDebt) - 1;
        uint256 price = _poolInfo.indexToPrice(bucket);
        uint256 collateralToPledge = ((amount_ * 1e18 + price / 2) / price) * 101 / 100 + 1;

        try _erc20Pool.drawDebt(_actor, amount_, 7388, collateralToPledge) {

            (uint256 interestRate, ) = _erc20Pool.interestRateInfo();

            // **RE10**: Reserves increase by origination fee: max(1 week interest, 0.05% of borrow amount), on draw debt
            increaseInReserves += Maths.wmul(
                amount_, _borrowFeeRate(interestRate)
            );

        } catch (bytes memory err) {
            _ensurePoolError(err);
        }
    }

    function _repayDebt(
        uint256 amountToRepay_
    ) internal updateLocalStateAndPoolInterest {
        numberOfCalls['UBBasicHandler.repayDebt']++;

        try _erc20Pool.repayDebt(_actor, amountToRepay_, 0, _actor, 7388) {

        } catch (bytes memory err) {
            _ensurePoolError(err);
        }
    }
}
