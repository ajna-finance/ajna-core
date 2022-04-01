// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.11;

import {DSTestPlus} from "./utils/DSTestPlus.sol";
import {UserWithCollateral, UserWithQuoteToken} from "./utils/Users.sol";
import {CollateralToken, QuoteToken} from "./utils/Tokens.sol";

import {ERC20Pool} from "../ERC20Pool.sol";
import {ERC20PoolFactory} from "../ERC20PoolFactory.sol";

contract ERC20PoolBidTest is DSTestPlus {
    ERC20Pool internal pool;
    CollateralToken internal collateral;
    QuoteToken internal quote;

    UserWithCollateral internal borrower;
    UserWithQuoteToken internal lender;
    UserWithCollateral internal bidder;

    function setUp() public {
        collateral = new CollateralToken();
        quote = new QuoteToken();

        ERC20PoolFactory factory = new ERC20PoolFactory();
        pool = factory.deployPool(collateral, quote);

        borrower = new UserWithCollateral();
        collateral.mint(address(borrower), 100 * 1e18);
        borrower.approveToken(collateral, address(pool), 100 * 1e18);

        bidder = new UserWithCollateral();
        collateral.mint(address(bidder), 100 * 1e18);
        bidder.approveToken(collateral, address(pool), 100 * 1e18);

        lender = new UserWithQuoteToken();
        quote.mint(address(lender), 200_000 * 1e18);
        lender.approveToken(quote, address(pool), 200_000 * 1e18);
    }

    function testPurchaseBidPartialAmount() public {
        lender.addQuoteToken(
            pool,
            address(lender),
            3_000 * 1e18,
            4_000.927678580567537368 * 1e18
        );
        lender.addQuoteToken(
            pool,
            address(lender),
            3_000 * 1e18,
            3_010.892022197881557845 * 1e18
        );
        lender.addQuoteToken(
            pool,
            address(lender),
            3_000 * 1e18,
            1_004.989662429170775094 * 1e18
        );

        // borrower takes a loan of 4000 DAI making bucket 4000 to be fully utilized
        borrower.addCollateral(pool, 100 * 1e18);
        borrower.borrow(pool, 4_000 * 1e18, 3_000 * 1e18);
        assertEq(pool.lup(), 3_010.892022197881557845 * 1e18);

        // should revert if invalid price
        vm.expectRevert("ajna/invalid-price");
        bidder.purchaseBid(pool, 1 * 1e18, 1_000);

        // should revert if bidder doesn't have enough collateral
        vm.expectRevert("ajna/not-enough-collateral-balance");
        bidder.purchaseBid(
            pool,
            2_000_000 * 1e18,
            4_000.927678580567537368 * 1e18
        );

        // should revert if trying to purchase more than on bucket
        vm.expectRevert("ajna/insufficient-bucket-size");
        bidder.purchaseBid(pool, 4_000 * 1e18, 4_000.927678580567537368 * 1e18);

        // check bidder and pool balances
        assertEq(collateral.balanceOf(address(bidder)), 100 * 1e18);
        assertEq(quote.balanceOf(address(bidder)), 0);
        assertEq(collateral.balanceOf(address(pool)), 100 * 1e18);
        assertEq(quote.balanceOf(address(pool)), 5_000 * 1e18);
        assertEq(pool.totalCollateral(), 100 * 1e18);

        // check 4_000.927678580567537368 bucket balance before purchase bid
        (
            ,
            ,
            ,
            uint256 deposit,
            uint256 debt,
            ,
            ,
            uint256 bucketCollateral
        ) = pool.bucketAt(4_000.927678580567537368 * 1e18);
        assertEq(deposit, 0);
        assertEq(debt, 3_000 * 1e18);
        // check 3_010.892022197881557845 bucket balance before purchase bid
        (, , , deposit, debt, , , bucketCollateral) = pool.bucketAt(
            3_010.892022197881557845 * 1e18
        );
        assertEq(deposit, 2_000 * 1e18);
        assertEq(debt, 1_000 * 1e18);
        assertEq(bucketCollateral, 0);

        // purchase 2000 bid from 4_000.927678580567537368 bucket
        vm.expectEmit(true, true, false, true);
        emit Purchase(
            address(bidder),
            4_000.927678580567537368 * 1e18,
            2_000 * 1e18,
            0.499884067064554307 * 1e18
        );
        emit Transfer(
            address(bidder),
            address(pool),
            0.499884067064554307 * 1e18
        );
        bidder.purchaseBid(pool, 2_000 * 1e18, 4_000.927678580567537368 * 1e18);

        assertEq(pool.lup(), 1_004.989662429170775094 * 1e18);
        // check 4_000.927678580567537368 bucket balance after purchase bid
        (, , , deposit, debt, , , bucketCollateral) = pool.bucketAt(
            4_000.927678580567537368 * 1e18
        );
        assertEq(deposit, 0);
        assertEq(debt, 1_000 * 1e18);
        assertEq(bucketCollateral, 0.499884067064554307 * 1e18);
        // check 3_010.892022197881557845 bucket balance after purchase bid
        (, , , deposit, debt, , , bucketCollateral) = pool.bucketAt(
            3_010.892022197881557845 * 1e18
        );
        assertEq(deposit, 0);
        assertEq(debt, 3_000 * 1e18);
        assertEq(bucketCollateral, 0);
        // check 1_004.989662429170775094 bucket balance after purchase bid
        (, , , deposit, debt, , , bucketCollateral) = pool.bucketAt(
            1_004.989662429170775094 * 1e18
        );
        assertEq(deposit, 3_000 * 1e18);
        assertEq(debt, 0);
        assertEq(bucketCollateral, 0);

        // check bidder and pool balances
        assertEq(
            collateral.balanceOf(address(bidder)),
            99.500115932935445693 * 1e18
        );
        assertEq(quote.balanceOf(address(bidder)), 2_000 * 1e18);
        assertEq(
            collateral.balanceOf(address(pool)),
            100.499884067064554307 * 1e18
        );
        assertEq(quote.balanceOf(address(pool)), 3_000 * 1e18);
        assertEq(pool.totalCollateral(), 100 * 1e18);
    }

    function testPurchaseBidEntireAmount() public {
        lender.addQuoteToken(
            pool,
            address(lender),
            1_000 * 1e18,
            4_000.927678580567537368 * 1e18
        );
        lender.addQuoteToken(
            pool,
            address(lender),
            1_000 * 1e18,
            3_010.892022197881557845 * 1e18
        );
        lender.addQuoteToken(
            pool,
            address(lender),
            5_000 * 1e18,
            2_000.221618840727700609 * 1e18
        );

        // borrower takes a loan of 1000 DAI from bucket 4000
        borrower.addCollateral(pool, 100 * 1e18);
        borrower.borrow(pool, 1_000 * 1e18, 3_000 * 1e18);
        // borrower takes a loan of 1000 DAI from bucket 3000
        borrower.borrow(pool, 1_000 * 1e18, 3_000 * 1e18);

        // check bidder and pool balances
        assertEq(collateral.balanceOf(address(bidder)), 100 * 1e18);
        assertEq(quote.balanceOf(address(bidder)), 0);
        assertEq(collateral.balanceOf(address(pool)), 100 * 1e18);
        assertEq(quote.balanceOf(address(pool)), 5_000 * 1e18);
        assertEq(pool.totalCollateral(), 100 * 1e18);
        assertEq(pool.lup(), 3_010.892022197881557845 * 1e18);

        // check 4_000.927678580567537368 bucket balance before purchase Bid
        (
            ,
            ,
            ,
            uint256 deposit,
            uint256 debt,
            ,
            ,
            uint256 bucketCollateral
        ) = pool.bucketAt(4_000.927678580567537368 * 1e18);
        assertEq(deposit, 0);
        assertEq(debt, 1_000 * 1e18);
        assertEq(bucketCollateral, 0);
        // check 3_010.892022197881557845 bucket balance before purchase bid
        (, , , deposit, debt, , , bucketCollateral) = pool.bucketAt(
            3_010.892022197881557845 * 1e18
        );
        assertEq(deposit, 0);
        assertEq(debt, 1_000 * 1e18);
        assertEq(bucketCollateral, 0);
        // check 2_000.221618840727700609 bucket balance before purchase bid
        (, , , deposit, debt, , , bucketCollateral) = pool.bucketAt(
            2_000.221618840727700609 * 1e18
        );
        assertEq(deposit, 5_000 * 1e18);
        assertEq(debt, 0);
        assertEq(bucketCollateral, 0);

        // purchase 1000 bid - entire amount in 4000 bucket
        vm.expectEmit(true, false, false, true);
        emit Purchase(
            address(bidder),
            4_000.927678580567537368 * 1e18,
            1_000 * 1e18,
            0.249942033532277153 * 1e18
        );
        emit Transfer(address(bidder), address(pool), 0.25 * 1e18);
        bidder.purchaseBid(pool, 1_000 * 1e18, 4_000.927678580567537368 * 1e18);

        // lup should be pushed downwards
        assertEq(pool.lup(), 2_000.221618840727700609 * 1e18);
        // check 4_000.927678580567537368 bucket balance after purchase Bid
        (, , , deposit, debt, , , bucketCollateral) = pool.bucketAt(
            4_000.927678580567537368 * 1e18
        );
        assertEq(deposit, 0);
        assertEq(debt, 0);
        assertEq(bucketCollateral, 0.249942033532277153 * 1e18);
        // check 3_010.892022197881557845 bucket balance
        (, , , deposit, debt, , , bucketCollateral) = pool.bucketAt(
            3_010.892022197881557845 * 1e18
        );
        assertEq(deposit, 0);
        assertEq(debt, 1_000 * 1e18);
        assertEq(bucketCollateral, 0);
        // check 2_000.221618840727700609 bucket balance
        (, , , deposit, debt, , , bucketCollateral) = pool.bucketAt(
            2_000.221618840727700609 * 1e18
        );
        assertEq(deposit, 4_000 * 1e18);
        assertEq(debt, 1_000 * 1e18);
        assertEq(bucketCollateral, 0);

        // check bidder and pool balances
        assertEq(
            collateral.balanceOf(address(bidder)),
            99.750057966467722847 * 1e18
        );
        assertEq(quote.balanceOf(address(bidder)), 1_000 * 1e18);
        assertEq(
            collateral.balanceOf(address(pool)),
            100.249942033532277153 * 1e18
        );
        assertEq(quote.balanceOf(address(pool)), 4_000 * 1e18);
        assertEq(pool.totalCollateral(), 100 * 1e18);
    }

    function testPurchaseBidCannotReallocate() public {
        lender.addQuoteToken(
            pool,
            address(lender),
            1_000 * 1e18,
            4_000.927678580567537368 * 1e18
        );
        lender.addQuoteToken(
            pool,
            address(lender),
            1_000 * 1e18,
            3_010.892022197881557845 * 1e18
        );
        lender.addQuoteToken(
            pool,
            address(lender),
            500 * 1e18,
            2_000.221618840727700609 * 1e18
        );

        // borrower takes a loan of 1000 DAI from bucket 4000
        borrower.addCollateral(pool, 100 * 1e18);
        borrower.borrow(pool, 1_000 * 1e18, 3_000 * 1e18);
        // borrower takes a loan of 1000 DAI from bucket 3000
        borrower.borrow(pool, 1_000 * 1e18, 3_000 * 1e18);

        assertEq(pool.lup(), 3_010.892022197881557845 * 1e18);

        // should revert if debt cannot be reallocated
        vm.expectRevert("ajna/failed-to-reallocate");
        bidder.purchaseBid(pool, 1_000 * 1e18, 4_000.927678580567537368 * 1e18);
    }

    function testPurchaseBidUndercollateralized() public {
        lender.addQuoteToken(
            pool,
            address(lender),
            1_000 * 1e18,
            4_000.927678580567537368 * 1e18
        );
        lender.addQuoteToken(
            pool,
            address(lender),
            1_000 * 1e18,
            3_010.892022197881557845 * 1e18
        );
        lender.addQuoteToken(pool, address(lender), 2_000 * 1e18, 1 * 1e18);

        // borrower takes a loan of 1000 DAI from bucket 4000
        borrower.addCollateral(pool, 100 * 1e18);
        borrower.borrow(pool, 1_000 * 1e18, 3_000 * 1e18);
        // borrower takes a loan of 1000 DAI from bucket 3000
        borrower.borrow(pool, 1_000 * 1e18, 3_000 * 1e18);

        assertEq(pool.lup(), 3_010.892022197881557845 * 1e18);

        // should revert when leave pool undercollateralized
        vm.expectRevert("ajna/pool-undercollateralized");
        bidder.purchaseBid(pool, 1_000 * 1e18, 4_000.927678580567537368 * 1e18);
    }
}
