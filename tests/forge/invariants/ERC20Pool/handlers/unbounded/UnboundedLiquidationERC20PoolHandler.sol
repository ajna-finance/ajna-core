// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.14;

import { _priceAt }          from 'src/libraries/helpers/PoolHelper.sol';
import { MAX_FENWICK_INDEX } from 'src/libraries/helpers/PoolHelper.sol';
import { Maths }             from "src/libraries/internal/Maths.sol";

import { UnboundedLiquidationPoolHandler } from '../../../base/handlers/unbounded/UnboundedLiquidationPoolHandler.sol';
import { BaseERC20PoolHandler }            from './BaseERC20PoolHandler.sol';

abstract contract UnboundedLiquidationERC20PoolHandler is UnboundedLiquidationPoolHandler, BaseERC20PoolHandler {

    /********************************/
    /*** Settler Helper Functions ***/
    /********************************/

    function _settleAuction(
        address borrower_,
        uint256 maxDepth_
    ) internal updateLocalStateAndPoolInterest {
        (
            uint256 borrowerT0Debt,
            uint256 collateral,
        ) = _erc20Pool.borrowerInfo(borrower_);
        (uint256 reservesBeforeAction, , , , )= _poolInfo.poolReservesInfo(address(_pool));
        (uint256 inflator, ) = _erc20Pool.inflatorInfo();

        try _erc20Pool.settle(borrower_, maxDepth_) {

            // settle borrower debt with exchanging borrower collateral with quote tokens starting from hpb
            while (maxDepth_ != 0 && borrowerT0Debt != 0 && collateral != 0) {
                uint256 bucketIndex       = fenwickIndexForSum(1);
                uint256 maxSettleableDebt = Maths.wmul(collateral, _priceAt(bucketIndex));
                uint256 fenwickDeposit    = fenwickDeposits[bucketIndex];
                uint256 borrowerDebt      = Maths.wmul(borrowerT0Debt, inflator);

                if (bucketIndex != MAX_FENWICK_INDEX) {
                    // enough deposit in bucket and collateral avail to settle entire debt
                    if (fenwickDeposit >= borrowerDebt && maxSettleableDebt >= borrowerDebt) {
                        fenwickDeposits[bucketIndex] -= borrowerDebt;
                        collateral                   -= Maths.wdiv(borrowerDebt, _priceAt(bucketIndex));
                        borrowerT0Debt               = 0;
                    }
                    // enough collateral, therefore not enough deposit to settle entire debt, we settle only deposit amount
                    else if (maxSettleableDebt >= fenwickDeposit) {
                        fenwickDeposits[bucketIndex] = 0;
                        collateral                   -= Maths.wdiv(fenwickDeposit, _priceAt(bucketIndex));
                        borrowerT0Debt               -= Maths.wdiv(fenwickDeposit, inflator);
                    }
                    // exchange all collateral with deposit
                    else {
                        fenwickDeposits[bucketIndex] -= maxSettleableDebt;
                        collateral                   = 0;
                        borrowerT0Debt               -= Maths.wdiv(maxSettleableDebt, inflator);
                    }
                } else collateral = 0;

                maxDepth_ -= 1;
            }

            // if collateral becomes 0 and still debt is left, settle debt by reserves and hpb making buckets bankrupt
            if (borrowerT0Debt != 0 && collateral == 0) {

                (uint256 reservesAfterAction, , , , )= _poolInfo.poolReservesInfo(address(_pool));
                if (reservesBeforeAction > reservesAfterAction) {
                    // **RE12**: Reserves decrease by amount of reserve used to settle a auction
                    decreaseInReserves = reservesBeforeAction - reservesAfterAction;
                } else {
                    // Reserves might increase upto 2 WAD due to rounding issue
                    increaseInReserves = reservesAfterAction - reservesBeforeAction;
                }
                borrowerT0Debt -= Maths.min(Maths.wdiv(decreaseInReserves, inflator), borrowerT0Debt);

                while (maxDepth_ != 0 && borrowerT0Debt != 0) {
                    uint256 bucketIndex    = fenwickIndexForSum(1);
                    uint256 fenwickDeposit = fenwickDeposits[bucketIndex];
                    uint256 borrowerDebt   = Maths.wmul(borrowerT0Debt, inflator);

                    if (bucketIndex != MAX_FENWICK_INDEX) {
                        // debt is greater than bucket deposit
                        if (borrowerDebt > fenwickDeposit) {
                            fenwickDeposits[bucketIndex] = 0;
                            borrowerT0Debt               -= Maths.wdiv(fenwickDeposit, inflator);
                        }
                        // bucket deposit is greater than debt
                        else {
                            fenwickDeposits[bucketIndex] -= borrowerDebt;
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
