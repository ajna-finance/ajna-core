// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.14;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

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
        deal(0x9a96ec9B57Fb64FbC60B423d1f4da7691Bd35079, _actor, type(uint256).max);
        IERC20(0x9a96ec9B57Fb64FbC60B423d1f4da7691Bd35079).approve(address(_pool), type(uint256).max);

        try _pool.takeReserves(amount_) returns (uint256 takenAmount_) {

            decreaseInReserves += takenAmount_;

        } catch (bytes memory err) {
            _ensurePoolError(err);
        }
    }
}
