// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.10;

import {ERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {DSTestPlus} from "./utils/DSTestPlus.sol";
import {UserWithCollateral, UserWithQuoteToken} from "./utils/Users.sol";
import {CollateralToken, QuoteToken} from "./utils/Tokens.sol";

import {ERC20Pool} from "../ERC20Pool.sol";

contract ERC20PoolTest is DSTestPlus {
    ERC20Pool internal pool;
    CollateralToken internal collateral;
    QuoteToken internal quote;

    UserWithCollateral internal alice;
    UserWithCollateral internal bob;

    function setUp() public {
        alice = new UserWithCollateral();
        bob = new UserWithCollateral();
        collateral = new CollateralToken();

        collateral.mint(address(alice), 100 * 1e18);
        collateral.mint(address(bob), 100 * 1e18);

        quote = new QuoteToken();

        pool = new ERC20Pool(collateral, quote);
    }

    function testDeploy() public {
        assertEq(address(collateral), address(pool.collateral()));
        assertEq(address(quote), address(pool.quoteToken()));
    }
}
