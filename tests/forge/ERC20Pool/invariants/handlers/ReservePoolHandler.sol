
// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.14;

import '@std/Vm.sol';

import { LiquidationPoolHandler } from './LiquidationPoolHandler.sol';
import { LENDER_MIN_BUCKET_INDEX, LENDER_MAX_BUCKET_INDEX, BaseHandler } from './BaseHandler.sol';
import { Auctions } from 'src/libraries/external/Auctions.sol';

abstract contract UnBoundedReservePoolHandler is BaseHandler {
    function startClaimableReserveAuction() internal useTimestamps resetAllPreviousLocalState {
        (, uint256 claimableReserves, , , ) = _poolInfo.poolReservesInfo(address(_pool));
        if(claimableReserves == 0) return;

        fenwickAccrueInterest();
        updatePoolState();
        updatePreviousReserves();
        updatePreviousExchangeRate();

        try _pool.startClaimableReserveAuction(){
            shouldExchangeRateChange = false;
            shouldReserveChange      = true;
            updateCurrentReserves();
            updateCurrentExchangeRate();
        } catch {
            resetReservesAndExchangeRate();
        }
    }

    function takeReserves(uint256 amount) internal useTimestamps resetAllPreviousLocalState {

        (, , uint256 claimableReservesRemaining, , ) = _poolInfo.poolReservesInfo(address(_pool));

        if(claimableReservesRemaining == 0) {
            startClaimableReserveAuction();
        }
        (, , claimableReservesRemaining, , ) = _poolInfo.poolReservesInfo(address(_pool));

        amount = constrictToRange(amount, 0, claimableReservesRemaining);

        fenwickAccrueInterest();
        updatePoolState();
        updatePreviousReserves();
        updatePreviousExchangeRate();
        
        try _pool.takeReserves(amount){
            shouldExchangeRateChange = false;
            shouldReserveChange      = true;
            updateCurrentReserves();
            updateCurrentExchangeRate();
        } catch {
            resetReservesAndExchangeRate();
        }
    }
}

contract ReservePoolHandler is UnBoundedReservePoolHandler, LiquidationPoolHandler {

    constructor(address pool, address quote, address collateral, address poolInfo, uint256 numOfActors, address testContract) LiquidationPoolHandler(pool, quote, collateral, poolInfo, numOfActors, testContract) {}

    function startClaimableReserveAuction(uint256 actorIndex) external useRandomActor(actorIndex) useTimestamps {
        super.startClaimableReserveAuction();
    }

    function takeReserves(uint256 actorIndex, uint256 amount) external useRandomActor(actorIndex) useTimestamps {
        super.takeReserves(amount);
    }
}