// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.18;

import { Maths } from 'src/libraries/internal/Maths.sol';

import { UnboundedReservePoolHandler } from '../../base/handlers/unbounded/UnboundedReservePoolHandler.sol';
import { LiquidationPoolHandler }      from './LiquidationPoolHandler.sol';

abstract contract ReservePoolHandler is UnboundedReservePoolHandler, LiquidationPoolHandler {

    /*******************************/
    /*** Reserves Test Functions ***/
    /*******************************/

    function kickReserveAuction(
        uint256 actorIndex_,
        uint256 skippedTime_
    ) external useRandomActor(actorIndex_) useTimestamps skipTime(skippedTime_) writeLogs {
        numberOfCalls['BReserveHandler.kickReserveAuction']++;

        // Action phase
        _kickReserveAuction();
    }

    function takeReserves(
        uint256 actorIndex_,
        uint256 amountToTake_,
        uint256 skippedTime_
    ) external useRandomActor(actorIndex_) useTimestamps skipTime(skippedTime_) writeLogs {
        numberOfCalls['BReserveHandler.takeReserves']++;

        // Prepare test phase
        uint256 boundedAmount = _preTakeReserves(amountToTake_);

        // Action phase
        _takeReserves(boundedAmount);
    }

    /*******************************/
    /*** Prepare Tests Functions ***/
    /*******************************/

    function _preTakeReserves(
        uint256 amountToTake_
    ) internal returns (uint256 boundedAmount_) {
        (, , uint256 claimableReservesRemaining, , ) = _poolInfo.poolReservesInfo(address(_pool));
        if (claimableReservesRemaining == 0) _kickReserveAuction();

        // skip enough time for auction price to decrease
        skip(_getKickReserveTime());

        (, , claimableReservesRemaining, , ) = _poolInfo.poolReservesInfo(address(_pool));
        boundedAmount_ = constrictToRange(amountToTake_, 0, Maths.min(MIN_QUOTE_AMOUNT, claimableReservesRemaining));
    }

}