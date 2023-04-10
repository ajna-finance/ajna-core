// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.14;

import '../utils/DSTestPlus.sol';

import '@prb-math/contracts/PRBMathSD59x18.sol';
import '@prb-math/contracts/PRBMathUD60x18.sol';

import 'src/libraries/internal/Maths.sol';

contract MathTest is DSTestPlus {

    function testRayToWadRounded() external {
        uint256 amount = 5_000.00076103507940381999999950 * 1e27;
        assertEq(Maths.rayToWad(amount), 5_000.000761035079403820 * 1e18);

        assertEq(Maths.rayToWad(4 * 1e27), 4 * 1e18);
        assertEq(Maths.rayToWad(0.0000000000000000006 * 1e27), 1);
        assertEq(Maths.rayToWad(0.0000000000000000004 * 1e27), 0);
    }

    function testZeroStaysZero() external {
        assertEq(Maths.rayToWad(0), 0);
    }

    function testMultiplication() external {
        uint256 debt     = 10_000.44444444444443999 * 1e18;
        uint256 inflator = 1.02132007 * 1e27;

        assertEq(debt * inflator,                         10_213.6546200311111065616975993 * 1e45);
    }

    function testScaleConversions() external {
        assertEq(Maths.wad(153), 153 * 1e18);
    } 

    function testExp() external {
        assertEq(PRBMathUD60x18.exp(1.53 * 1e18), 4.618176822299780807 * 1e18);

        int256 testPower = PRBMathSD59x18.mul(-1 * 1e18, int256(Maths.wdiv(12180 * 1e18, 3600 * 1e18)));
        assertEq(PRBMathSD59x18.exp2(testPower), 0.095833021541850035 * 1e18);
    }

    function testPow() external {
        assertEq(Maths.rpow(0.5 * 1e27, 60), 0.000000000000000000867361738 * 1e27);
        assertEq(Maths.rpow(0.5 * 1e27, 80), 0.000000000000000000000000827 * 1e27);
    }

    function testMaxMin() external {
        uint256 smallerWad = 0.002144924036174740 * 1e18;
        uint256 largerWad  = 0.951347940696070000 * 1e18;

        assertEq(Maths.max(0, 9), 9);
        assertEq(Maths.max(3, 0), 3);
        assertEq(Maths.max(smallerWad, largerWad), largerWad);

        assertEq(Maths.min(2, 4), 2);
        assertEq(Maths.min(0, 9), 0);
        assertEq(Maths.min(smallerWad, largerWad), smallerWad);
    }

    function testFloorWdiv() external {
        assertEq(Maths.wdiv(     1_001.4534563955 * 1e18, 55.24325 * 1e18), 18.128069155878772520 * 1e18);
        assertEq(Maths.floorWdiv(1_001.4534563955 * 1e18, 55.24325 * 1e18), 18.128069155878772519 * 1e18);
    }

    function testFloorWmul() external {
        assertEq(Maths.wmul(     1.4534563955 * 1e18, 0.112224325121212178 * 1e18), 0.163113163078097153 * 1e18);
        assertEq(Maths.floorWmul(1.4534563955 * 1e18, 0.112224325121212178 * 1e18), 0.163113163078097152 * 1e18);
    }

    function testMaxMinInt() external {
        assertEq(Maths.maxInt(-1, 2),   2);
        assertEq(Maths.minInt(-1, 2),  -1);

        assertEq(Maths.maxInt(-1, -1), -1);
        assertEq(Maths.minInt(-1, -1), -1);

        assertEq(Maths.maxInt(2, -1),   2);
        assertEq(Maths.minInt(2, -1),  -1);
    }
}
