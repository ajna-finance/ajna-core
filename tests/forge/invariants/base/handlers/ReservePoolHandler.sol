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

        // take all reserves if available
        (, , uint256 claimableReservesRemaining, , ) = _poolInfo.poolReservesInfo(address(_pool));
        _takeReserves(claimableReservesRemaining);

        // Action phase
        _kickReserveAuction();
    }

    function takeReserves(
        uint256 actorIndex_,
        uint256 amountToTake_,
        uint256 skippedTime_
    ) external useRandomActor(actorIndex_) useTimestamps skipTime(skippedTime_) writeLogs {
        numberOfCalls['BReserveHandler.takeReserves']++; 

        // kick reserve auction if claimable reserves available
        (, uint256 claimableReserves, , , ) = _poolInfo.poolReservesInfo(address(_pool));
        if (claimableReserves != 0) {
            _kickReserveAuction();
        }

        // take reserve auction if remaining claimable reserves
        (, , uint256 claimableReservesRemaining, , ) = _poolInfo.poolReservesInfo(address(_pool));
        if (claimableReservesRemaining != 0) {
            uint256 boundedAmount = constrictToRange(amountToTake_, claimableReservesRemaining / 2, claimableReservesRemaining);
            _takeReserves(boundedAmount);
        }
    }
}