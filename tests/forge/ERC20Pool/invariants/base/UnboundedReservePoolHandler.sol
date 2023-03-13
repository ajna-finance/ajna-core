// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.14;

import { BaseHandler } from './BaseHandler.sol';

abstract contract UnboundedReservePoolHandler is BaseHandler {

    /*******************************/
    /*** Kicker Helper Functions ***/
    /*******************************/

    function _startClaimableReserveAuction() internal useTimestamps updateLocalStateAndPoolInterest {
        (, uint256 claimableReserves, , , ) = _poolInfo.poolReservesInfo(address(_pool));
        if (claimableReserves == 0) return;

        try _pool.startClaimableReserveAuction() {

            // **RE11**:  Reserves increase by claimableReserves by startClaimableReserveAuction
            decreaseInReserves += claimableReserves;            
        } catch (bytes memory err) {
            _ensurePoolError(err);
        }
    }

    /******************************/
    /*** Taker Helper Functions ***/
    /******************************/

    function _takeReserves(
        uint256 amount_
    ) internal useTimestamps updateLocalStateAndPoolInterest {
        try _pool.takeReserves(amount_) returns (uint256 takenAmount_) {

            decreaseInReserves += takenAmount_;

        } catch (bytes memory err) {
            _ensurePoolError(err);
        }
    }
}
