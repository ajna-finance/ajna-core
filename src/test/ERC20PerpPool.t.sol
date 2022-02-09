// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.11;

import {ERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {DSTestPlus} from "./utils/DSTestPlus.sol";
import {UserWithCollateral, UserWithQuoteToken} from "./utils/Users.sol";
import {CollateralToken, QuoteToken} from "./utils/Tokens.sol";

import {ERC20PerpPool} from "../ERC20PerpPool.sol";

contract ERC20PerpPoolTest is DSTestPlus {
    ERC20PerpPool internal pool;
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

        pool = new ERC20PerpPool(collateral, quote);
    }

    function testDeploy() public {
        assertEq(address(collateral), address(pool.collateralToken()));
        assertEq(address(quote), address(pool.quoteToken()));

        // TODO: Should them be also parameters to constructor
        assertEq(1 * 1e18, pool.borrowerInflator());
        assertEq(0.05 * 1e18, pool.previousRate());

        assertEq(block.timestamp, pool.lastBorrowerInflatorUpdate());
        assertEq(block.timestamp, pool.previousRateUpdate());
    }

    function testDepositCollateral() public {
        alice.approveAndDepositTokenAsCollateral(collateral, pool, 50 * 1e18);

        uint256 aliceCollateral = pool.collateralBalances(address(alice));

        assertEq(aliceCollateral, 50 * 1e18);

        // we're at the same block, borrower inflator should be same
        assertEq(pool.borrowerInflator(), 1 * 1e18);
        assertEq(pool.borrowerInflatorPending(), 1 * 1e18);

        vm.warp(block.timestamp + 1 minutes);

        // blocks mined but no tx to update borrower inflator
        assertEq(pool.borrowerInflator(), 1 * 1e18);
        assertGt(pool.borrowerInflatorPending(), 1000000095000000000);

        alice.approveAndDepositTokenAsCollateral(collateral, pool, 50 * 1e18);
        // borrower inflator updated with new deposit tx
        assertGt(pool.borrowerInflator(), 1 * 1e18);
    }
}
