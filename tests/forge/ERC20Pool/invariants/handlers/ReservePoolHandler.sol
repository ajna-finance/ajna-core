// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.14;

import { UnboundedReservePoolHandler } from '../base/UnboundedReservePoolHandler.sol';

import { LiquidationPoolHandler } from './LiquidationPoolHandler.sol';

contract ReservePoolHandler is UnboundedReservePoolHandler, LiquidationPoolHandler {

    constructor(
        address pool_,
        address quote_,
        address collateral_,
        address poolInfo_,
        uint256 numOfActors_,
        address testContract_
    ) LiquidationPoolHandler(pool_, quote_, collateral_, poolInfo_, numOfActors_, testContract_) {

    }

    /*******************************/
    /*** Reserves Test Functions ***/
    /*******************************/

    function startClaimableReserveAuction(
        uint256 actorIndex_
    ) external useRandomActor(actorIndex_) useTimestamps {
        _startClaimableReserveAuction();
    }

    function takeReserves(
        uint256 actorIndex_,
        uint256 amount_
    ) external useRandomActor(actorIndex_) useTimestamps {

        (, , uint256 claimableReservesRemaining, , ) = _poolInfo.poolReservesInfo(address(_pool));
        if (claimableReservesRemaining == 0) _startClaimableReserveAuction();

        (, , claimableReservesRemaining, , ) = _poolInfo.poolReservesInfo(address(_pool));
        amount_ = constrictToRange(amount_, 0, claimableReservesRemaining);

        _takeReserves(amount_);
    }
}