// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.14;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { BaseHandler } from './BaseHandler.sol';

abstract contract UnboundedReservePoolHandler is BaseHandler {

    /*******************************/
    /*** Kicker Helper Functions ***/
    /*******************************/

    function _kickReserveAuction() internal updateLocalStateAndPoolInterest {
        (, uint256 claimableReserves, , , ) = _poolInfo.poolReservesInfo(address(_pool));
        if (claimableReserves == 0) return;

        try _pool.kickReserveAuction() {

            // **RE11**:  Reserves increase by claimableReserves by kickReserveAuction
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
    ) internal updateLocalStateAndPoolInterest {
        deal(address(_ajna), _actor, type(uint256).max);
        IERC20(address(_ajna)).approve(address(_pool), type(uint256).max);

        try _pool.takeReserves(amount_) {

        } catch (bytes memory err) {
            _ensurePoolError(err);
        }
    }
}
