// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.14;

import "@std/console.sol";

import { IBaseHandler }          from '../interfaces/IBaseHandler.sol';
import { LiquidationInvariants } from './LiquidationInvariants.t.sol';

abstract contract ReserveInvariants is LiquidationInvariants {

    function invariant_reserves_RE1_RE2_RE3_RE4_RE5_RE6_RE7_RE8_RE9_RE10_RE11_RE12() public useCurrentTimestamp {

        uint256 previousReserves   = IBaseHandler(_handler).previousReserves();
        uint256 increaseInReserves = IBaseHandler(_handler).increaseInReserves();
        uint256 decreaseInReserves = IBaseHandler(_handler).decreaseInReserves();
        (uint256 currentReserves, , , , ) = _poolInfo.poolReservesInfo(address(_pool));

        console.log("Previous Reserves     -->", previousReserves);
        console.log("Increase in Reserves  -->", increaseInReserves);
        console.log("Decrease in Reserves  -->", decreaseInReserves);
        console.log("Current Reserves      -->", currentReserves);
        console.log("Required Reserves     -->", previousReserves + increaseInReserves - decreaseInReserves);

        requireWithinDiff(
            currentReserves,
            previousReserves + increaseInReserves - decreaseInReserves,
            1e15,
            "Incorrect Reserves change"
        );
    }
}