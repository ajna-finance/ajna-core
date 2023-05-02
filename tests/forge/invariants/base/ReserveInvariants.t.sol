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

    function invariant_call_summary() public virtual override useCurrentTimestamp {
        console.log("\nCall Summary\n");
        console.log("--Reserves--------");
        console.log("BReserveHandler.takeReserves        ",  IBaseHandler(_handler).numberOfCalls("BReserveHandler.takeReserves"));
        console.log("UBReserveHandler.takeReserves       ",  IBaseHandler(_handler).numberOfCalls("UBReserveHandler.takeReserves"));
        console.log("BReserveHandler.kickReserves        ",  IBaseHandler(_handler).numberOfCalls("BReserveHandler.kickReserves"));
        console.log("UBReserveHandler.kickReserves       ",  IBaseHandler(_handler).numberOfCalls("UBReserveHandler.kickReserves"));
        console.log(
            "Sum",
            IBaseHandler(_handler).numberOfCalls("BReserveHandler.takeReserves") +
            IBaseHandler(_handler).numberOfCalls("BReserveHandler.kickReserves")
        );
    }
}