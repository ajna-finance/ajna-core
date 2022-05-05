// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.11;

import { ERC20Pool }        from "../ERC20Pool.sol";
import { ERC20PoolFactory } from "../ERC20PoolFactory.sol";

import { IPool } from "../interfaces/IPool.sol";

import { DSTestPlus }                             from "./utils/DSTestPlus.sol";
import { CollateralToken, QuoteToken }            from "./utils/Tokens.sol";
import { UserWithCollateral, UserWithQuoteToken } from "./utils/Users.sol";

contract ERC20PoolTest is DSTestPlus {

    address            internal _poolAddress;
    CollateralToken    internal _collateral;
    ERC20Pool          internal _pool;
    QuoteToken         internal _quote;
    UserWithCollateral internal _borrower;
    UserWithQuoteToken internal _lender;

    function setUp() external {
        _collateral  = new CollateralToken();
        _quote       = new QuoteToken();
        _poolAddress = new ERC20PoolFactory().deployPool(address(_collateral), address(_quote));
        _pool        = ERC20Pool(_poolAddress);  

        _lender     = new UserWithQuoteToken();
        _borrower   = new UserWithCollateral();

        _quote.mint(address(_lender), 200_000 * 1e18);
        _collateral.mint(address(_borrower), 200_000 * 1e18);

        _lender.approveToken(_quote, address(_pool), 200_000 * 1e18);
        _borrower.approveToken(_collateral, address(_pool), 200_000 * 1e18);
    }

    // @notice:Tests pool factory inputs match the pool created
    function testDeploy() external {
        assertEq(address(_collateral), address(_pool.collateral()));
        assertEq(address(_quote),      address(_pool.quoteToken()));
    }

    function testEmptyBucket() external {
        (
            ,
            ,
            ,
            uint256 deposit,
            uint256 debt,
            uint256 bucketInflator,
            uint256 lpOutstanding,
            uint256 bucketCollateral
        ) = _pool.bucketAt(_p1004);

        assertEq(deposit,          0);
        assertEq(debt,             0);
        assertEq(bucketInflator,   0);
        assertEq(lpOutstanding,    0);
        assertEq(bucketCollateral, 0);

        (, , , deposit, debt, bucketInflator, lpOutstanding, bucketCollateral) = _pool.bucketAt(_p2793);

        assertEq(deposit,          0);
        assertEq(debt,             0);
        assertEq(bucketInflator,   0);
        assertEq(lpOutstanding,    0);
        assertEq(bucketCollateral, 0);
    }

    // @notice: Check that initialize can only be called once
    function testInitialize() external {
        uint256 initialInflator = 1 * 10**27;

        assertEq(_pool.inflatorSnapshot(),           initialInflator);
        assertEq(_pool.lastInflatorSnapshotUpdate(), 0);

        // Add quote tokens to the pool to allow initial values to change
        _lender.addQuoteToken(_pool, address(_lender), 10_000 * 1e18, _p4000);

        // add time to enable the inflator to update
        skip(8200);

        _borrower.addCollateral(_pool, 2 * 1e18);
        _borrower.borrow(_pool, 1000 * 1e18, 3000 * 1e18);

        assertGt(_pool.inflatorSnapshot(),           initialInflator);
        assertEq(_pool.lastInflatorSnapshotUpdate(), 8200);

        // Attempt to call initialize() to reset global variables and check for revert
        vm.expectRevert(IPool.AlreadyInitialized.selector);
        _pool.initialize();

        // check that global variables weren't reset
        assertGt(_pool.inflatorSnapshot(),           initialInflator);
        assertEq(_pool.lastInflatorSnapshotUpdate(), 8200);
    }

}
