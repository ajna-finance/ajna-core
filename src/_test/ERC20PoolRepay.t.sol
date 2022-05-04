// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.11;

import { ERC20Pool }        from "../ERC20Pool.sol";
import { ERC20PoolFactory } from "../ERC20PoolFactory.sol";

import { IPool } from "../interfaces/IPool.sol";

import { DSTestPlus }                             from "./utils/DSTestPlus.sol";
import { CollateralToken, QuoteToken }            from "./utils/Tokens.sol";
import { UserWithCollateral, UserWithQuoteToken } from "./utils/Users.sol";

contract ERC20PoolRepayTest is DSTestPlus {

    CollateralToken    internal _collateral;
    ERC20Pool          internal _pool;
    QuoteToken         internal _quote;
    UserWithCollateral internal _borrower;
    UserWithCollateral internal _borrower2;
    UserWithQuoteToken internal _lender;

    function setUp() external {
        _collateral = new CollateralToken();
        _quote      = new QuoteToken();
        _pool       = new ERC20PoolFactory().deployPool(address(_collateral), address(_quote));
        _borrower   = new UserWithCollateral();
        _borrower2  = new UserWithCollateral();
        _lender     = new UserWithQuoteToken();

        _collateral.mint(address(_borrower), 100 * 1e18);
        _collateral.mint(address(_borrower2), 100 * 1e18);
        _quote.mint(address(_lender), 200_000 * 1e18);

        _borrower.approveToken(_collateral, address(_pool), 100 * 1e18);
        _borrower2.approveToken(_collateral, address(_pool), 100 * 1e18);
        _lender.approveToken(_quote, address(_pool), 200_000 * 1e18);
    }

    // @notice: 1 lender 1 borrower deposits quote token
    // @notice: borrows, partially repay then overpay purposefully
    function testOverRepayOneBorrower() external {
        uint256 priceHigh = _p5007;
        uint256 priceMid  = _p4000;
        uint256 priceLow  = _p3010;

        // lender deposits 10000 DAI in 3 buckets each
        _lender.addQuoteToken(_pool, address(_lender), 10_000 * 1e18, priceHigh);
        skip(14);

        _lender.addQuoteToken(_pool, address(_lender), 10_000 * 1e18, priceMid);
        skip(14);

        _lender.addQuoteToken(_pool, address(_lender), 10_000 * 1e18, priceLow);

        // borrower starts with 10_000 DAI and deposit 100 collateral
        _quote.mint(address(_borrower), 10_000 * 1e18);
        _borrower.approveToken(_quote, address(_pool), 100_000 * 1e18);
        _borrower.addCollateral(_pool, 100 * 1e18);

        // check balances
        assertEq(_collateral.balanceOf(address(_borrower)), 0);
        assertEq(_collateral.balanceOf(address(_pool)),     100 * 1e18);

        assertEq(_pool.totalCollateral(), 100 * 1e27);

        // borrower takes loan of 25_000 DAI from 3 buckets
        _borrower.borrow(_pool, 25_000 * 1e18, 2_500 * 1e18);

        // check balances
        assertEq(_pool.totalQuoteToken(),                          5_000 * 1e27);
        assertEq(_pool.totalDebt(),                                25_000 * 1e27);
        assertEq(_pool.lup(),                                      priceLow);
        assertEq(_pool.getEncumberedCollateral(_pool.totalDebt()), 8.303187167021213219818093536 * 1e27);

        assertEq(_quote.balanceOf(address(_borrower)), 35_000 * 1e18);
        assertEq(_quote.balanceOf(address(_pool)),     5_000 * 1e18);

        // check borrower
        (   uint256 borrowerDebt,
            uint256 borrowerPendingDebt,
            uint256 depositedCollateral,
            , , , ) = _pool.getBorrowerInfo(address(_borrower));
        assertEq(borrowerDebt,        25_000 * 1e27);
        assertEq(borrowerPendingDebt, 25_000.0022196855356439486784 * 1e27);
        assertEq(depositedCollateral, 100 * 1e27);

        // repay partially debt w/ 10_000 DAI
        skip(8200);
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(_borrower), address(_pool), 10_000 * 1e18);
        vm.expectEmit(true, true, false, true);
        emit Repay(address(_borrower), priceMid, 10_000 * 1e27);
        _borrower.repay(_pool, 10_000 * 1e18);

        // check balances
        assertEq(_pool.totalQuoteToken(),                          15_000 * 1e27);
        assertEq(_pool.totalDebt(),                                15_000.32724719480886836644175 * 1e27);
        assertEq(_pool.lup(),                                      priceMid);
        assertEq(_pool.getEncumberedCollateral(_pool.totalDebt()), 3.749212295813495561695123222 * 1e27);
        assertEq(_quote.balanceOf(address(_borrower)),             25_000 * 1e18);
        assertEq(_quote.balanceOf(address(_pool)),                 15_000 * 1e18);

        // check borrower debt
        (borrowerDebt, depositedCollateral, ) = _pool.borrowers(address(_borrower));
        assertEq(borrowerDebt,        15_000.32724719480886836644175 * 1e27);
        assertEq(depositedCollateral, 100 * 1e27);

        // overpay debt w/ repay 16_000 DAI
        skip(8200);
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(_borrower), address(_pool), 15_000.913648922084090343 * 1e18);
        vm.expectEmit(true, true, false, true);
        emit Repay(
            address(_borrower),
            0,
            15_000.913648922084090343510876438 * 1e27
        );
        _borrower.repay(_pool, 16_000 * 1e18);

        // check balances
        assertEq(_pool.totalQuoteToken(),                          30_000.913648922084090343510876438 * 1e27);
        assertEq(_pool.totalDebt(),                                0);
        assertEq(_pool.lup(),                                      0);
        assertEq(_pool.getEncumberedCollateral(_pool.totalDebt()), 0);
        assertEq(_pool.getPendingPoolInterest(),                   0);
        assertEq(_quote.balanceOf(address(_borrower)),             9_999.086351077915909657 * 1e18);
        assertEq(_quote.balanceOf(address(_pool)),                 30_000.913648922084090343 * 1e18);

        // check borrower debt
        (borrowerDebt, borrowerPendingDebt, depositedCollateral, , , , ) = _pool.getBorrowerInfo(
            address(_borrower)
        );
        assertEq(borrowerDebt,        0);
        assertEq(depositedCollateral, 100 * 1e27);
        assertEq(borrowerPendingDebt, 0);
    }

    // @notice: 1 lender 2 borrowers deposits quote token
    // @notice: borrows, repays, withdraws collateral
    // @notice: borrower reverts:
    // @notice:     attempts to repay with no debt
    // @notice:     attempts to repay with insufficent balance
    function testRepayTwoBorrower() external {
        uint256 priceHigh = _p5007;
        uint256 priceMid = _p4000;
        uint256 priceLow = _p3010;

        // lender deposits 10000 DAI in 3 buckets each
        _lender.addQuoteToken(_pool, address(_lender), 10_000 * 1e18, priceHigh);
        _lender.addQuoteToken(_pool, address(_lender), 10_000 * 1e18, priceMid);
        _lender.addQuoteToken(_pool, address(_lender), 10_000 * 1e18, priceLow);

        // borrower starts with 10_000 DAI and deposit 100 collateral
        _quote.mint(address(_borrower), 10_000 * 1e18);
        _borrower.approveToken(_quote, address(_pool), 100_000 * 1e18);
        _borrower.addCollateral(_pool, 100 * 1e18);

        // borrower2 starts with 10_000 DAI and deposit 100 collateral
        _quote.mint(address(_borrower2), 10_000 * 1e18);
        _borrower2.approveToken(_quote, address(_pool), 100_000 * 1e18);
        _borrower2.addCollateral(_pool, 100 * 1e18);

        // check balances
        assertEq(_collateral.balanceOf(address(_borrower)),  0);
        assertEq(_collateral.balanceOf(address(_borrower2)), 0);
        assertEq(_collateral.balanceOf(address(_pool)),      200 * 1e18);

        assertEq(_pool.totalCollateral(), 200 * 1e27);

        // repay should revert if no debt
        vm.expectRevert(IPool.NoDebtToRepay.selector);
        _borrower.repay(_pool, 10_000 * 1e18);

        // borrower takes loan of 25_000 DAI from 3 buckets
        _borrower.borrow(_pool, 25_000 * 1e18, 2_500 * 1e18);
        // borrower2 takes loan of 2_000 DAI from 3 buckets
        _borrower2.borrow(_pool, 2_000 * 1e18, 1 * 1e18);

        // check balances
        assertEq(_pool.totalQuoteToken(),                          3_000 * 1e27);
        assertEq(_pool.totalDebt(),                                27_000 * 1e27);
        assertEq(_pool.hpb(),                                      priceHigh);
        assertEq(_pool.lup(),                                      priceLow);
        assertEq(_pool.getEncumberedCollateral(_pool.totalDebt()), 8.967442140382910277403541019 * 1e27);

        assertEq(_quote.balanceOf(address(_borrower)),  35_000 * 1e18);
        assertEq(_quote.balanceOf(address(_borrower2)), 12_000 * 1e18);
        assertEq(_quote.balanceOf(address(_pool)),      3_000 * 1e18);

        // check buckets
        (, , , uint256 deposit, uint256 debt, , , ) = _pool.bucketAt(priceHigh);
        assertEq(deposit, 0);
        assertEq(debt,    10_000 * 1e27);

        (, , , deposit, debt, , , ) = _pool.bucketAt(priceMid);
        assertEq(deposit, 0);
        assertEq(debt,    10_000 * 1e27);

        (, , , deposit, debt, , , ) = _pool.bucketAt(priceLow);
        assertEq(deposit, 3_000 * 1e27);
        assertEq(debt,    7_000 * 1e27);

        // check borrower
        (   uint256 borrowerDebt,
            uint256 borrowerPendingDebt,
            uint256 depositedCollateral,
            , , , ) = _pool.getBorrowerInfo(address(_borrower));
        assertEq(borrowerDebt,        25_000 * 1e27);
        assertEq(borrowerPendingDebt, 25_000 * 1e27);
        assertEq(depositedCollateral, 100 * 1e27);

        // check borrower2
        (borrowerDebt, , depositedCollateral, , , ,) = _pool.getBorrowerInfo(address(_borrower2));
        assertEq(borrowerDebt,        2_000 * 1e27);
        assertEq(depositedCollateral, 100 * 1e27);
        // repay should revert if amount not available
        vm.expectRevert(IPool.InsufficientBalanceForRepay.selector);
        _borrower.repay(_pool, 50_000 * 1e18);

        // repay debt partially 10_000 DAI
        skip(8200);
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(_borrower), address(_pool), 10_000 * 1e18);
        vm.expectEmit(true, true, false, true);
        emit Repay(address(_borrower), priceMid, 10_000 * 1e27);
        _borrower.repay(_pool, 10_000 * 1e18);

        // check buckets
        (, , , deposit, debt, , , ) = _pool.bucketAt(priceHigh);
        assertEq(deposit, 0);
        assertEq(debt,    10_000 * 1e27);

        (, , , deposit, debt, , , ) = _pool.bucketAt(priceMid);
        assertEq(deposit, 2_999.908992305483835689019583 * 1e27);
        assertEq(debt,    7_000.221018686682113326666727 * 1e27);

        (, , , deposit, debt, , , ) = _pool.bucketAt(priceLow);
        assertEq(deposit, 10_000.091007694516164310980417 * 1e27);
        assertEq(debt,    0);

        // check balances
        assertEq(_pool.totalQuoteToken(),                          13_000 * 1e27);
        assertEq(_pool.totalDebt(),                                17_000.351029678848062342353037 * 1e27);
        assertEq(_pool.lup(),                                      priceMid);
        assertEq(_pool.getEncumberedCollateral(_pool.totalDebt()), 4.249102307120473073413233733 * 1e27);

        assertEq(_quote.balanceOf(address(_borrower)), 25_000 * 1e18);
        assertEq(_quote.balanceOf(address(_pool)),     13_000 * 1e18);

        // check borrower debt
        (borrowerDebt, depositedCollateral, ) = _pool.borrowers(address(_borrower));
        assertEq(borrowerDebt,        15_000.325027480414872539215775 * 1e27);
        assertEq(depositedCollateral, 100 * 1e27);

        // borrower attempts to overpay to cover 15_000 DAI plus accumulated debt
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(_borrower), address(_pool), 15_000.715071443825413103 * 1e18);
        vm.expectEmit(true, true, false, true);
        emit Repay(address(_borrower), priceHigh, 15_000.715071443825413103419758346 * 1e27);
        _borrower.repay(_pool, 15_001 * 1e18);

        (borrowerDebt, borrowerPendingDebt, depositedCollateral, , , ,) = _pool.getBorrowerInfo(address(_borrower));

        assertEq(borrowerDebt,        0);
        assertEq(depositedCollateral, 100 * 1e27);
        assertEq(borrowerPendingDebt, 0);

        // determine pending debt across all buckets
        uint256 bucketPendingDebt = 0;
        (, , , , debt, , , ) = _pool.bucketAt(priceHigh);
        bucketPendingDebt += debt;
        bucketPendingDebt += _pool.getPendingBucketInterest(priceHigh);

        (, , , , debt, , , ) = _pool.bucketAt(priceMid);
        bucketPendingDebt += debt;
        bucketPendingDebt += _pool.getPendingBucketInterest(priceMid);

        (, , , , debt, , , ) = _pool.bucketAt(priceLow);
        bucketPendingDebt += debt;
        bucketPendingDebt += _pool.getPendingBucketInterest(priceLow);

        assertEq(_pool.totalQuoteToken(), 28_000.715071443825413103419758346 * 1e27);
        assertEq(_pool.totalDebt(),       1_999.635958235022649238933278654 * 1e27);

        // tie out pending debt
        uint256 poolPendingDebt = _pool.totalDebt() + _pool.getPendingPoolInterest();
        // first borrower repaid; only second borrower has debt
        (, borrowerPendingDebt, , , , , ) = _pool.getBorrowerInfo(address(_borrower2));
        // TODO: Pending debt should tie within 1 RAY, but it is ~0.4 quote tokens off.
        //        assertEq(bucketPendingDebt, borrowerPendingDebt);
        assertEq(bucketPendingDebt, poolPendingDebt);
        //        assertEq(borrowerPendingDebt, poolPendingDebt);

        assertEq(_pool.hpb(),                                      priceHigh);
        assertEq(_pool.lup(),                                      priceHigh);
        assertEq(_pool.getEncumberedCollateral(_pool.totalDebt()), 0.399316685558313112714566594 * 1e27);

        assertEq(_quote.balanceOf(address(_borrower)), 9_999.284928556174586897 * 1e18);
        assertEq(_quote.balanceOf(address(_pool)),     28_000.715071443825413103 * 1e18);

        // borrower2 attempts to repay 2_000 DAI plus accumulated debt
        (borrowerDebt, depositedCollateral, ) = _pool.borrowers(address(_borrower2));
        assertEq(borrowerDebt,        2_000 * 1e27);
        assertEq(depositedCollateral, 100 * 1e27);
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(_borrower2), address(_pool), 2000.026002198433189803 * 1e18);
        vm.expectEmit(true, true, false, true);
        emit Repay(address(_borrower2), 0, 2000.026002198433189803137262 * 1e27);

        // repay entire debt
        _borrower2.repay(_pool, 2_010 * 1e18);

        (, , , deposit, debt, , , ) = _pool.bucketAt(priceHigh);
        assertEq(deposit, 10_000.13001099216594901568631 * 1e27);
        assertEq(debt,    0);

        assertEq(_pool.getPendingBucketInterest(priceHigh), 0);

        (, , , deposit, debt, , , ) = _pool.bucketAt(priceMid);
        assertEq(deposit, 10_000.13001099216594901568631 * 1e27);
        assertEq(debt,    0);

        assertEq(_pool.getPendingBucketInterest(priceMid), 0);

        (, , , deposit, debt, , , ) = _pool.bucketAt(priceLow);
        assertEq(deposit, 10_000.091007694516164310980417 * 1e27);
        assertEq(debt,    0);

        assertEq(_pool.getPendingBucketInterest(priceLow), 0);

        (borrowerDebt, depositedCollateral, ) = _pool.borrowers(address(_borrower2));
        assertEq(borrowerDebt, 0);

        (, borrowerPendingDebt, , , , , ) = _pool.getBorrowerInfo(address(_borrower2));
        assertEq(borrowerPendingDebt, 0);
        assertEq(depositedCollateral, 100 * 1e27);

        assertEq(_pool.totalQuoteToken(),                          30_000.741073642258602906557020346 * 1e27);
        assertEq(_pool.totalDebt(),                                0);
        assertEq(_pool.getPendingPoolInterest(),                   0);
        assertEq(_pool.lup(),                                      0);
        assertEq(_pool.getEncumberedCollateral(_pool.totalDebt()), 0);

        assertEq(_quote.balanceOf(address(_borrower2)), 9_999.973997801566810197 * 1e18);
        assertEq(_quote.balanceOf(address(_pool)),      30_000.741073642258602906 * 1e18);

        assertEq(_pool.hpb(), priceHigh);
        assertEq(_pool.lup(), 0);

        // remove deposited collateral
        _borrower.removeCollateral(_pool, 100 * 1e18);
        assertEq(_collateral.balanceOf(address(_borrower)), 100 * 1e18);

        _borrower2.removeCollateral(_pool, 100 * 1e18);
        assertEq(_collateral.balanceOf(address(_borrower2)), 100 * 1e18);
    }

}
