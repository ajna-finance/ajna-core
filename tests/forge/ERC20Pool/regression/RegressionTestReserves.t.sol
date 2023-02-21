// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.14;

import { ReserveInvariants }            from "../invariants/ReserveInvariants.t.sol";

import '@std/console.sol';

contract RegressionTestReserve is ReserveInvariants { 

    function setUp() public override { 
        super.setUp();
    }   

    function test_reserve_1() external {
        (uint256 reserve, , , , ) = _poolInfo.poolReservesInfo(address(_pool));
        console.log("Initial Reserve -->", reserve);
        console.log("===========");

        _reservePoolHandler.kickAuction(3833, 15167, 15812);

        (reserve, , , , ) = _poolInfo.poolReservesInfo(address(_pool));
        console.log("Reserve after kick --->", reserve);
        invariant_reserves_RE1_RE2_RE3_RE4_RE5_RE6_RE7_RE8_RE9();
        console.log("===========");


        _reservePoolHandler.removeQuoteToken(3841, 5339, 3672);

        (reserve, , , , ) = _poolInfo.poolReservesInfo(address(_pool));
        console.log("Reserve after removeQuoteToken --->", reserve);
        invariant_reserves_RE1_RE2_RE3_RE4_RE5_RE6_RE7_RE8_RE9();
        console.log("===========");
    }

    // test was failing due to error in local fenwickAccureInterest method
    function test_reserve_2() external {
        (uint256 reserve, , , , ) = _poolInfo.poolReservesInfo(address(_pool));
        console.log("Initial Reserve -->", reserve);
        console.log("===========");
        
        _reservePoolHandler.bucketTake(19730, 10740, false, 15745);

        (reserve, , , , ) = _poolInfo.poolReservesInfo(address(_pool));
        console.log("Reserve after addQuoteToken(2000000000000000000000000, 2570, 1672372187)");
        console.log("Reserve after drawDebt(Actor0: [0x129862D03ec9aBEE86890af0AB05EC02C654B403], 1000000000000000000000000, 7388, 368791893539077078583)");
        console.log("Reserve after kick(Actor0: [0x129862D03ec9aBEE86890af0AB05EC02C654B403]) --->", reserve);
        invariant_reserves_RE1_RE2_RE3_RE4_RE5_RE6_RE7_RE8_RE9();
        console.log("===========");
        console.log("ADD Collateral");
        console.log("===========");
        _reservePoolHandler.addCollateral(14982, 18415, 2079);

        (reserve, , , , ) = _poolInfo.poolReservesInfo(address(_pool));
        console.log("Reserve after addCollateral(18415, 2570, 1689659387) by actor2 --->", reserve);
        invariant_reserves_RE1_RE2_RE3_RE4_RE5_RE6_RE7_RE8_RE9();
        console.log("===========");
    }

    function test_reserve_3() external {
        (uint256 reserve, , , , ) = _poolInfo.poolReservesInfo(address(_pool));
        console.log("Initial Reserve -->", reserve);
        console.log("===========");

        _reservePoolHandler.repayDebt(404759030515771436961484, 115792089237316195423570985008687907853269984665640564039457584007913129639932);

        invariant_fenwickTreeSum();

        (reserve, , , , ) = _poolInfo.poolReservesInfo(address(_pool));
        console.log("Reserve after repayDebt --->", reserve);

        _reservePoolHandler.removeQuoteToken(1, 48462143332689486187207611220503504, 3016379223696706064676286307759709760607418884028758142005949880337746);
        (reserve, , , , ) = _poolInfo.poolReservesInfo(address(_pool));
        console.log("Reserve after removeQuoteToken --->", reserve);

        invariant_fenwickTreeSum();

    }

    function test_reserve_4() external {
        _reservePoolHandler.takeAuction(115792089237316195423570985008687907853269984665640564039457584007913129639934, 115792089237316195423570985008687907853269984665640564039457584007913129639933, 1);  

        // Current Reserves --> 58240015324867402996449176812691659
        // Previous Reserves --> 19420925251055611391882467966008910
        // firstTakeIncreaseInReserve --> 34019245800203394599128852948867657 

        invariant_reserves_RE1_RE2_RE3_RE4_RE5_RE6_RE7_RE8_RE9();
    }

    function test_reserve_5() external {
        (uint256 reserve, , , , ) = _poolInfo.poolReservesInfo(address(_pool));
        console.log("Initial Reserve -->", reserve);
        console.log("===========");
        _reservePoolHandler.addQuoteToken(16175599156223678030374425049208907710, 7790130564765920091364739351727, 3);
        (reserve, , , , ) = _poolInfo.poolReservesInfo(address(_pool));
        console.log("Reserve after addQuoteToken -->", reserve);
        console.log("===========");
        _reservePoolHandler.takeReserves(5189, 15843);
        (reserve, , , , ) = _poolInfo.poolReservesInfo(address(_pool));
        console.log("Reserve after takeReserves -->", reserve);
        console.log("===========");
        _reservePoolHandler.bucketTake(115792089237316195423570985008687907853269984665640564039457584007913129639934, 115792089237316195423570985008687907853269984665640564039457584007913129639933, false, 32141946615464);
        (reserve, , , , ) = _poolInfo.poolReservesInfo(address(_pool));
        console.log("Reserve after bucketTake -->", reserve);
        console.log("===========");

        invariant_reserves_RE1_RE2_RE3_RE4_RE5_RE6_RE7_RE8_RE9();
    }

    function test_reserve_6() external {
        _reservePoolHandler.addQuoteToken(115792089237316195423570985008687907853269984665640564039457584007913129639933, 115792089237316195423570985008687907853269984665640564039457584007913129639932, 115792089237316195423570985008687907853269984665640564039457584007913129639934);
        _reservePoolHandler.removeQuoteToken(3, 76598848420614737624527356706527, 0);

        invariant_reserves_RE1_RE2_RE3_RE4_RE5_RE6_RE7_RE8_RE9();
    }

    function test_reserve_7() external {
        _reservePoolHandler.addQuoteToken(3457, 669447918254181815570046125126321316, 999999999837564549363536522206516458546098684);

        _reservePoolHandler.takeReserves(0, 115792089237316195423570985008687907853269984665640564039457584007913129639935);

        _reservePoolHandler.takeAuction(1340780, 50855928079819281347583122859151761721081932621621575848930363902528865907253, 1955849966715168052511460257792969975295827229642304100359774335664);

        invariant_reserves_RE1_RE2_RE3_RE4_RE5_RE6_RE7_RE8_RE9();
    }

    function test_reserve_8() external {
        _reservePoolHandler.addQuoteToken(0, 16517235514828622102184417372650002297563613398679232953, 3);

        _reservePoolHandler.takeReserves(1, 824651);

        _reservePoolHandler.kickAuction(353274873012743605831170677893, 0, 297442424590491337560428021161844134441441035247561757);

        invariant_reserves_RE1_RE2_RE3_RE4_RE5_RE6_RE7_RE8_RE9();
    }
}