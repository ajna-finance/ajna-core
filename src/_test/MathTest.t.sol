// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.11;

import { DSTestPlus } from "./utils/DSTestPlus.sol";
import { Maths }      from "../libraries/Maths.sol";

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

    function testDivision() external {
        uint256 debt = 11_000.143012091382543917 * 1e18;
        uint256 price = 1_001.6501589292607751220 * 1e18;

        assertEq(Maths.wdiv(debt, price), 10.98202093218880245 * 1e18);
        assertEq(debt * 1e18 / price, 10.98202093218880245 * 1e18);
    }

}
