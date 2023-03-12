// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.14;

import { BaseHandler } from './BaseHandler.sol';

abstract contract UnboundedReservePoolHandler is BaseHandler {

    /*******************************/
    /*** Kicker Helper Functions ***/
    /*******************************/

    function _startClaimableReserveAuction() internal useTimestamps resetAllPreviousLocalState {
        (, uint256 claimableReserves, , , ) = _poolInfo.poolReservesInfo(address(_pool));
        if (claimableReserves == 0) return;

        _fenwickAccrueInterest();

        _updatePoolState();

        _updatePreviousReserves();
        _updatePreviousExchangeRate();

        try _pool.startClaimableReserveAuction() {

            shouldExchangeRateChange = false;
            shouldReserveChange      = true;

        } catch (bytes memory err) {
            _ensurePoolError(err);
        }
    }

    /******************************/
    /*** Taker Helper Functions ***/
    /******************************/

    function _takeReserves(
        uint256 amount_
    ) internal useTimestamps resetAllPreviousLocalState {
        (, , uint256 claimableReservesRemaining, , ) = _poolInfo.poolReservesInfo(address(_pool));

        if (claimableReservesRemaining == 0) _startClaimableReserveAuction();

        (, , claimableReservesRemaining, , ) = _poolInfo.poolReservesInfo(address(_pool));

        amount_ = constrictToRange(amount_, 0, claimableReservesRemaining);

        _fenwickAccrueInterest();

        _updatePoolState();

        _updatePreviousReserves();
        _updatePreviousExchangeRate();
        
        try _pool.takeReserves(amount_) {

            shouldExchangeRateChange = false;
            shouldReserveChange      = true;

        } catch (bytes memory err) {
            _ensurePoolError(err);
        }
    }
}
