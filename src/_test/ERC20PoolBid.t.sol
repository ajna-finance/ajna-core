// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.11;

import {DSTestPlus} from "./utils/DSTestPlus.sol";
import {UserWithCollateral, UserWithQuoteToken} from "./utils/Users.sol";
import {CollateralToken, QuoteToken} from "./utils/Tokens.sol";

import {ERC20Pool} from "../ERC20Pool.sol";
import {ERC20PoolFactory} from "../ERC20PoolFactory.sol";
import {Buckets} from "../libraries/Buckets.sol";
import {BucketMath} from "../libraries/BucketMath.sol";
import {IPool} from "../interfaces/IPool.sol";

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
        pool = factory.deployPool(address(collateral), address(quote));

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

    // @notice: lender deposits 9000 quote accross 3 buckets
    // @notice: borrower borrows 4000
    // @notice: bidder successfully purchases 6000 quote partially in 2 purchases
    function testPurchaseBidPartialAmount() public {
        lender.addQuoteToken(pool, address(lender), 3_000 * 1e18, 4_000.927678580567537368 * 1e18);
        lender.addQuoteToken(pool, address(lender), 3_000 * 1e18, 3_010.892022197881557845 * 1e18);
        lender.addQuoteToken(pool, address(lender), 3_000 * 1e18, 1_004.989662429170775094 * 1e18);
        assertEq(pool.totalQuoteToken(), 9_000 * 1e45);

        // borrower takes a loan of 4000 DAI making bucket 4000 to be fully utilized
        borrower.addCollateral(pool, 100 * 1e18);
        borrower.borrow(pool, 4_000 * 1e18, 3_000 * 1e18);
        assertEq(pool.lup(), 3_010.892022197881557845 * 1e18);

        // should revert if invalid price
        vm.expectRevert(BucketMath.PriceOutsideBoundry.selector);
        bidder.purchaseBid(pool, 1 * 1e18, 1_000);

        // should revert if bidder doesn't have enough collateral
        vm.expectRevert(IPool.InsufficientCollateralBalance.selector);
        bidder.purchaseBid(pool, 2_000_000 * 1e18, 4_000.927678580567537368 * 1e18);
        // should revert if trying to purchase more than on bucket
        (, , , uint256 amount, uint256 bucket_debt, , , ) = pool.bucketAt(
            4_000.927678580567537368 * 1e18
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                Buckets.InsufficientBucketLiquidity.selector,
                amount + bucket_debt
            )
        );
        bidder.purchaseBid(pool, 4_000 * 1e18, 4_000.927678580567537368 * 1e18);

        // check bidder and pool balances
        assertEq(collateral.balanceOf(address(bidder)), 100 * 1e18);
        assertEq(quote.balanceOf(address(bidder)), 0);
        assertEq(collateral.balanceOf(address(pool)), 100 * 1e18);
        assertEq(quote.balanceOf(address(pool)), 5_000 * 1e18);
        assertEq(pool.totalQuoteToken(), 5_000 * 1e45);
        assertEq(pool.totalCollateral(), 100 * 1e27);

        // check 4_000.927678580567537368 bucket balance before purchase bid
        (, , , uint256 deposit, uint256 debt, , , uint256 bucketCollateral) = pool.bucketAt(
            4_000.927678580567537368 * 1e18
        );
        assertEq(deposit, 0);
        assertEq(debt, 3_000 * 1e45);
        // check 3_010.892022197881557845 bucket balance before purchase bid
        (, , , deposit, debt, , , bucketCollateral) = pool.bucketAt(
            3_010.892022197881557845 * 1e18
        );
        assertEq(deposit, 2_000 * 1e45);
        assertEq(debt, 1_000 * 1e45);
        assertEq(bucketCollateral, 0);

        // purchase 2000 bid from 4_000.927678580567537368 bucket
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(bidder), address(pool), 0.499884067064554306 * 1e18);
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(pool), address(bidder), 2_000 * 1e18);
        vm.expectEmit(true, true, false, true);
        emit Purchase(
            address(bidder),
            4_000.927678580567537368 * 1e18,
            2_000 * 1e45,
            0.499884067064554306651186498 * 1e27
        );
        bidder.purchaseBid(pool, 2_000 * 1e18, 4_000.927678580567537368 * 1e18);

        assertEq(pool.lup(), 1_004.989662429170775094 * 1e18);
        // check 4_000.927678580567537368 bucket balance after purchase bid
        (, , , deposit, debt, , , bucketCollateral) = pool.bucketAt(
            4_000.927678580567537368 * 1e18
        );
        assertEq(deposit, 0);
        assertEq(debt, 1_000 * 1e45);
        assertEq(bucketCollateral, 0.499884067064554306651186498 * 1e27);
        // check 3_010.892022197881557845 bucket balance after purchase bid
        (, , , deposit, debt, , , bucketCollateral) = pool.bucketAt(
            3_010.892022197881557845 * 1e18
        );
        assertEq(deposit, 0);
        assertEq(debt, 3_000 * 1e45);
        assertEq(bucketCollateral, 0);
        // check 1_004.989662429170775094 bucket balance after purchase bid
        (, , , deposit, debt, , , bucketCollateral) = pool.bucketAt(
            1_004.989662429170775094 * 1e18
        );
        assertEq(deposit, 3_000 * 1e45);
        assertEq(debt, 0);
        assertEq(bucketCollateral, 0);

        // check bidder and pool balances
        assertEq(collateral.balanceOf(address(bidder)), 99.500115932935445694 * 1e18);
        assertEq(quote.balanceOf(address(bidder)), 2_000 * 1e18);
        assertEq(collateral.balanceOf(address(pool)), 100.499884067064554306 * 1e18);
        assertEq(quote.balanceOf(address(pool)), 3_000 * 1e18);
        assertEq(pool.totalQuoteToken(), 3_000 * 1e45);
        assertEq(pool.totalCollateral(), 100 * 1e27);
    }

    // @notice: lender deposits 7000 quote accross 3 buckets
    // @notice: borrower borrows 2000 quote
    // @notice: bidder successfully purchases 6000 quote fully accross 2 purchases
    function testPurchaseBidEntireAmount() public {
        uint256 p4000 = 4_000.927678580567537368 * 1e18;
        uint256 p3010 = 3_010.892022197881557845 * 1e18;
        uint256 p2000 = 2_000.221618840727700609 * 1e18;
        lender.addQuoteToken(pool, address(lender), 1_000 * 1e18, p4000);
        lender.addQuoteToken(pool, address(lender), 1_000 * 1e18, p3010);
        lender.addQuoteToken(pool, address(lender), 5_000 * 1e18, p2000);

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
        assertEq(pool.totalCollateral(), 100 * 1e27);
        assertEq(pool.hpb(), p4000);
        assertEq(pool.lup(), p3010);

        // check 4_000.927678580567537368 bucket balance before purchase Bid
        (, , , uint256 deposit, uint256 debt, , , uint256 bucketCollateral) = pool.bucketAt(p4000);
        assertEq(deposit, 0);
        assertEq(debt, 1_000 * 1e45);
        assertEq(bucketCollateral, 0);
        // check 3_010.892022197881557845 bucket balance before purchase bid
        (, , , deposit, debt, , , bucketCollateral) = pool.bucketAt(p3010);
        assertEq(deposit, 0);
        assertEq(debt, 1_000 * 1e45);
        assertEq(bucketCollateral, 0);
        // check 2_000.221618840727700609 bucket balance before purchase bid
        (, , , deposit, debt, , , bucketCollateral) = pool.bucketAt(p2000);
        assertEq(deposit, 5_000 * 1e45);
        assertEq(debt, 0);
        assertEq(bucketCollateral, 0);

        // purchase 1000 bid - entire amount in 4000 bucket
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(bidder), address(pool), 0.249942033532277153 * 1e18);
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(pool), address(bidder), 1_000 * 1e18);
        vm.expectEmit(true, true, false, true);
        emit Purchase(
            address(bidder),
            4_000.927678580567537368 * 1e18,
            1_000 * 1e45,
            0.249942033532277153325593249 * 1e27
        );
        bidder.purchaseBid(pool, 1_000 * 1e18, 4_000.927678580567537368 * 1e18);

        // hbp should be pushed downwards
        assertEq(pool.hpb(), p3010);
        // lup should be pushed downwards
        assertEq(pool.lup(), 2_000.221618840727700609 * 1e18);
        // check 4_000.927678580567537368 bucket balance after purchase Bid
        (, , , deposit, debt, , , bucketCollateral) = pool.bucketAt(p4000);
        assertEq(deposit, 0);
        assertEq(debt, 0);
        assertEq(bucketCollateral, 0.249942033532277153325593249 * 1e27);
        // check 3_010.892022197881557845 bucket balance
        (, , , deposit, debt, , , bucketCollateral) = pool.bucketAt(p3010);
        assertEq(deposit, 0);
        assertEq(debt, 1_000 * 1e45);
        assertEq(bucketCollateral, 0);
        // check 2_000.221618840727700609 bucket balance
        (, , , deposit, debt, , , bucketCollateral) = pool.bucketAt(p2000);
        assertEq(deposit, 4_000 * 1e45);
        assertEq(debt, 1_000 * 1e45);
        assertEq(bucketCollateral, 0);

        // check bidder and pool balances
        assertEq(collateral.balanceOf(address(bidder)), 99.750057966467722847 * 1e18);
        assertEq(quote.balanceOf(address(bidder)), 1_000 * 1e18);
        assertEq(collateral.balanceOf(address(pool)), 100.249942033532277153 * 1e18);
        assertEq(quote.balanceOf(address(pool)), 4_000 * 1e18);
        assertEq(pool.totalCollateral(), 100 * 1e27);
    }

    function testPurchaseBidCannotReallocate() public {
        lender.addQuoteToken(pool, address(lender), 1_000 * 1e18, 4_000.927678580567537368 * 1e18);
        lender.addQuoteToken(pool, address(lender), 1_000 * 1e18, 3_010.892022197881557845 * 1e18);
        lender.addQuoteToken(pool, address(lender), 500 * 1e18, 2_000.221618840727700609 * 1e18);

        // borrower takes a loan of 1000 DAI from bucket 4000
        borrower.addCollateral(pool, 100 * 1e18);
        borrower.borrow(pool, 1_000 * 1e18, 3_000 * 1e18);
        // borrower takes a loan of 1000 DAI from bucket 3000
        borrower.borrow(pool, 1_000 * 1e18, 3_000 * 1e18);

        assertEq(pool.lup(), 3_010.892022197881557845 * 1e18);

        // should revert if trying to bid more than available liquidity (1000 vs 500)
        vm.expectRevert(Buckets.NoDepositToReallocateTo.selector);
        bidder.purchaseBid(pool, 1_000 * 1e18, 4_000.927678580567537368 * 1e18);
    }

    // @notice: lender deposits 4000 quote accross 3 buckets
    // @notice: borrower borrows 2000 quote
    // @notice: bidder attempts to purchase 1000 quote, it reverts
    function testPurchaseBidUndercollateralized() public {
        lender.addQuoteToken(pool, address(lender), 1_000 * 1e18, 4_000.927678580567537368 * 1e18);
        lender.addQuoteToken(pool, address(lender), 1_000 * 1e18, 3_010.892022197881557845 * 1e18);
        lender.addQuoteToken(pool, address(lender), 2_000 * 1e18, 1 * 1e18);

        // borrower takes a loan of 1000 DAI from bucket 4000
        borrower.addCollateral(pool, 100 * 1e18);
        borrower.borrow(pool, 1_000 * 1e18, 3_000 * 1e18);
        // borrower takes a loan of 1000 DAI from bucket 3000
        borrower.borrow(pool, 1_000 * 1e18, 3_000 * 1e18);

        assertEq(pool.lup(), 3_010.892022197881557845 * 1e18);

        // should revert when leave pool undercollateralized
        vm.expectRevert(
            abi.encodeWithSelector(IPool.PoolUndercollateralized.selector, 0.05 * 1e27)
        );
        bidder.purchaseBid(pool, 1_000 * 1e18, 4_000.927678580567537368 * 1e18);
    }
}
