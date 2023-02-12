// SPDX-License-Identifier: UNLICENSED

import { ReserveInvariants }            from "../invariants/ReserveInvariants.t.sol";

pragma solidity 0.8.14;

import '@std/console.sol';


contract RegressionTestReserve is ReserveInvariants { 

    function setUp() public override { 
        super.setUp();
    }   

    // function test_reserve_1() external {
    //     (uint256 reserve, , , , ) = _poolInfo.poolReservesInfo(address(_pool));
    //     console.log("Initial Reserve -->", reserve);

    //     _reservePoolHandler.kickAuction(3833, 15167, 15812);

    //     (reserve, , , , ) = _poolInfo.poolReservesInfo(address(_pool));
    //     console.log("Reserve after kick --->", reserve);
    //     invariant_reserves_RE1_RE2_RE3_RE4_RE5_RE6_RE7_RE8_RE9();


    //     _reservePoolHandler.removeQuoteToken(3841, 5339, 3672);

    //     (reserve, , , , ) = _poolInfo.poolReservesInfo(address(_pool));
    //     console.log("Reserve after removeQuoteToken --->", reserve);
    //     invariant_reserves_RE1_RE2_RE3_RE4_RE5_RE6_RE7_RE8_RE9();
    // }

    // function test_reserve_2() external {
    //     (uint256 reserve, , , , ) = _poolInfo.poolReservesInfo(address(_pool));
    //     console.log("Initial Reserve -->", reserve);
        
    //     _reservePoolHandler.bucketTake(19730, 10740, false, 15745);

    //     (reserve, , , , ) = _poolInfo.poolReservesInfo(address(_pool));
    //     console.log("Reserve after bucketTake --->", reserve);
    //     invariant_reserves_RE1_RE2_RE3_RE4_RE5_RE6_RE7_RE8_RE9();


    //     _reservePoolHandler.addCollateral(14982, 18415, 2079);

    //     (reserve, , , , ) = _poolInfo.poolReservesInfo(address(_pool));
    //     console.log("Reserve after addCollateral --->", reserve);
    //     invariant_reserves_RE1_RE2_RE3_RE4_RE5_RE6_RE7_RE8_RE9();
    // }
}