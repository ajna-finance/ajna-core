// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.11;

import {DSTestPlus} from "./utils/DSTestPlus.sol";
import {UserWithCollateral, UserWithQuoteToken} from "./utils/Users.sol";
import {CollateralToken, QuoteToken} from "./utils/Tokens.sol";

import {ERC20Pool} from "../ERC20Pool.sol";

contract ERC20PoolBorrowTest is DSTestPlus {
    ERC20Pool internal pool;
    CollateralToken internal collateral;
    QuoteToken internal quote;

    UserWithCollateral internal borrower;
    UserWithCollateral internal borrower2;
    UserWithQuoteToken internal lender;

    function setUp() public {
        collateral = new CollateralToken();
        quote = new QuoteToken();

        pool = new ERC20Pool(collateral, quote);

        borrower = new UserWithCollateral();
        collateral.mint(address(borrower), 100 * 1e18);
        borrower.approveToken(collateral, address(pool), 100 * 1e18);

        borrower2 = new UserWithCollateral();
        collateral.mint(address(borrower2), 100 * 1e18);
        borrower2.approveToken(collateral, address(pool), 100 * 1e18);

        lender = new UserWithQuoteToken();
        quote.mint(address(lender), 200_000 * 1e18);
        lender.approveToken(quote, address(pool), 200_000 * 1e18);
    }

    function testBorrow() public {
        // lender deposits 10000 DAI in 5 buckets each
        lender.addQuoteToken(pool, 10_000 * 1e18, 4_000 * 1e18);
        lender.addQuoteToken(pool, 10_000 * 1e18, 3_500 * 1e18);
        lender.addQuoteToken(pool, 10_000 * 1e18, 3_000 * 1e18);
        lender.addQuoteToken(pool, 10_000 * 1e18, 2_500 * 1e18);
        lender.addQuoteToken(pool, 10_000 * 1e18, 2_000 * 1e18);

        // check pool balance
        assertEq(pool.totalQuoteToken(), 50_000 * 1e18);
        assertEq(pool.totalDebt(), 0);
        assertEq(pool.hdp(), 4_000 * 1e18);

        // should revert if borrower wants to borrow a greater amount than in pool
        vm.expectRevert("ajna/not-enough-liquidity");
        borrower.borrow(pool, 60_000 * 1e18, 2_000 * 1e18);

        // should revert if not enough collateral deposited by borrower
        vm.expectRevert("ajna/not-enough-collateral");
        borrower.borrow(pool, 10_000 * 1e18, 4_000 * 1e18);

        // borrower deposit 100 MKR collateral
        borrower.addCollateral(pool, 10 * 1e18);

        // should revert if stop price exceeded
        vm.expectRevert("ajna/stop-price-exceeded");
        borrower.borrow(pool, 15_000 * 1e18, 4_000 * 1e18);

        // should revert if not enough collateral to get the loan
        vm.expectRevert("ajna/not-enough-collateral");
        borrower.borrow(pool, 40_000 * 1e18, 2_000 * 1e18);

        // borrower deposits additional 90 MKR collateral
        borrower.addCollateral(pool, 90 * 1e18);
        // get a 21_000 DAI loan from 3 buckets, loan price should be 3000 DAI
        assertEq(pool.estimatePriceForLoan(21_000 * 1e18), 3_000 * 1e18);

        vm.expectEmit(true, false, false, true);
        emit Transfer(address(pool), address(borrower), 21_000 * 1e18);
        emit Borrow(address(borrower), 3_000 * 1e18, 21_000 * 1e18);
        borrower.borrow(pool, 21_000 * 1e18, 2_500 * 1e18);

        assertEq(quote.balanceOf(address(borrower)), 21_000 * 1e18);
        assertEq(quote.balanceOf(address(pool)), 29_000 * 1e18);
        assertEq(pool.hdp(), 4_000 * 1e18);
        assertEq(pool.lup(), 3_000 * 1e18);

        // check bucket deposit and debt at 3_000
        (, , , uint256 deposit, uint256 debt, , ) = pool.bucketAt(3_000 * 1e18);
        assertEq(deposit - debt, 9_000 * 1e18);
        // check pool debt
        assertEq(pool.totalDebt(), 21_000 * 1e18);
        // check borrower balance
        (uint256 borrowerDebt, uint256 depositedCollateral, ) = pool.borrowers(
            address(borrower)
        );
        assertEq(borrowerDebt, 21_000 * 1e18);
        assertEq(depositedCollateral, 100 * 1e18);

        skip(8200);

        // borrow remaining 9_000 DAI from LUP
        vm.expectEmit(true, false, false, true);
        emit Transfer(address(pool), address(borrower), 9_000 * 1e18);
        emit Borrow(address(borrower), 2_500 * 1e18, 9_000 * 1e18);
        borrower.borrow(pool, 9_000 * 1e18, 2_500 * 1e18);

        assertEq(quote.balanceOf(address(borrower)), 30_000 * 1e18);
        assertEq(quote.balanceOf(address(pool)), 20_000 * 1e18);
        assertEq(pool.hdp(), 4_000 * 1e18);
        assertEq(pool.lup(), 2_500 * 1e18);

        // check bucket debt at 2_500
        (, , , deposit, debt, , ) = pool.bucketAt(2_500 * 1e18);
        assertEq(debt, 0.013001099140905000 * 1e18);
        assertEq(deposit, 10_000 * 1e18);
        // check bucket debt at 3_000
        (, , , deposit, debt, , ) = pool.bucketAt(3_000 * 1e18);
        assertEq(debt, 10_000 * 1e18);
        assertEq(deposit, 10_000 * 1e18);
        // check bucket debt at 3_500
        (, , , deposit, debt, , ) = pool.bucketAt(3_500 * 1e18);
        assertEq(debt, 10_000 * 1e18);
        assertEq(deposit, 10_000 * 1e18);
        // check bucket debt at 4_000
        (, , , deposit, debt, , ) = pool.bucketAt(4_000 * 1e18);
        assertEq(debt, 10_000 * 1e18);
        assertEq(deposit, 10_000 * 1e18);
        // check pool debt
        assertEq(pool.totalDebt(), 30_000.273023081959005000 * 1e18);

        // check borrower balances
        (borrowerDebt, depositedCollateral, ) = pool.borrowers(
            address(borrower)
        );
        assertEq(borrowerDebt, 30_000 * 1e18);
        assertEq(depositedCollateral, 100 * 1e18);

        // deposit at 5_000 price and reallocate entire debt
        lender.addQuoteToken(pool, 40_000 * 1e18, 5_000 * 1e18);

        // check bucket debt at 2_500
        (, , , deposit, debt, , ) = pool.bucketAt(2_500 * 1e18);
        assertEq(debt, 0);
        assertEq(deposit, 10_000 * 1e18);
        // check bucket debt at 3_000
        (, , , deposit, debt, , ) = pool.bucketAt(3_000 * 1e18);
        assertEq(debt, 0);
        assertEq(deposit, 10_000 * 1e18);
        // check bucket debt at 3_500
        (, , , deposit, debt, , ) = pool.bucketAt(3_500 * 1e18);
        assertEq(debt, 0);
        assertEq(deposit, 10_000 * 1e18);
        // check bucket debt at 4_000
        (, , , deposit, debt, , ) = pool.bucketAt(4_000 * 1e18);
        assertEq(debt, 0);
        assertEq(deposit, 10_000 * 1e18);
        // check bucket debt at 5_000
        (, , , deposit, debt, , ) = pool.bucketAt(5_000 * 1e18);
        assertEq(debt, 30000.273023081959005000 * 1e18);
        assertEq(deposit, 40_000 * 1e18);
        // check pool debt
        assertEq(pool.totalQuoteToken(), 90_000 * 1e18);
        assertEq(pool.totalDebt(), 30000.273023081959005000 * 1e18);
    }

    function testBorrowPoolUndercollateralization() public {
        // lender deposits 200_000 DAI in 3 buckets
        lender.addQuoteToken(pool, 100_000 * 1e18, 2_000 * 1e18);
        lender.addQuoteToken(pool, 50_000 * 1e18, 1_000 * 1e18);
        lender.addQuoteToken(pool, 50_000 * 1e18, 500 * 1e18);

        // borrower1 takes a loan on 100_000 DAI
        borrower.addCollateral(pool, 51 * 1e18);
        borrower.borrow(pool, 100_000 * 1e18, 1_000 * 1e18);

        borrower2.addCollateral(pool, 51 * 1e18);
        // should revert when taking a loan of 50_000 DAI that will drive pool undercollateralized
        vm.expectRevert("ajna/pool-undercollateralized");
        borrower2.borrow(pool, 5_000 * 1e18, 1_000 * 1e18);
    }

    function testBorrowTestCollateralValidation() public {
        // lender deposits 10_000 DAI at 13.537
        lender.addQuoteToken(pool, 10_000 * 1e18, 13.537 * 1e18);
        borrower.addCollateral(pool, 100 * 1e18);
        // should not revert when borrower takes a loan on 100_000 DAI
        borrower.borrow(pool, 1_000 * 1e18, 13.537 * 1e18);
    }
}
