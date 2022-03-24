// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.11;

import {DSTestPlus} from "./utils/DSTestPlus.sol";
import {UserWithCollateral, UserWithQuoteToken} from "./utils/Users.sol";
import {CollateralToken, QuoteToken} from "./utils/Tokens.sol";

import {ERC20Pool} from "../ERC20Pool.sol";
import {ERC20PoolFactory} from "../ERC20PoolFactory.sol";

contract ERC20PoolLiquidateTest is DSTestPlus {
    ERC20Pool internal pool;
    CollateralToken internal collateral;
    QuoteToken internal quote;

    UserWithCollateral internal borrower;
    UserWithCollateral internal borrower2;
    UserWithQuoteToken internal lender;

    function setUp() public {
        collateral = new CollateralToken();
        quote = new QuoteToken();

        ERC20PoolFactory factory = new ERC20PoolFactory();
        pool = factory.deployPool(collateral, quote);

        borrower = new UserWithCollateral();
        collateral.mint(address(borrower), 2 * 1e18);
        borrower.approveToken(collateral, address(pool), 2 * 1e18);

        borrower2 = new UserWithCollateral();
        collateral.mint(address(borrower2), 200 * 1e18);
        borrower2.approveToken(collateral, address(pool), 200 * 1e18);

        lender = new UserWithQuoteToken();
        quote.mint(address(lender), 200_000 * 1e18);
        lender.approveToken(quote, address(pool), 200_000 * 1e18);
    }

    function testLiquidate() public {
        // lender deposit in 3 buckets, price spaced
        lender.addQuoteToken(pool, 10_000 * 1e18, 10_000 * 1e18);
        lender.addQuoteToken(pool, 1_000 * 1e18, 9_000 * 1e18);
        lender.addQuoteToken(pool, 10_000 * 1e18, 100 * 1e18);

        // should revert when no debt
        vm.expectRevert("ajna/no-debt-to-liquidate");
        lender.liquidate(pool, address(borrower));

        // borrowers deposit collateral
        borrower.addCollateral(pool, 2 * 1e18);
        borrower2.addCollateral(pool, 200 * 1e18);

        // check pool balance
        assertEq(pool.totalQuoteToken(), 21_000 * 1e18);
        assertEq(pool.totalDebt(), 0);
        assertEq(pool.totalCollateral(), 202 * 1e18);
        assertEq(pool.hdp(), 10_000 * 1e18);

        // first borrower takes a loan of 11_000 DAI, pushing lup to 9_000
        borrower.borrow(pool, 11_000 * 1e18, 9_000 * 1e18);
        // 2nd borrower takes a loan of 1_000 DAI, pushing lup to 100
        borrower2.borrow(pool, 1_000 * 1e18, 100 * 1e18);

        // should revert when borrower collateralized
        vm.expectRevert("ajna/borrower-collateralized");
        lender.liquidate(pool, address(borrower2));

        // check borrower 1 is undercollateralized
        (
            uint256 borrowerDebt,
            uint256 borrowerPendingDebt,
            uint256 collateralDeposited,
            uint256 collateralEncumbered,
            uint256 collateralization,
            uint256 borrowerInflator,

        ) = pool.getBorrowerInfo(address(borrower));
        assertEq(borrowerDebt, 11_000 * 1e18);
        assertEq(borrowerPendingDebt, 11_000 * 1e18);
        assertEq(collateralDeposited, 2 * 1e18);
        assertEq(collateralEncumbered, 110 * 1e18);
        assertEq(collateralization, 0.018181818181818182 * 1e18);
        assertEq(borrowerInflator, 1 * 1e18);

        // check pool balance
        assertEq(pool.totalQuoteToken(), 21_000 * 1e18);
        assertEq(pool.totalDebt(), 12_000 * 1e18);
        assertEq(pool.totalCollateral(), 202 * 1e18);
        assertEq(pool.lup(), 100 * 1e18);
        assertEq(quote.balanceOf(address(pool)), 9_000 * 1e18);

        assertEq(pool.lastInflatorSnapshotUpdate(), 0);

        // check 10_000 bucket balance before purchase bid
        (
            ,
            ,
            ,
            uint256 deposit,
            uint256 debt,
            ,
            ,
            uint256 bucketCollateral
        ) = pool.bucketAt(10_000 * 1e18);
        assertEq(debt, 10_000 * 1e18);
        assertEq(deposit, 10_000 * 1e18);
        assertEq(bucketCollateral, 0);

        // check 9_000 bucket balance before purchase bid
        (, , , deposit, debt, , , bucketCollateral) = pool.bucketAt(
            9_000 * 1e18
        );
        assertEq(debt, 1_000 * 1e18);
        assertEq(deposit, 1_000 * 1e18);
        assertEq(bucketCollateral, 0);

        // check 100 bucket balance before purchase bid
        (, , , deposit, debt, , , bucketCollateral) = pool.bucketAt(100 * 1e18);
        assertEq(debt, 1_000 * 1e18);
        assertEq(deposit, 10_000 * 1e18);
        assertEq(bucketCollateral, 0);

        skip(8200);

        // liquidate borrower
        vm.expectEmit(true, false, false, true);
        emit Liquidate(
            address(borrower),
            11_000 * 1e18,
            1.111109666544539939 * 1e18
        );
        lender.liquidate(pool, address(borrower));

        // check borrower 1 balances and that interest accumulated
        (
            borrowerDebt,
            borrowerPendingDebt,
            collateralDeposited,
            collateralEncumbered,
            collateralization,
            borrowerInflator,

        ) = pool.getBorrowerInfo(address(borrower));
        assertEq(borrowerDebt, 0);
        assertEq(borrowerPendingDebt, 0);
        assertEq(collateralDeposited, 0.888890333455460061 * 1e18);
        assertEq(collateralEncumbered, 0);
        assertEq(collateralization, 0);
        assertEq(borrowerInflator, 1.000013001099140905 * 1e18);

        // check pool balance and that interest accumulated
        assertEq(pool.totalQuoteToken(), 10_000 * 1e18);
        assertEq(pool.totalDebt(), 1000.156013189690860000 * 1e18);
        assertEq(pool.totalCollateral(), 200.888890333455460061 * 1e18);
        assertEq(pool.inflatorSnapshot(), 1.000013001099140905 * 1e18);
        assertEq(pool.lastInflatorSnapshotUpdate(), 8200);
        assertEq(pool.lup(), 100 * 1e18);
        assertEq(quote.balanceOf(address(pool)), 9_000 * 1e18);

        // check 10_000 bucket balance after purchase bid
        (, , , deposit, debt, , , bucketCollateral) = pool.bucketAt(
            10_000 * 1e18
        );
        assertEq(debt, 0);
        assertEq(deposit, 10_000 * 1e18);
        assertEq(bucketCollateral, 1.000013001099140905 * 1e18);

        // check 9_000 bucket balance after purchase bid
        (, , , deposit, debt, , , bucketCollateral) = pool.bucketAt(
            9_000 * 1e18
        );
        assertEq(debt, 0.130010991409054000 * 1e18);
        assertEq(deposit, 1_000 * 1e18);
        assertEq(bucketCollateral, 0.111096665445398994 * 1e18);

        // check 100 bucket balance after purchase bid
        (, , , deposit, debt, , , bucketCollateral) = pool.bucketAt(100 * 1e18);
        assertEq(debt, 999.999999999999996000 * 1e18);
        assertEq(deposit, 10_000 * 1e18);
        assertEq(bucketCollateral, 0.000000000000000040 * 1e18);
    }
}
