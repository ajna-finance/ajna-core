// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.11;

import { AjnaToken } from "../../tokens/Ajna.sol";

import { DSTestPlus } from "../utils/DSTestPlus.sol";

contract AjnaTokenTest is DSTestPlus {
    AjnaToken internal _token;

    function setUp() external {
        _token = new AjnaToken(10_000);
    }

    function testFailCannotSendTokensToContract() external {
        assert(false == _token.transfer(address(_token), 1));
    }

    function invariantMetadata() external {
        assertEq(_token.name(),     "Ajna");
        assertEq(_token.symbol(),   "AJNA");
        assertEq(_token.decimals(), 18);
    }
}
