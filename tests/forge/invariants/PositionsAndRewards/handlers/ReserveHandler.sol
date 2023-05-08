// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.14;

import { Maths } from 'src/libraries/internal/Maths.sol';

import { UnboundedReservePoolHandler } from './unbounded/UnboundedReservePoolHandler.sol';
import { PositionsHandler }            from './PositionsHandler.sol';

contract ReserveHandler is UnboundedReservePoolHandler, PositionsHandler { 



    constructor(
        address positions_,
        address pool_,
        address ajna_,
        address quote_,
        address collateral_,
        address poolInfo_,
        uint256 numOfActors_,
        address testContract_
    ) PositionsHandler(positions_, pool_, ajna_, quote_, collateral_, poolInfo_, numOfActors_, testContract_) {}

    /*******************************/
    /*** Reserves Test Functions ***/
    /*******************************/

    function kickReserveAuction(
        uint256 actorIndex_,
        uint256 skippedTime_
    ) external useRandomActor(actorIndex_) useTimestamps skipTime(skippedTime_) {
        numberOfCalls['BReserveHandler.kickReserves']++;
        // Action phase
        _kickReserveAuction();
    }

    function takeReserves(
        uint256 actorIndex_,
        uint256 amountToTake_,
        uint256 skippedTime_
    ) external useRandomActor(actorIndex_) useTimestamps skipTime(skippedTime_) {
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
        skip(24 hours);

        (, , claimableReservesRemaining, , ) = _poolInfo.poolReservesInfo(address(_pool));
        boundedAmount_ = constrictToRange(amountToTake_, 0, Maths.min(MIN_QUOTE_AMOUNT, claimableReservesRemaining));
    }

}