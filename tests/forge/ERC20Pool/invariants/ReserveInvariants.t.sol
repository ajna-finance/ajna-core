// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.14;

import '@std/Test.sol';
import "@std/console.sol";

import { TestBase } from './TestBase.sol';

import { LENDER_MIN_BUCKET_INDEX, LENDER_MAX_BUCKET_INDEX, BORROWER_MIN_BUCKET_INDEX } from './handlers/BasicPoolHandler.sol';

import { ReservePoolHandler }   from './handlers/ReservePoolHandler.sol';
import { LiquidationInvariant } from './LiquidationInvariant.t.sol';
import { IBaseHandler }         from './handlers/IBaseHandler.sol';

contract ReserveInvariants is LiquidationInvariant {
    
    ReservePoolHandler internal _reservePoolHandler;
    uint256 previousReserves;

    function setUp() public override virtual {

        super.setUp();

        excludeContract(address(_liquidationPoolHandler));

        _reservePoolHandler = new ReservePoolHandler(address(_pool), address(_quote), address(_collateral), address(_poolInfo), NUM_ACTORS);
        _handler = address(_reservePoolHandler);

        (previousReserves, , , , ) = _poolInfo.poolReservesInfo(address(_pool));
    }

    // FIXME
    function _invariant_reserves_RE1_RE2_RE3_RE4_RE5_RE6_RE7_RE8_RE9() public {

        (uint256 currentReserves, , , , ) = _poolInfo.poolReservesInfo(address(_pool));
        console.log("Current Reserves -->", currentReserves);
        console.log("Previous Reserves -->", previousReserves);
        if(!IBaseHandler(_handler).shouldReserveChange()) {
            require(currentReserves == previousReserves, "Incorrect Reserves change");
        }

        uint256 firstTakeIncreaseInReserve = IBaseHandler(_handler).firstTakeIncreaseInReserve();

        console.log("firstTakeIncreaseInReserve -->", firstTakeIncreaseInReserve);
        if(IBaseHandler(_handler).firstTake()) {
            requireWithinDiff(currentReserves, previousReserves + firstTakeIncreaseInReserve, 1e2, "Incorrect Reserves change with first take");
        }

        uint256 loanKickIncreaseInReserve = IBaseHandler(_handler).loanKickIncreaseInReserve();

        console.log("loanKickIncreaseInReserve -->", loanKickIncreaseInReserve);
        if(loanKickIncreaseInReserve != 0) {
            requireWithinDiff(currentReserves, previousReserves + loanKickIncreaseInReserve, 1e2, "Incorrect Reserves change with kick");
        }
        previousReserves = currentReserves;
    }

}