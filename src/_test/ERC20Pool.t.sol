// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.11;

import {ERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {DSTestPlus} from "./utils/DSTestPlus.sol";
import {UserWithCollateral, UserWithQuoteToken} from "./utils/Users.sol";
import {CollateralToken, QuoteToken} from "./utils/Tokens.sol";

import {ERC20Pool} from "../ERC20Pool.sol";
import {ERC20PoolFactory} from "../ERC20PoolFactory.sol";

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

        ERC20PoolFactory factory = new ERC20PoolFactory();
        pool = factory.deployPool(address(collateral), address(quote));
    }

    function testDeploy() public {
        assertEq(address(collateral), address(pool.collateral()));
        assertEq(address(quote), address(pool.quoteToken()));
    }

    function testEmptyBucket() public {
        (
            ,
            ,
            ,
            uint256 deposit,
            uint256 debt,
            uint256 bucketInflator,
            uint256 lpOutstanding,
            uint256 bucketCollateral
        ) = pool.bucketAt(1_004.989662429170775094 * 1e18);
        assertEq(deposit, 0);
        assertEq(debt, 0);
        assertEq(bucketInflator, 0);
        assertEq(lpOutstanding, 0);
        assertEq(bucketCollateral, 0);

        (
            ,
            ,
            ,
            deposit,
            debt,
            bucketInflator,
            lpOutstanding,
            bucketCollateral
        ) = pool.bucketAt(2_793.857521496941952028 * 1e18);
        assertEq(deposit, 0);
        assertEq(debt, 0);
        assertEq(bucketInflator, 0);
        assertEq(lpOutstanding, 0);
        assertEq(bucketCollateral, 0);
    }
}
