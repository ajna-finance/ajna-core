// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.11;

import { DSTestPlus } from "./utils/DSTestPlus.sol";
import { Maths }      from "../libraries/Maths.sol";

contract MathTest is DSTestPlus {

    function testRayToWadRounded() external {
        uint256 amount = 5_000.00076103507940381999999950 * 1e27;
        assertEq(Maths.rayToWad(amount), 5_000.000761035079403820 * 1e18);
    }

    function testZeroStaysZero() external {
        assertEq(Maths.rayToWad(0), 0);
    }

}
