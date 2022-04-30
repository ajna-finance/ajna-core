// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.11;

import {ERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {DSTestPlus} from "./utils/DSTestPlus.sol";
import {UserWithCollateral, UserWithQuoteToken} from "./utils/Users.sol";
import {CollateralToken, QuoteToken} from "./utils/Tokens.sol";

import {ERC20Pool} from "../ERC20Pool.sol";
import {ERC20PoolFactory} from "../ERC20PoolFactory.sol";
import {IPool} from "../interfaces/IPool.sol";


contract ERC20PoolTest is DSTestPlus {
    ERC20Pool internal pool;
    CollateralToken internal collateral;
    QuoteToken internal quote;

    UserWithCollateral internal borrower;
    UserWithQuoteToken internal lender;

    function setUp() public {
        collateral = new CollateralToken();
        quote = new QuoteToken();

        ERC20PoolFactory factory = new ERC20PoolFactory();
        pool = factory.deployPool(address(collateral), address(quote));

        lender = new UserWithQuoteToken();
        quote.mint(address(lender), 200_000 * 1e18);
        lender.approveToken(quote, address(pool), 200_000 * 1e18);

        borrower = new UserWithCollateral();
        collateral.mint(address(borrower), 200_000 * 1e18);
        borrower.approveToken(collateral, address(pool), 200_000 * 1e18);
    }

    // @notice:Tests pool factory inputs match the pool created
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

        (, , , deposit, debt, bucketInflator, lpOutstanding, bucketCollateral) = pool.bucketAt(
            2_793.857521496941952028 * 1e18
        );
        assertEq(deposit, 0);
        assertEq(debt, 0);
        assertEq(bucketInflator, 0);
        assertEq(lpOutstanding, 0);
        assertEq(bucketCollateral, 0);
    }

    // @notice: Check that initialize can only be called once
    function testInitialize() public {
        uint256 initialInflator = 1 * 10**27;

        assertEq(pool.inflatorSnapshot(), initialInflator);
        assertEq(pool.lastInflatorSnapshotUpdate(), 0);

        // Add quote tokens to the pool to allow initial values to change
        lender.addQuoteToken(pool, address(lender), 10_000 * 1e18, 4_000.927678580567537368 * 1e18);

        // add time to enable the inflator to update
        skip(8200);

        borrower.addCollateral(pool, 2 * 1e18);
        borrower.borrow(pool, 1000 * 1e18, 3000 * 1e18);

        assertGt(pool.inflatorSnapshot(), initialInflator);
        assertEq(pool.lastInflatorSnapshotUpdate(), 8200);

        // Attempt to call initialize() to reset global variables and check for revert
        vm.expectRevert(IPool.AlreadyInitialized.selector);
        pool.initialize();

        // check that global variables weren't reset
        assertGt(pool.inflatorSnapshot(), initialInflator);
        assertEq(pool.lastInflatorSnapshotUpdate(), 8200);
    }
}
