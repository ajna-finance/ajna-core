// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.11;

import { ERC20Pool }        from "../../ERC20Pool.sol";
import { ERC20PoolFactory } from "../../ERC20PoolFactory.sol";

import { IPool } from "../../interfaces/IPool.sol";

import { DSTestPlus }                             from "../utils/DSTestPlus.sol";
import { CollateralToken, QuoteToken }            from "../utils/Tokens.sol";
import { UserWithCollateral, UserWithQuoteToken } from "../utils/Users.sol";

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

    /**********************************************************/
    /*** Manipulation mitigation tests - fees and penalties ***/
    /**********************************************************/

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

   function testRemoveQuoteTokenPenalty() external {
        uint256 priceHigh = _p2000;
        uint256 priceMed  = _p1004;
        uint256 priceLow  = _p502;

        _lender.addQuoteToken(_pool, address(_lender), 2_000 * 1e18, priceHigh);
        _lender.addQuoteToken(_pool, address(_lender), 3_000 * 1e18, priceMed);
        _lender.addQuoteToken(_pool, address(_lender), 1_000 * 1e18, priceLow);

        // check balances
        assertEq(_quote.balanceOf(address(_pool)),   6_000 * 1e18);
        assertEq(_quote.balanceOf(address(_lender)), 194_000 * 1e18);

        // check bucket
        (, , , uint256 deposit, , , uint256 lpOutstanding, ) = _pool.bucketAt(priceHigh);
        uint256 bipCredit = _pool.bipAt(priceHigh);
        assertEq(deposit,       2_000 * 1e18);
        assertEq(lpOutstanding, 2_000 * 1e27);
        assertEq(bipCredit,     0);

        assertEq(_pool.lpBalance(address(_lender), priceHigh), 2_000 * 1e27);

        // test remove all amount with penalty from one bucket
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(_pool), address(_lender), 1_998 * 1e18);
        vm.expectEmit(true, true, false, true);
        emit RemoveQuoteToken(address(_lender), priceHigh, 1_998 * 1e18, 0);
        _lender.removeQuoteToken(_pool, address(_lender), 2_000 * 1e18, priceHigh);

        // check balances
        assertEq(_quote.balanceOf(address(_pool)),   4_002 * 1e18);
        assertEq(_quote.balanceOf(address(_lender)), 195_998 * 1e18);

        // check bucket
        (, , , deposit, , , lpOutstanding, ) = _pool.bucketAt(priceHigh);
        bipCredit = _pool.bipAt(priceHigh);
        assertEq(deposit,       0);
        assertEq(lpOutstanding, 0);
        assertEq(bipCredit,     2 * 1e18);

        assertEq(_pool.lpBalance(address(_lender), priceHigh), 0);

        // test remove entire amount in 2 steps with penalty 
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(_pool), address(_lender), 499.5 * 1e18);
        vm.expectEmit(true, true, false, true);
        emit RemoveQuoteToken(address(_lender), priceMed, 499.5 * 1e18, 0);
        _lender.removeQuoteToken(_pool, address(_lender), 500 * 1e18, priceMed);

        // check balances
        assertEq(_quote.balanceOf(address(_pool)),   3_502.5 * 1e18);
        assertEq(_quote.balanceOf(address(_lender)), 196_497.5 * 1e18);

        // check bucket
        (, , , deposit, , , lpOutstanding, ) = _pool.bucketAt(priceMed);
        bipCredit = _pool.bipAt(priceMed);
        assertEq(deposit,       2_500 * 1e18);
        assertEq(lpOutstanding, 2_500 * 1e27);
        assertEq(bipCredit,     0.5 * 1e18);

        assertEq(_pool.lpBalance(address(_lender), priceMed), 2_500 * 1e27);

        vm.expectEmit(true, true, false, true);
        emit Transfer(address(_pool), address(_lender), 2_497.5 * 1e18);
        vm.expectEmit(true, true, false, true);
        emit RemoveQuoteToken(address(_lender), priceMed, 2_497.5 * 1e18, 0);
        _lender.removeQuoteToken(_pool, address(_lender), 2_500 * 1e18, priceMed);

        // check balances
        assertEq(_quote.balanceOf(address(_pool)),   1_005 * 1e18);
        assertEq(_quote.balanceOf(address(_lender)), 198_995 * 1e18);

        // check bucket
        (, , , deposit, , , lpOutstanding, ) = _pool.bucketAt(priceMed);
        bipCredit = _pool.bipAt(priceMed);
        assertEq(deposit,       0 * 1e18);
        assertEq(lpOutstanding, 0 * 1e27);
        assertEq(bipCredit,     3 * 1e18);

        assertEq(_pool.lpBalance(address(_lender), priceMed), 0);

        // skip > 24h no penalty should occur
        skip(3600 * 24 + 1);

        vm.expectEmit(true, true, false, true);
        emit Transfer(address(_pool), address(_lender), 500 * 1e18);
        vm.expectEmit(true, true, false, true);
        emit RemoveQuoteToken(address(_lender), priceLow, 500 * 1e18, 0);
        _lender.removeQuoteToken(_pool, address(_lender), 500 * 1e18, priceLow);

        // check balances
        assertEq(_quote.balanceOf(address(_pool)),   505 * 1e18);
        assertEq(_quote.balanceOf(address(_lender)), 199_495 * 1e18);

        // check bucket
        (, , , deposit, , , lpOutstanding, ) = _pool.bucketAt(priceLow);
        bipCredit = _pool.bipAt(priceLow);
        assertEq(deposit,       500 * 1e18);
        assertEq(lpOutstanding, 500 * 1e27);
        assertEq(bipCredit,     0 * 1e18);

        assertEq(_pool.lpBalance(address(_lender), priceLow), 500 * 1e27);

        // deposit at a different bucket should not impose penalty on current bucket
        _lender.addQuoteToken(_pool, address(_lender), 2_000 * 1e18, priceHigh);

        vm.expectEmit(true, true, false, true);
        emit Transfer(address(_pool), address(_lender), 100 * 1e18);
        vm.expectEmit(true, true, false, true);
        emit RemoveQuoteToken(address(_lender), priceLow, 100 * 1e18, 0);
        _lender.removeQuoteToken(_pool, address(_lender), 100 * 1e18, priceLow);

        // check balances
        assertEq(_quote.balanceOf(address(_pool)),   2_405 * 1e18);
        assertEq(_quote.balanceOf(address(_lender)), 197_595 * 1e18);

        // check bucket
        (, , , deposit, , , lpOutstanding, ) = _pool.bucketAt(priceLow);
        bipCredit = _pool.bipAt(priceLow);
        assertEq(deposit,       400 * 1e18);
        assertEq(lpOutstanding, 400 * 1e27);
        assertEq(bipCredit,     0 * 1e18);

        assertEq(_pool.lpBalance(address(_lender), priceLow), 400 * 1e27);

        // deposit in current bucket should reactivate penalty
        _lender.addQuoteToken(_pool, address(_lender), 2_000 * 1e18, priceLow);

        vm.expectEmit(true, true, false, true);
        emit Transfer(address(_pool), address(_lender), 2_397.6 * 1e18);
        vm.expectEmit(true, true, false, true);
        emit RemoveQuoteToken(address(_lender), priceLow, 2_397.6 * 1e18, 0);
        _lender.removeQuoteToken(_pool, address(_lender), 2_400 * 1e18, priceLow);

        // check balances
        assertEq(_quote.balanceOf(address(_pool)),   2_007.4 * 1e18);
        assertEq(_quote.balanceOf(address(_lender)), 197_992.6 * 1e18);

        // check bucket
        (, , , deposit, , , lpOutstanding, ) = _pool.bucketAt(priceLow);
        bipCredit = _pool.bipAt(priceLow);
        assertEq(deposit,       0 * 1e18);
        assertEq(lpOutstanding, 0 * 1e27);
        assertEq(bipCredit,     2.4 * 1e18);

        assertEq(_pool.lpBalance(address(_lender), priceLow), 0 * 1e27);
    }

   function testMoveQuoteTokenPenalty() external {
        uint256 priceHigh = _p2000;
        uint256 priceMed  = _p1004;
        uint256 priceLow  = _p502;

        _lender.addQuoteToken(_pool, address(_lender), 2_000 * 1e18, priceHigh);
        _lender.addQuoteToken(_pool, address(_lender), 3_000 * 1e18, priceMed);
        _lender.addQuoteToken(_pool, address(_lender), 1_000 * 1e18, priceLow);

        _lender1.addQuoteToken(_pool, address(_lender1), 500 * 1e18, priceHigh);
        _lender1.addQuoteToken(_pool, address(_lender1), 1_000 * 1e18, priceMed);
        _lender1.addQuoteToken(_pool, address(_lender1), 1_500 * 1e18, priceLow);

        // check balances
        assertEq(_quote.balanceOf(address(_pool)),    9_000 * 1e18);
        assertEq(_quote.balanceOf(address(_lender)),  194_000 * 1e18);
        assertEq(_quote.balanceOf(address(_lender1)), 197_000 * 1e18);

        // check bucket
        (, , , uint256 deposit, , , uint256 lpOutstanding, ) = _pool.bucketAt(priceLow);
        uint256 bipCredit = _pool.bipAt(priceLow);
        assertEq(deposit,       2_500 * 1e18);
        assertEq(lpOutstanding, 2_500 * 1e27);
        assertEq(bipCredit,     0);

        assertEq(_pool.lpBalance(address(_lender), priceLow), 1_000 * 1e27);
        assertEq(_pool.lpBalance(address(_lender1), priceLow), 1_500 * 1e27);

        // there should be no penalty if moving to a higher bucket
        vm.expectEmit(true, true, true, true);
        emit MoveQuoteToken(address(_lender), priceLow, priceMed, 500 * 1e18, 0);
        _lender.moveQuoteToken(_pool, address(_lender), 500 * 1e18, priceLow, priceMed);

        // check buckets
        (, , , deposit, , , lpOutstanding, ) = _pool.bucketAt(priceLow);
        bipCredit = _pool.bipAt(priceLow);
        assertEq(deposit,       2_000 * 1e18);
        assertEq(lpOutstanding, 2_000 * 1e27);
        assertEq(bipCredit,     0);

        assertEq(_pool.lpBalance(address(_lender), priceLow),  500 * 1e27);
        assertEq(_pool.lpBalance(address(_lender1), priceLow), 1_500 * 1e27);

        (, , , deposit, , , lpOutstanding, ) = _pool.bucketAt(priceMed);
        bipCredit = _pool.bipAt(priceMed);
        assertEq(deposit,       4_500 * 1e18);
        assertEq(lpOutstanding, 4_500 * 1e27);
        assertEq(bipCredit,     0);

        assertEq(_pool.lpBalance(address(_lender), priceMed),  3_500 * 1e27);
        assertEq(_pool.lpBalance(address(_lender1), priceMed), 1_000 * 1e27);

        // apply penalty if moving to a lower bucket
        vm.expectEmit(true, true, true, true);
        emit MoveQuoteToken(address(_lender), priceHigh, priceLow, 998.502212369222621532 * 1e18, 0);
        _lender.moveQuoteToken(_pool, address(_lender), 1_000 * 1e18, priceHigh, priceLow);

        // check buckets
        (, , , deposit, , , lpOutstanding, ) = _pool.bucketAt(priceLow);
        bipCredit = _pool.bipAt(priceLow);
        assertEq(deposit,       2_998.502212369222621532 * 1e18);
        assertEq(lpOutstanding, 2_998.502212369222621532000000000 * 1e27);
        assertEq(bipCredit,     0);

        assertEq(_pool.lpBalance(address(_lender), priceLow),  1_498.502212369222621532000000000 * 1e27);
        assertEq(_pool.lpBalance(address(_lender1), priceLow), 1_500 * 1e27);

        (, , , deposit, , , lpOutstanding, ) = _pool.bucketAt(priceHigh);
        bipCredit = _pool.bipAt(priceHigh);
        assertEq(deposit,       1_501.497787630777378468 * 1e18);
        assertEq(lpOutstanding, 1_500 * 1e27);
        assertEq(bipCredit,     1.497787630777378468 * 1e18);

        assertEq(_pool.lpBalance(address(_lender), priceHigh),  1_000 * 1e27);
        assertEq(_pool.lpBalance(address(_lender1), priceHigh), 500 * 1e27);

        (, , , deposit, , , lpOutstanding, ) = _pool.bucketAt(priceMed);
        bipCredit = _pool.bipAt(priceMed);
        assertEq(deposit,       4_500 * 1e18);
        assertEq(lpOutstanding, 4_500 * 1e27);
        assertEq(bipCredit,     0);

        assertEq(_pool.lpBalance(address(_lender), priceMed),  3_500 * 1e27);
        assertEq(_pool.lpBalance(address(_lender1), priceMed), 1_000 * 1e27);

        // skip > 24h no penalty should occur
        skip(3600 * 24 + 1);

        vm.expectEmit(true, true, true, true);
        emit MoveQuoteToken(address(_lender1), priceHigh, priceMed, 500.499262543592459489 * 1e18, 0);
        _lender1.moveQuoteToken(_pool, address(_lender1), 510 * 1e18, priceHigh, priceMed);

        // check buckets
        (, , , deposit, , , lpOutstanding, ) = _pool.bucketAt(priceMed);
        bipCredit = _pool.bipAt(priceMed);
        assertEq(deposit,       5_000.499262543592459489 * 1e18);
        assertEq(lpOutstanding, 5_000.499262543592459489000000000 * 1e27);
        assertEq(bipCredit,     0);

        assertEq(_pool.lpBalance(address(_lender), priceMed),  3_500 * 1e27);
        assertEq(_pool.lpBalance(address(_lender1), priceMed), 1_500.499262543592459489000000000 * 1e27);

        (, , , deposit, , , lpOutstanding, ) = _pool.bucketAt(priceHigh);
        bipCredit = _pool.bipAt(priceHigh);
        assertEq(deposit,       1_000.998525087184918979 * 1e18);
        assertEq(lpOutstanding, 1_000 * 1e27);
        assertEq(bipCredit,     1.497787630777378468 * 1e18);

        assertEq(_pool.lpBalance(address(_lender), priceHigh),  1_000 * 1e27);
        assertEq(_pool.lpBalance(address(_lender1), priceHigh), 0);

        // lender deposit in priceHigh bucket, check penalty applies only if moving from priceHigh bucket
        _lender.addQuoteToken(_pool, address(_lender), 2_000 * 1e18, priceHigh);

        vm.expectEmit(true, true, true, true);
        emit MoveQuoteToken(address(_lender), priceHigh, priceMed, 1_999.004768043588443074 * 1e18, 0);
        _lender.moveQuoteToken(_pool, address(_lender), 2_000 * 1e18, priceHigh, priceMed);

        (, , , deposit, , , lpOutstanding, ) = _pool.bucketAt(priceHigh);
        bipCredit = _pool.bipAt(priceHigh);
        assertEq(deposit,       1_001.993757043596475905 * 1e18);
        assertEq(lpOutstanding, 1_000 * 1e27);
        assertEq(bipCredit,     2.493019587188935394 * 1e18);

        assertEq(_pool.lpBalance(address(_lender), priceHigh),  1_000 * 1e27);
        assertEq(_pool.lpBalance(address(_lender1), priceHigh), 0 * 1e27);

        (, , , deposit, , , lpOutstanding, ) = _pool.bucketAt(priceMed);
        bipCredit = _pool.bipAt(priceMed);
        assertEq(deposit,       6_999.504030587180902563 * 1e18);
        assertEq(lpOutstanding, 6_999.504030587180902563000000000 * 1e27);
        assertEq(bipCredit,     0);

        assertEq(_pool.lpBalance(address(_lender), priceMed),  5_499.004768043588443074000000000 * 1e27);
        assertEq(_pool.lpBalance(address(_lender1), priceMed), 1_500.499262543592459489000000000 * 1e27);

        // penalty should not apply if moving from priceMed bucket to priceLow
        vm.expectEmit(true, true, true, true);
        emit MoveQuoteToken(address(_lender), priceMed, priceLow, 2_000 * 1e18, 0);
        _lender.moveQuoteToken(_pool, address(_lender), 2_000 * 1e18, priceMed, priceLow);

        (, , , deposit, , , lpOutstanding, ) = _pool.bucketAt(priceMed);
        bipCredit = _pool.bipAt(priceMed);
        assertEq(deposit,       4_999.504030587180902563 * 1e18);
        assertEq(lpOutstanding, 4_999.504030587180902563000000000 * 1e27);
        assertEq(bipCredit,     0);

        assertEq(_pool.lpBalance(address(_lender), priceMed),  3_499.004768043588443074000000000 * 1e27);
        assertEq(_pool.lpBalance(address(_lender1), priceMed), 1_500.499262543592459489000000000 * 1e27);

        (, , , deposit, , , lpOutstanding, ) = _pool.bucketAt(priceLow);
        bipCredit = _pool.bipAt(priceLow);
        assertEq(deposit,       4_998.502212369222621532 * 1e18);
        assertEq(lpOutstanding, 4_998.502212369222621532000000000 * 1e27);
        assertEq(bipCredit,     0);

        assertEq(_pool.lpBalance(address(_lender), priceLow),  3_498.502212369222621532000000000 * 1e27);
        assertEq(_pool.lpBalance(address(_lender1), priceLow), 1_500 * 1e27);
   }

}
