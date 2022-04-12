// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.11;

import {DSTestPlus} from "../utils/DSTestPlus.sol";

import {AjnaToken} from "../../tokens/Ajna.sol";

contract AjnaTokenTest is DSTestPlus {
    AjnaToken internal token;

    function setUp() public {
        token = new AjnaToken(10_000);
    }

    function testFailCannotSendTokensToContract() public {
        assert(false == token.transfer(address(token), 1));
    }

    function invariantMetadata() public {
        assertEq(token.name(), "Ajna");
        assertEq(token.symbol(), "AJNA");
        assertEq(token.decimals(), 18);
    }
}
