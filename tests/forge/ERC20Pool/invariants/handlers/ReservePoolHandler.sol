
// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.14;

import '@std/Vm.sol';

import { Auctions } from 'src/libraries/external/Auctions.sol';

import { LiquidationPoolHandler } from './LiquidationPoolHandler.sol';

import {
    LENDER_MIN_BUCKET_INDEX,
    LENDER_MAX_BUCKET_INDEX,
    BaseHandler
} from './BaseHandler.sol';

abstract contract UnBoundedReservePoolHandler is BaseHandler {

    function startClaimableReserveAuction() internal useTimestamps resetAllPreviousLocalState {
        (, uint256 claimableReserves, , , ) = _poolInfo.poolReservesInfo(address(_pool));
        if (claimableReserves == 0) return;

        _fenwickAccrueInterest();

        _updatePoolState();

        _updatePreviousReserves();
        _updatePreviousExchangeRate();

        try _pool.startClaimableReserveAuction() {

            shouldExchangeRateChange = false;
            shouldReserveChange      = true;

            _updateCurrentReserves();
            _updateCurrentExchangeRate();

        } catch {
            _resetReservesAndExchangeRate();
        }
    }

    function takeReserves(
        uint256 amount_
    ) internal useTimestamps resetAllPreviousLocalState {
        (, , uint256 claimableReservesRemaining, , ) = _poolInfo.poolReservesInfo(address(_pool));

        if(claimableReservesRemaining == 0) {
            startClaimableReserveAuction();
        }
        (, , claimableReservesRemaining, , ) = _poolInfo.poolReservesInfo(address(_pool));

        amount_ = constrictToRange(amount_, 0, claimableReservesRemaining);

        _fenwickAccrueInterest();

        _updatePoolState();

        _updatePreviousReserves();
        _updatePreviousExchangeRate();
        
        try _pool.takeReserves(amount_) {

            shouldExchangeRateChange = false;
            shouldReserveChange      = true;

            _updateCurrentReserves();
            _updateCurrentExchangeRate();

        } catch {
            _resetReservesAndExchangeRate();
        }
    }
}

contract ReservePoolHandler is UnBoundedReservePoolHandler, LiquidationPoolHandler {

    constructor(
        address pool_,
        address quote_,
        address collateral_,
        address poolInfo_,
        uint256 numOfActors_,
        address testContract_
    ) LiquidationPoolHandler(pool_, quote_, collateral_, poolInfo_, numOfActors_, testContract_) {

    }

    function startClaimableReserveAuction(
        uint256 actorIndex_
    ) external useRandomActor(actorIndex_) useTimestamps {
        super.startClaimableReserveAuction();
    }

    function takeReserves(
        uint256 actorIndex_,
        uint256 amount_
    ) external useRandomActor(actorIndex_) useTimestamps {
        super.takeReserves(amount_);
    }
}