
// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.14;

import '@std/Vm.sol';

import { LiquidationPoolHandler } from './LiquidationPoolHandler.sol';
import { LENDER_MIN_BUCKET_INDEX, LENDER_MAX_BUCKET_INDEX, BaseHandler } from './BaseHandler.sol';
import { Auctions } from 'src/libraries/external/Auctions.sol';

abstract contract UnBoundedReservePoolHandler is BaseHandler {
    function startClaimableReserveAuction() internal {
        (, uint256 claimableReserves, , , ) = _poolInfo.poolReservesInfo(address(_pool));
        if(claimableReserves == 0) return;
        try _pool.startClaimableReserveAuction(){
            shouldReserveChange = true;
        } catch {
        }
    }

    function takeReserves(uint256 amount) internal {
        try _pool.takeReserves(amount){
            shouldReserveChange = true;
        } catch {
        }
    }
}

contract ReservePoolHandler is UnBoundedReservePoolHandler, LiquidationPoolHandler {

    constructor(address pool, address quote, address collateral, address poolInfo, uint256 numOfActors) LiquidationPoolHandler(pool, quote, collateral, poolInfo, numOfActors) {}

    function startClaimableReserveAuction(uint256 actorIndex) external useRandomActor(actorIndex) {
        super.startClaimableReserveAuction();
    }

    function takeReserves(uint256 actorIndex, uint256 amount) external useRandomActor(actorIndex) {
        (, , uint256 claimableReservesRemaining, , ) = _poolInfo.poolReservesInfo(address(_pool));

        if(claimableReservesRemaining == 0) {
            super.startClaimableReserveAuction();
        }
        (, , claimableReservesRemaining, , ) = _poolInfo.poolReservesInfo(address(_pool));

        amount = constrictToRange(amount, 0, claimableReservesRemaining);
        super.takeReserves(amount);
    }
}