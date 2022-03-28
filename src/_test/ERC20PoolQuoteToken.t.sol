// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.11;

import {DSTestPlus} from "./utils/DSTestPlus.sol";
import {UserWithCollateral, UserWithQuoteToken} from "./utils/Users.sol";
import {CollateralToken, QuoteToken} from "./utils/Tokens.sol";

import {ERC20Pool} from "../ERC20Pool.sol";
import {ERC20PoolFactory} from "../ERC20PoolFactory.sol";

contract ERC20PoolQuoteTokenTest is DSTestPlus {
    ERC20Pool internal pool;
    CollateralToken internal collateral;
    QuoteToken internal quote;

    UserWithCollateral internal borrower;
    UserWithQuoteToken internal lender;

    function setUp() public {
        collateral = new CollateralToken();
        quote = new QuoteToken();

        ERC20PoolFactory factory = new ERC20PoolFactory();
        pool = factory.deployPool(collateral, quote);

        borrower = new UserWithCollateral();
        collateral.mint(address(borrower), 100 * 1e18);
        borrower.approveToken(collateral, address(pool), 100 * 1e18);

        lender = new UserWithQuoteToken();
        quote.mint(address(lender), 200_000 * 1e18);
        lender.approveToken(quote, address(pool), 200_000 * 1e18);
    }

    function testDepositQuoteToken() public {
        // should revert when depositing at invalid price
        vm.expectRevert("ajna/invalid-bucket-price");
        lender.addQuoteToken(pool, 10_000 * 1e18, 1004948314 * 1e18);

        assertEq(pool.hdp(), 0);

        // test 10000 DAI deposit at price of 1 MKR = 4000 DAI
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(lender), address(pool), 10_000 * 1e18);
        emit AddQuoteToken(address(lender), 4_000 * 1e18, 10_000 * 1e18, 0);
        lender.addQuoteToken(pool, 10_000 * 1e18, 4_000 * 1e18);
        // check pool hdp and balances
        assertEq(pool.hdp(), 4_000 * 1e18);
        assertEq(pool.totalQuoteToken(), 10_000 * 1e18);
        assertEq(quote.balanceOf(address(pool)), 10_000 * 1e18);
        assertEq(quote.balanceOf(address(lender)), 190_000 * 1e18);
        // check bucket balance
        (
            uint256 price,
            uint256 upPrice,
            uint256 downPrice,
            uint256 deposit,
            uint256 debt,
            uint256 snapshot,
            uint256 lpOutstanding,

        ) = pool.bucketAt(4_000 * 1e18);
        assertEq(price, 4_000 * 1e18);
        assertEq(upPrice, 4_000 * 1e18);
        assertEq(downPrice, 0);
        assertEq(deposit, 10_000 * 1e18);
        assertEq(debt, 0);
        assertEq(snapshot, 1 * 1e18);
        assertEq(lpOutstanding, 10_000 * 1e18);
        assertEq(pool.lpBalance(address(lender), 4_000 * 1e18), 10_000 * 1e18);

        // test 20000 DAI deposit at price of 1 MKR = 2000 DAI
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(lender), address(pool), 20_000 * 1e18);
        emit AddQuoteToken(address(lender), 2_000 * 1e18, 20_000 * 1e18, 0);
        lender.addQuoteToken(pool, 20_000 * 1e18, 2_000 * 1e18);
        // check pool hdp and balances
        assertEq(pool.hdp(), 4_000 * 1e18);
        assertEq(pool.totalQuoteToken(), 30_000 * 1e18);
        assertEq(quote.balanceOf(address(pool)), 30_000 * 1e18);
        assertEq(quote.balanceOf(address(lender)), 170_000 * 1e18);
        // check bucket balance
        (
            price,
            upPrice,
            downPrice,
            deposit,
            debt,
            snapshot,
            lpOutstanding,

        ) = pool.bucketAt(2_000 * 1e18);
        assertEq(price, 2_000 * 1e18);
        assertEq(upPrice, 4_000 * 1e18);
        assertEq(downPrice, 0);
        assertEq(deposit, 20_000 * 1e18);
        assertEq(debt, 0);
        assertEq(snapshot, 1 * 1e18);
        assertEq(lpOutstanding, 20_000 * 1e18);
        assertEq(pool.lpBalance(address(lender), 2_000 * 1e18), 20_000 * 1e18);
        // check hdp down price pointer updated
        (, upPrice, downPrice, , , , , ) = pool.bucketAt(4_000 * 1e18);
        assertEq(upPrice, 4_000 * 1e18);
        assertEq(downPrice, 2_000 * 1e18);

        // test 30000 DAI deposit at price of 1 MKR = 3000 DAI
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(lender), address(pool), 30_000 * 1e18);
        emit AddQuoteToken(address(lender), 3_000 * 1e18, 30_000 * 1e18, 0);
        lender.addQuoteToken(pool, 30_000 * 1e18, 3_000 * 1e18);
        // check pool hdp and balances
        assertEq(pool.hdp(), 4_000 * 1e18);
        assertEq(pool.totalQuoteToken(), 60_000 * 1e18);
        assertEq(quote.balanceOf(address(pool)), 60_000 * 1e18);
        assertEq(quote.balanceOf(address(lender)), 140_000 * 1e18);
        // check bucket balance
        (
            price,
            upPrice,
            downPrice,
            deposit,
            debt,
            snapshot,
            lpOutstanding,

        ) = pool.bucketAt(3_000 * 1e18);
        assertEq(price, 3_000 * 1e18);
        assertEq(upPrice, 4_000 * 1e18);
        assertEq(downPrice, 2_000 * 1e18);
        assertEq(deposit, 30_000 * 1e18);
        assertEq(debt, 0);
        assertEq(snapshot, 1 * 1e18);
        assertEq(lpOutstanding, 30_000 * 1e18);
        assertEq(pool.lpBalance(address(lender), 3_000 * 1e18), 30_000 * 1e18);
        // check hdp down price pointer updated
        (, upPrice, downPrice, , , , , ) = pool.bucketAt(4_000 * 1e18);
        assertEq(upPrice, 4_000 * 1e18);
        assertEq(downPrice, 3_000 * 1e18);
        // check 2000 down price pointer updated
        (, upPrice, downPrice, , , , , ) = pool.bucketAt(2_000 * 1e18);
        assertEq(upPrice, 3_000 * 1e18);
        assertEq(downPrice, 0);

        // test 40000 DAI deposit at price of 1 MKR = 5000 DAI
        // hdp should be updated to 5000 DAI and hdp next price should be 4000 DAI
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(lender), address(pool), 40_000 * 1e18);
        emit AddQuoteToken(address(lender), 5_000 * 1e18, 40_000 * 1e18, 0);
        lender.addQuoteToken(pool, 40_000 * 1e18, 5_000 * 1e18);
        // check pool hdp and balances
        assertEq(pool.hdp(), 5_000 * 1e18);
        assertEq(pool.totalQuoteToken(), 100_000 * 1e18);
        assertEq(quote.balanceOf(address(pool)), 100_000 * 1e18);
        assertEq(quote.balanceOf(address(lender)), 100_000 * 1e18);
        // check bucket balance
        (
            price,
            upPrice,
            downPrice,
            deposit,
            debt,
            snapshot,
            lpOutstanding,

        ) = pool.bucketAt(5_000 * 1e18);
        assertEq(price, 5_000 * 1e18);
        assertEq(upPrice, 5_000 * 1e18);
        assertEq(downPrice, 4_000 * 1e18);
        assertEq(deposit, 40_000 * 1e18);
        assertEq(debt, 0);
        assertEq(snapshot, 1 * 1e18);
        assertEq(lpOutstanding, 40_000 * 1e18);
        assertEq(pool.lpBalance(address(lender), 5_000 * 1e18), 40_000 * 1e18);
    }

    function testRemoveQuoteTokenNoLoan() public {
        // lender deposit 10000 DAI at price 4000
        lender.addQuoteToken(pool, 10_000 * 1e18, 4_000 * 1e18);

        // should revert if trying to remove more than lended
        vm.expectRevert("ajna/amount-greater-than-claimable");
        lender.removeQuoteToken(pool, 20_000 * 1e18, 4_000 * 1e18);

        skip(8200);

        // check balances before removal
        assertEq(pool.totalDebt(), 0);
        assertEq(pool.totalQuoteToken(), 10_000 * 1e18);

        (, , , uint256 deposit, uint256 debt, , uint256 lpOutstanding, ) = pool
            .bucketAt(4_000 * 1e18);
        assertEq(deposit, 10_000 * 1e18);
        assertEq(debt, 0);
        assertEq(lpOutstanding, 10_000 * 1e18);
        assertEq(pool.lpBalance(address(lender), 4_000 * 1e18), 10_000 * 1e18);

        // remove 10000 DAI at price of 1 MKR = 4000 DAI
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(pool), address(lender), 10_000 * 1e18);
        emit RemoveQuoteToken(
            address(borrower),
            4_000 * 1e18,
            10_000 * 1e18,
            4_000 * 1e18
        );
        lender.removeQuoteToken(pool, 10_000 * 1e18, 4_000 * 1e18);

        // check balances after removal
        assertEq(pool.totalDebt(), 0);
        assertEq(pool.totalQuoteToken(), 0);
        // check 4000 bucket balance
        (, , , deposit, debt, , lpOutstanding, ) = pool.bucketAt(4_000 * 1e18);
        assertEq(deposit, 0 * 1e18);
        assertEq(debt, 0);
        assertEq(lpOutstanding, 0 * 1e18);
        assertEq(pool.lpBalance(address(lender), 4_000 * 1e18), 0 * 1e18);
    }

    function testRemoveQuoteTokenUnpaidLoan() public {
        // lender deposit 10000 DAI at price 4000
        lender.addQuoteToken(pool, 10_000 * 1e18, 4_000 * 1e18);
        assertEq(quote.balanceOf(address(lender)), 190_000 * 1e18);

        // check balances
        assertEq(quote.balanceOf(address(pool)), 10_000 * 1e18);
        assertEq(pool.totalQuoteToken(), 10_000 * 1e18);
        assertEq(quote.balanceOf(address(lender)), 190_000 * 1e18);
        assertEq(pool.lpBalance(address(lender), 4_000 * 1e18), 10_000 * 1e18);

        // borrower takes a loan of 5_000 DAI
        borrower.addCollateral(pool, 100 * 1e18);
        borrower.borrow(pool, 5_000 * 1e18, 4_000 * 1e18);

        // should revert if trying to remove entire amount lended
        vm.expectRevert("ajna/failed-to-reallocate");
        lender.removeQuoteToken(pool, 10_000 * 1e18, 4_000 * 1e18);

        // remove 4000 DAI at price of 1 MKR = 4000 DAI
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(pool), address(lender), 4_000 * 1e18);
        emit RemoveQuoteToken(
            address(borrower),
            4_000 * 1e18,
            4_000 * 1e18,
            4_000 * 1e18
        );
        lender.removeQuoteToken(pool, 4_000 * 1e18, 4_000 * 1e18);

        // check pool balances
        assertEq(pool.totalQuoteToken(), 1_000 * 1e18);
        assertEq(quote.balanceOf(address(pool)), 1_000 * 1e18);
        // check lender balance
        assertEq(quote.balanceOf(address(lender)), 194_000 * 1e18);

        // check 4000 bucket balance
        (, , , uint256 deposit, uint256 debt, , uint256 lpOutstanding, ) = pool
            .bucketAt(4_000 * 1e18);
        assertEq(deposit, 6_000 * 1e18);
        assertEq(debt, 5_000 * 1e18);
        assertEq(lpOutstanding, 6_000 * 1e18);
        assertEq(pool.lpBalance(address(lender), 4_000 * 1e18), 6_000 * 1e18);
    }

    function testRemoveQuoteTokenPaidLoan() public {
        // lender deposit 10000 DAI at price 4000
        lender.addQuoteToken(pool, 10_000 * 1e18, 4_000 * 1e18);
        assertEq(quote.balanceOf(address(lender)), 190_000 * 1e18);

        // borrower takes a loan of 10000 DAI
        borrower.addCollateral(pool, 100 * 1e18);
        borrower.borrow(pool, 10_000 * 1e18, 4_000 * 1e18);
        assertEq(pool.lup(), 4_000 * 1e18);

        // borrower repay entire loan
        quote.mint(address(borrower), 1 * 1e18);
        borrower.approveToken(quote, address(pool), 100_000 * 1e18);

        borrower.repay(pool, 10_001 * 1e18);

        skip(8200);
        // lender removes entire amount lended
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(pool), address(lender), 10_000 * 1e18);
        emit RemoveQuoteToken(
            address(borrower),
            4_000 * 1e18,
            10_000 * 1e18,
            4_000 * 1e18
        );
        lender.removeQuoteToken(pool, 10_000 * 1e18, 4_000 * 1e18);

        // check pool balances
        assertEq(pool.totalQuoteToken(), 0);
        assertEq(quote.balanceOf(address(pool)), 0);
        // check lender balance
        assertEq(quote.balanceOf(address(lender)), 200_000 * 1e18);
    }

    function testRemoveQuoteTokenWithDebtReallocation() public {
        // lender deposit 3_400 DAI in 2 buckets
        lender.addQuoteToken(pool, 3_400 * 1e18, 4_000 * 1e18);
        lender.addQuoteToken(pool, 3_400 * 1e18, 3_000 * 1e18);

        // borrower takes a loan of 3000 DAI
        borrower.addCollateral(pool, 100 * 1e18);
        borrower.borrow(pool, 3_000 * 1e18, 4_000 * 1e18);
        assertEq(pool.lup(), 4_000 * 1e18);

        // lender removes 1000 DAI from lup
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(pool), address(lender), 1_000 * 1e18);
        emit RemoveQuoteToken(
            address(borrower),
            4_000 * 1e18,
            1_000 * 1e18,
            4_000 * 1e18
        );
        lender.removeQuoteToken(pool, 1_000 * 1e18, 4_000 * 1e18);

        // check lup moved down to 3000
        assertEq(pool.lup(), 3_000 * 1e18);
        // check pool balances
        assertEq(pool.totalQuoteToken(), 2_800 * 1e18);
        assertEq(pool.totalDebt(), 3_000 * 1e18);
        assertEq(quote.balanceOf(address(pool)), 2_800 * 1e18);
        // check lender balance
        assertEq(quote.balanceOf(address(lender)), 194_200 * 1e18);

        // check 4000 bucket balance
        (, , , uint256 deposit, uint256 debt, , uint256 lpOutstanding, ) = pool
            .bucketAt(4_000 * 1e18);
        assertEq(deposit, 2_400 * 1e18);
        assertEq(debt, 2_400 * 1e18);
        assertEq(lpOutstanding, 2_400 * 1e18);
        assertEq(pool.lpBalance(address(lender), 4_000 * 1e18), 2_400 * 1e18);

        // check 3000 bucket balance
        (, , , deposit, debt, , lpOutstanding, ) = pool.bucketAt(3_000 * 1e18);
        assertEq(deposit, 3_400 * 1e18);
        assertEq(debt, 600 * 1e18);
        assertEq(lpOutstanding, 3_400 * 1e18);
        assertEq(pool.lpBalance(address(lender), 3_000 * 1e18), 3_400 * 1e18);
    }

    function testRemoveQuoteTokenBelowLup() public {
        // lender deposit 5000 DAI in 3 buckets
        lender.addQuoteToken(pool, 5_000 * 1e18, 4_000 * 1e18);
        lender.addQuoteToken(pool, 5_000 * 1e18, 3_000 * 1e18);
        lender.addQuoteToken(pool, 5_000 * 1e18, 2_000 * 1e18);

        // borrower takes a loan of 3000 DAI
        borrower.addCollateral(pool, 100 * 1e18);
        borrower.borrow(pool, 3_000 * 1e18, 4_000 * 1e18);
        assertEq(pool.lup(), 4_000 * 1e18);

        // lender removes 1000 DAI under the lup - from bucket 3000
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(pool), address(lender), 1_000 * 1e18);
        emit RemoveQuoteToken(
            address(borrower),
            3_000 * 1e18,
            1_000 * 1e18,
            4_000 * 1e18
        );
        lender.removeQuoteToken(pool, 1_000 * 1e18, 3_000 * 1e18);

        // check same lup
        assertEq(pool.lup(), 4_000 * 1e18);
        // check pool balances
        assertEq(pool.totalQuoteToken(), 11_000 * 1e18);
        assertEq(quote.balanceOf(address(pool)), 11_000 * 1e18);

        // check 4000 bucket balance
        (, , , uint256 deposit, uint256 debt, , uint256 lpOutstanding, ) = pool
            .bucketAt(4_000 * 1e18);
        assertEq(deposit, 5_000 * 1e18);
        assertEq(debt, 3_000 * 1e18);
        assertEq(lpOutstanding, 5_000 * 1e18);
        assertEq(pool.lpBalance(address(lender), 4_000 * 1e18), 5_000 * 1e18);

        // check 3000 bucket balance, should have less 1000 DAi and lp token
        (, , , deposit, debt, , lpOutstanding, ) = pool.bucketAt(3_000 * 1e18);
        assertEq(deposit, 4_000 * 1e18);
        assertEq(debt, 0);
        assertEq(lpOutstanding, 4_000 * 1e18);
        assertEq(pool.lpBalance(address(lender), 3_000 * 1e18), 4_000 * 1e18);
    }

    function testRemoveQuoteUndercollateralizedPool() public {
        // lender deposit 5000 DAI in 2 spaced buckets
        lender.addQuoteToken(pool, 5_000 * 1e18, 1_000 * 1e18);
        lender.addQuoteToken(pool, 5_000 * 1e18, 100 * 1e18);

        // borrower takes a loan of 4000 DAI
        borrower.addCollateral(pool, 5.1 * 1e18);
        borrower.borrow(pool, 4_000 * 1e18, 1_000 * 1e18);
        assertEq(pool.lup(), 1_000 * 1e18);

        // repay should revert if pool remains undercollateralized
        vm.expectRevert("ajna/pool-undercollateralized");
        lender.removeQuoteToken(pool, 2_000 * 1e18, 1_000 * 1e18);
    }
}
