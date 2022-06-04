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
    UserWithCollateral internal _borrower1;
    UserWithCollateral internal _borrower2;
    UserWithQuoteToken internal _lender;
    UserWithQuoteToken internal _lender1;
    UserWithQuoteToken internal _lender2;

    function setUp() external {
        _collateral  = new CollateralToken();
        _quote       = new QuoteToken();
        _poolAddress = new ERC20PoolFactory().deployPool(address(_collateral), address(_quote));
        _pool        = ERC20Pool(_poolAddress);

        _lender      = new UserWithQuoteToken();
        _lender1     = new UserWithQuoteToken();
        _lender2     = new UserWithQuoteToken();
        _borrower    = new UserWithCollateral();
        _borrower1   = new UserWithCollateral();
        _borrower2   = new UserWithCollateral();

        _quote.mint(address(_lender), 200_000 * 1e18);
        _quote.mint(address(_lender1), 200_000 * 1e18);
        _quote.mint(address(_lender2), 200_000 * 1e18);
        _collateral.mint(address(_borrower), 200_000 * 1e18);
        _collateral.mint(address(_borrower1), 200_000 * 1e18);
        _collateral.mint(address(_borrower2), 200_000 * 1e18);

        _lender.approveToken(_quote, address(_pool), 200_000 * 1e18);
        _lender1.approveToken(_quote, address(_pool), 200_000 * 1e18);
        _lender2.approveToken(_quote, address(_pool), 200_000 * 1e18);
        _borrower.approveToken(_collateral, address(_pool), 200_000 * 1e18);
        _borrower.approveToken(_quote, address(_pool), 200_000 * 1e18);
        _borrower1.approveToken(_collateral, address(_pool), 200_000 * 1e18);
        _borrower1.approveToken(_quote, address(_pool), 200_000 * 1e18);
        _borrower2.approveToken(_collateral, address(_pool), 200_000 * 1e18);
        _borrower2.approveToken(_quote, address(_pool), 200_000 * 1e18);
    }

    /**
     *  @notice Tests pool factory inputs match the pool created.
     */
    function testDeploy() external {
        assertEq(address(_collateral), address(_pool.collateral()));
        assertEq(address(_quote),      address(_pool.quoteToken()));
    }

    function testEmptyBucket() external {
        (, , , uint256 deposit, uint256 debt, uint256 bucketInflator, uint256 lpOutstanding, uint256 bucketCollateral) = _pool.bucketAt(_p1004);
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

    /**
     *  @notice Check that initialize can only be called once.
     */
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
        vm.expectRevert("P:INITIALIZED");
        _pool.initialize();

        // check that global variables weren't reset
        assertGt(_pool.inflatorSnapshot(),           initialInflator);
        assertEq(_pool.lastInflatorSnapshotUpdate(), 8200);
    }

   function testDebtAccumulatorSingleBucket() external {

        _lender.addQuoteToken(_pool, address(_lender), 100_000 * 1e18, _p4000);

        skip(820000);

        _borrower.addCollateral(_pool, 200 * 1e18);
        _borrower.borrow(_pool, 1000 * 1e18, 3000 * 1e18);

        skip(820000);
        _borrower.borrow(_pool, 1000 * 1e18, 3000 * 1e18);

        (, , , , uint256 bucketDebt, , , ) = _pool.bucketAt(_p4000);
        (uint256 borrowerDebt, , , , , , ) = _pool.getBorrowerInfo(address(_borrower));
        assertEq(_pool.totalDebt(), bucketDebt);
        assertEq(_pool.totalDebt(), borrowerDebt);

        skip(820000);
        _borrower.repay(_pool, 1000 * 1e18);

        (, , , , bucketDebt, , , ) = _pool.bucketAt(_p4000);
        (borrowerDebt, , , , , , ) = _pool.getBorrowerInfo(address(_borrower));
        assertEq(_pool.totalDebt(), bucketDebt);
        assertEq(_pool.totalDebt(), borrowerDebt);

        skip(820000);
        _borrower.borrow(_pool, 3000 * 1e18, 3000 * 1e18);

        (, , , , bucketDebt, , , ) = _pool.bucketAt(_p4000);
        (borrowerDebt, , , , , , ) = _pool.getBorrowerInfo(address(_borrower));
        assertEq(_pool.totalDebt(), bucketDebt);
        assertEq(_pool.totalDebt(), borrowerDebt);

        skip(820000);
        _borrower.repay(_pool, 3000 * 1e18);

        (, , , , bucketDebt, , , ) = _pool.bucketAt(_p4000);
        (borrowerDebt, , , , , , ) = _pool.getBorrowerInfo(address(_borrower));
        assertEq(_pool.totalDebt(), bucketDebt);
        assertEq(_pool.totalDebt(), borrowerDebt);

    }

   function testManipulationMitigations() external {
        _lender.addQuoteToken(_pool, address(_lender), 100_000 * 1e18, _p4000);
        _lender1.addQuoteToken(_pool, address(_lender), 1_000 * 1e18, _p3010);

        assertEq(_pool.getPoolMinDebtAmount(), 0);
        assertEq(_pool.totalBorrowers(),       0);

        _borrower.addCollateral(_pool, 200 * 1e18);
        _borrower1.addCollateral(_pool, 200 * 1e18);
        _borrower2.addCollateral(_pool, 200 * 1e18);

        _borrower.borrow(_pool, 100 * 1e18, 3000 * 1e18);

        assertEq(_pool.getPoolMinDebtAmount(), 0.100000961538461538 * 1e18);
        assertEq(_pool.totalBorrowers(),       1);

        // should fail if trying to borrow amount < 10% of pool average debt amount
        vm.expectRevert("P:B:AMT_LT_AVG_DEBT");
        _borrower.borrow(_pool, 0.1 * 1e18, 3000 * 1e18);

        // borrowers accumulator should be incremented only if new borrower
        _borrower.borrow(_pool, 100 * 1e18, 3000 * 1e18);
        assertEq(_pool.getPoolMinDebtAmount(), 0.200001923076923077 * 1e18);
        assertEq(_pool.totalBorrowers(),       1);

        _borrower1.borrow(_pool, 100 * 1e18, 3000 * 1e18);
        assertEq(_pool.getPoolMinDebtAmount(), 0.300002884615384615 * 1e18);
        assertEq(_pool.totalBorrowers(),       2);

        _borrower2.borrow(_pool, 200 * 1e18, 3000 * 1e18);
        assertEq(_pool.getPoolMinDebtAmount(), 0.500003846153846154 * 1e18);
        assertEq(_pool.totalBorrowers(),       3);

        // repay should fail if remaining debt < 10% of pool average debt amount
        _quote.mint(address(_borrower2), 200 * 1e18);
        vm.expectRevert("P:R:AMT_LT_AVG_DEBT");
         _borrower2.repay(_pool, 199.9 * 1e18);

        _borrower2.repay(_pool, 100 * 1e18);
        assertEq(_pool.getPoolMinDebtAmount(), 0.400003846153846154 * 1e18);
        assertEq(_pool.totalBorrowers(),       3);
        _borrower2.repay(_pool, 200 * 1e18);
        assertEq(_pool.getPoolMinDebtAmount(), 0.300002884615384615 * 1e18);
        assertEq(_pool.totalBorrowers(),       2);

        // deposit should fail if amount < 10% of pool average debt amount
        vm.expectRevert("P:AQT:AMT_LT_AVG_DEBT");
        _lender2.addQuoteToken(_pool, address(_lender), 0.1 * 1e18, _p2850);

        _lender2.addQuoteToken(_pool, address(_lender), 151 * 1e18, _p2850);

        // repay all borrowers
        _quote.mint(address(_borrower), 200 * 1e18);
        _quote.mint(address(_borrower1), 200 * 1e18);

        _borrower.repay(_pool, 100 * 1e18);
        assertEq(_pool.getPoolMinDebtAmount(), 0.200002884615384615 * 1e18);
        assertEq(_pool.totalBorrowers(),       2);
        _borrower.repay(_pool, 200 * 1e18);
        assertEq(_pool.getPoolMinDebtAmount(), 0.100000961538461538 * 1e18);
        assertEq(_pool.totalBorrowers(),       1);

        _borrower1.repay(_pool, 20 * 1e18);
        assertEq(_pool.getPoolMinDebtAmount(), 0.080000961538461538 * 1e18);
        assertEq(_pool.totalBorrowers(),       1);
        _borrower1.repay(_pool, 100 * 1e18);
        assertEq(_pool.getPoolMinDebtAmount(), 0);
        assertEq(_pool.totalBorrowers(),       0);
   }

}
