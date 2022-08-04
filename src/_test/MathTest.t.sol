// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.14;

import { DSTestPlus }     from "./utils/DSTestPlus.sol";
import { Maths }          from "../libraries/Maths.sol";
import { PRBMathUD60x18 } from "@prb-math/contracts/PRBMathUD60x18.sol";

contract MathTest is DSTestPlus {

    function testRayToWadRounded() external {
        uint256 amount = 5_000.00076103507940381999999950 * 1e27;
        assertEq(Maths.rayToWad(amount), 5_000.000761035079403820 * 1e18);

        assertEq(Maths.rayToWad(4 * 10e27), 4 * 10e18);
        assertEq(Maths.rayToWad(0.00000000000000000006 * 10e27), 1);
        assertEq(Maths.rayToWad(0.00000000000000000004 * 10e27), 0);
    }

    function testZeroStaysZero() external {
        assertEq(Maths.rayToWad(0), 0);
        assertEq(Maths.radToRay(0), 0);
        assertEq(Maths.radToWad(0), 0);
    }

    function testMultiplication() external {
        uint256 debt     = 10_000.44444444444443999 * 1e18;
        uint256 inflator = 1.02132007 * 1e27;

        assertEq(debt * inflator,                         10_213.6546200311111065616975993 * 1e45);
        assertEq(Maths.radToRay(debt * inflator),         10_213.6546200311111065616975993 * 1e27);
        assertEq(Maths.radToWad(debt * inflator),         10_213.654620031111106562 * 1e18);
        assertEq(Maths.radToWadTruncate(debt * inflator), 10_213.654620031111106561 * 1e18);
    }

    function testDivision() external {
        uint256 debt  = 11_000.143012091382543917 * 1e18;
        uint256 price = 1_001.6501589292607751220 * 1e18;

        assertEq(Maths.wdiv(debt, price),   10.98202093218880245 * 1e18);
        assertEq(debt * 1e18 / price,       10.98202093218880245 * 1e18);
        assertEq(Maths.wwdivr(debt, price), 10.982020932188802450191601163 * 1e27);

        assertEq(Maths.wrdivw(20 * 1e18, 10.982020932188802450191601163 * 1e27), 1.821158430082671857 * 1e18);

        uint256 exchangeRate = 1.09232010 * 1e27;
        assertEq(Maths.rdiv(Maths.wadToRay(debt), exchangeRate), Maths.wrdivr(debt, exchangeRate));
    }

    function testWadToIntRoundingDown() external {
        uint256 testNum1  = 11_000.143012091382543917 * 1e18;
        uint256 testNum2  = 1_001.6501589292607751220 * 1e18;
        uint256 testNum3  = 0.6501589292607751220 * 1e18;

        assertEq(Maths.wadToIntRoundingDown(testNum1), 11_000);
        assertEq(Maths.wadToIntRoundingDown(testNum2), 1_001);
        assertEq(Maths.wadToIntRoundingDown(testNum3), 0);
    }

    function testExp() external {
        assertEq(PRBMathUD60x18.exp(1.53 * 1e18), 4.618176822299780807 * 1e18);
    }
}
