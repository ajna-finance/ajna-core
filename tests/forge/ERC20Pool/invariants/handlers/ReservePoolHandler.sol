// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.14;

import 'src/libraries/internal/Maths.sol';

import { UnboundedReservePoolHandler } from '../base/UnboundedReservePoolHandler.sol';

import { LiquidationPoolHandler } from './LiquidationPoolHandler.sol';

contract ReservePoolHandler is UnboundedReservePoolHandler, LiquidationPoolHandler {

    constructor(
        address pool_,
        address ajna_,
        address quote_,
        address collateral_,
        address poolInfo_,
        uint256 numOfActors_,
        address testContract_
    ) LiquidationPoolHandler(pool_, ajna_, quote_, collateral_, poolInfo_, numOfActors_, testContract_) {

    }

    /*******************************/
    /*** Reserves Test Functions ***/
    /*******************************/

    function startClaimableReserveAuction(
        uint256 actorIndex_
    ) external useRandomActor(actorIndex_) useTimestamps {
        // Action phase
        _startClaimableReserveAuction();
    }

    function takeReserves(
        uint256 actorIndex_,
        uint256 amountToTake_
    ) external useRandomActor(actorIndex_) useTimestamps {
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
    ) internal useTimestamps returns (uint256 boundedAmount_) {
        (, , uint256 claimableReservesRemaining, , ) = _poolInfo.poolReservesInfo(address(_pool));
        if (claimableReservesRemaining == 0) _startClaimableReserveAuction();

        // skip enough time for auction price to decrease
        skip(24 hours);

        (, , claimableReservesRemaining, , ) = _poolInfo.poolReservesInfo(address(_pool));
        boundedAmount_ = constrictToRange(amountToTake_, 0, Maths.min(100_000 * 1e18, claimableReservesRemaining));
    }

}