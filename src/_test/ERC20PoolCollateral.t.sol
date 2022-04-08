// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.11;

import {DSTestPlus} from "./utils/DSTestPlus.sol";
import {UserWithCollateral, UserWithQuoteToken} from "./utils/Users.sol";
import {CollateralToken, QuoteToken} from "./utils/Tokens.sol";

import {ERC20Pool} from "../ERC20Pool.sol";
import {ERC20PoolFactory} from "../ERC20PoolFactory.sol";

contract ERC20PoolCollateralTest is DSTestPlus {
    ERC20Pool internal pool;
    CollateralToken internal collateral;
    QuoteToken internal quote;

    UserWithCollateral internal borrower;
    UserWithCollateral internal borrower2;
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

        borrower2 = new UserWithCollateral();
        collateral.mint(address(borrower2), 200 * 1e18);
        borrower2.approveToken(collateral, address(pool), 200 * 1e18);

        bidder = new UserWithCollateral();
        collateral.mint(address(bidder), 100 * 1e18);
        bidder.approveToken(collateral, address(pool), 100 * 1e18);

        lender = new UserWithQuoteToken();
        quote.mint(address(lender), 200_000 * 1e18);
        lender.approveToken(quote, address(pool), 200_000 * 1e18);
    }

    function testAddRemoveCollateral() public {
        // should revert if trying to remove collateral when no available
        vm.expectRevert("ajna/not-enough-collateral");
        borrower.removeCollateral(pool, 10 * 1e18);

        // lender deposits 10000 DAI in 5 buckets each
        lender.addQuoteToken(
            pool,
            address(lender),
            20_000 * 1e45,
            5_007.644384905151472283 * 1e18
        );

        // test deposit collateral
        assertEq(collateral.balanceOf(address(borrower)), 100 * 1e18);
        assertEq(collateral.balanceOf(address(pool)), 0);
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(borrower), address(pool), 100 * 1e18);
        vm.expectEmit(true, true, false, true);
        emit AddCollateral(address(borrower), 100 * 1e27);
        borrower.addCollateral(pool, 100 * 1e27);

        // check balances
        assertEq(collateral.balanceOf(address(borrower)), 0);
        assertEq(collateral.balanceOf(address(pool)), 100 * 1e18);
        assertEq(pool.totalCollateral(), 100 * 1e27);

        // check borrower
        (, , uint256 deposited, uint256 encumbered, , , ) = pool
            .getBorrowerInfo(address(borrower));
        assertEq(deposited, 100 * 1e27);
        assertEq(encumbered, 0);

        // get loan of 20_000 DAI, recheck borrower
        borrower.borrow(pool, 20_000 * 1e45, 2500 * 1e18);
        (, , deposited, encumbered, , , ) = pool.getBorrowerInfo(
            address(borrower)
        );
        assertEq(deposited, 100 * 1e27);
        assertEq(encumbered, 3.993893827662208275880152017 * 1e27);

        // should revert if trying to remove all collateral deposited
        vm.expectRevert("ajna/not-enough-collateral");
        borrower.removeCollateral(pool, 100 * 1e27);

        // borrower pays back entire loan and accumulated debt
        quote.mint(address(borrower), 20_001 * 1e18);
        borrower.approveToken(quote, address(pool), 20_001 * 1e18);
        borrower.repay(pool, 20_001 * 1e45);

        // remove collateral
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(pool), address(borrower), 100 * 1e18);
        vm.expectEmit(true, false, false, true);
        emit RemoveCollateral(address(borrower), 100 * 1e27);
        borrower.removeCollateral(pool, 100 * 1e27);

        // check balances
        assertEq(collateral.balanceOf(address(borrower)), 100 * 1e18);
        assertEq(collateral.balanceOf(address(pool)), 0);
        assertEq(pool.totalCollateral(), 0);

        // check borrower
        (, , deposited, encumbered, , , ) = pool.getBorrowerInfo(
            address(borrower)
        );
        assertEq(deposited, 0);
        assertEq(encumbered, 0);
    }

    function testClaimCollateral() public {
        // should fail if invalid price
        vm.expectRevert("ajna/invalid-bucket-price");
        lender.claimCollateral(
            pool,
            address(lender),
            10_000 * 1e45,
            4_000 * 1e18
        );

        // should revert if no lp tokens in bucket
        vm.expectRevert("ajna/no-claim-to-bucket");
        lender.claimCollateral(
            pool,
            address(lender),
            1 * 1e27,
            4_000.927678580567537368 * 1e18
        );

        // lender deposit DAI in 3 buckets
        lender.addQuoteToken(
            pool,
            address(lender),
            3_000 * 1e45,
            4_000.927678580567537368 * 1e18
        );
        lender.addQuoteToken(
            pool,
            address(lender),
            4_000 * 1e45,
            3_010.892022197881557845 * 1e18
        );
        lender.addQuoteToken(
            pool,
            address(lender),
            5_000 * 1e45,
            1_004.989662429170775094 * 1e18
        );
        assertEq(
            pool.lpBalance(address(lender), 4_000.927678580567537368 * 1e18),
            3_000 * 1e27
        );
        assertEq(
            pool.lpBalance(address(lender), 3_010.892022197881557845 * 1e18),
            4_000 * 1e27
        );
        assertEq(
            pool.lpBalance(address(lender), 1_004.989662429170775094 * 1e18),
            5_000 * 1e27
        );

        // should revert when claiming collateral if no purchase bid was done on bucket
        vm.expectRevert("ajna/insufficient-amount-to-claim");
        lender.claimCollateral(
            pool,
            address(lender),
            1 * 1e27,
            4_000.927678580567537368 * 1e18
        );

        // borrower takes a loan of 4000 DAI
        borrower.addCollateral(pool, 100 * 1e27);
        borrower.borrow(pool, 4_000 * 1e45, 3_000 * 1e18);
        assertEq(pool.lup(), 3_010.892022197881557845 * 1e18);

        // check 3_010.892022197881557845 bucket balance before purchase Bid
        (
            ,
            ,
            ,
            uint256 deposit,
            uint256 debt,
            ,
            uint256 lpOutstanding,
            uint256 bucketCollateral
        ) = pool.bucketAt(3_010.892022197881557845 * 1e18);
        assertEq(deposit, 3_000 * 1e45);
        assertEq(debt, 1_000 * 1e45);
        assertEq(lpOutstanding, 4_000 * 1e27);
        assertEq(bucketCollateral, 0);
        assertEq(
            pool.lpBalance(address(lender), 3_010.892022197881557845 * 1e18),
            4_000 * 1e27
        );

        // bidder purchases some of the middle bucket
        bidder.purchaseBid(pool, 1_500 * 1e45, 3_010.892022197881557845 * 1e18);

        // check balances
        assertEq(
            pool.lpBalance(address(lender), 3_010.892022197881557845 * 1e18),
            4_000 * 1e27
        );
        assertEq(collateral.balanceOf(address(lender)), 0);
        assertEq(
            collateral.balanceOf(address(pool)),
            100.498191230021272793 * 1e18
        );
        assertEq(quote.balanceOf(address(lender)), 188_000 * 1e18);
        assertEq(quote.balanceOf(address(pool)), 6_500 * 1e18);
        assertEq(pool.totalCollateral(), 100 * 1e27);

        // should revert if claiming a larger amount than available in bucket
        vm.expectRevert("ajna/insufficient-amount-to-claim");
        lender.claimCollateral(
            pool,
            address(lender),
            2 * 1e27,
            3_010.892022197881557845 * 1e18
        );

        // lender claims 0.498191230021272793 collateral
        vm.expectEmit(true, true, false, true);
        emit Transfer(
            address(pool),
            address(lender),
            0.498191230021272793 * 1e18
        );
        vm.expectEmit(true, true, false, true);
        emit ClaimCollateral(
            address(lender),
            3_010.892022197881557845 * 1e18,
            0.498191230021272793189085612 * 1e27,
            1_499.999999999999999999999999451 * 1e27
        );
        lender.claimCollateral(
            pool,
            address(lender),
            0.498191230021272793189085612 * 1e27,
            3_010.892022197881557845 * 1e18
        );

        // check 3_010.892022197881557845 bucket balance after collateral claimed
        (, , , deposit, debt, , lpOutstanding, bucketCollateral) = pool
            .bucketAt(3_010.892022197881557845 * 1e18);
        assertEq(deposit, 1_500 * 1e45);
        assertEq(debt, 1_000 * 1e45);
        assertEq(lpOutstanding, 2_500.000000000000000000000000549 * 1e27);
        assertEq(bucketCollateral, 0);

        // claimer lp tokens for pool should be diminished
        assertEq(
            pool.lpBalance(address(lender), 3_010.892022197881557845 * 1e18),
            2_500.000000000000000000000000549 * 1e27
        );
        // claimer collateral balance should increase with claimed amount
        assertEq(
            collateral.balanceOf(address(lender)),
            0.498191230021272793 * 1e18
        );
        // claimer quote token balance should stay the same
        assertEq(quote.balanceOf(address(lender)), 188_000 * 1e18);
        assertEq(collateral.balanceOf(address(pool)), 100 * 1e18);
        assertEq(quote.balanceOf(address(pool)), 6_500 * 1e18);
        assertEq(pool.totalCollateral(), 100 * 1e27);
    }

    function testLiquidateClaimAllCollateral() public {
        // lender deposit in 3 buckets, price spaced
        lender.addQuoteToken(
            pool,
            address(lender),
            10_000 * 1e45,
            10_016.501589292607751220 * 1e18
        );
        lender.addQuoteToken(
            pool,
            address(lender),
            1_000 * 1e45,
            9_020.461710444470171420 * 1e18
        );
        lender.addQuoteToken(
            pool,
            address(lender),
            1_000 * 1e45,
            8_002.824356287850613262 * 1e18
        );
        lender.addQuoteToken(
            pool,
            address(lender),
            1_000 * 1e45,
            100.332368143282009890 * 1e18
        );

        // borrowers deposit collateral
        borrower.addCollateral(pool, 2 * 1e27);
        borrower2.addCollateral(pool, 200 * 1e27);

        // first borrower takes a loan of 12_000 DAI, pushing lup to 8_002.824356287850613262
        borrower.borrow(pool, 12_000 * 1e45, 8_000 * 1e18);

        // 2nd borrower takes a loan of 1_000 DAI, pushing lup to 100.332368143282009890
        borrower2.borrow(pool, 1_000 * 1e45, 100 * 1e18);

        // liquidate borrower
        lender.liquidate(pool, address(borrower));

        // check buckets debt and collateral after liquidation
        (
            ,
            ,
            ,
            uint256 deposit,
            uint256 debt,
            ,
            uint256 lpOutstanding,
            uint256 bucketCollateral
        ) = pool.bucketAt(10_016.501589292607751220 * 1e18);
        assertEq(debt, 0);
        assertEq(deposit, 0);
        assertEq(lpOutstanding, 10_000 * 1e27);
        assertEq(bucketCollateral, 0.998352559609210511014078361 * 1e27);

        (, , , deposit, debt, , lpOutstanding, bucketCollateral) = pool
            .bucketAt(9_020.461710444470171420 * 1e18);
        assertEq(debt, 0);
        assertEq(deposit, 0);
        assertEq(lpOutstanding, 1_000 * 1e27);
        assertEq(bucketCollateral, 0.110859070422319485680287844 * 1e27);

        (, , , deposit, debt, , lpOutstanding, bucketCollateral) = pool
            .bucketAt(8_002.824356287850613262 * 1e18);
        assertEq(debt, 0);
        assertEq(deposit, 0);
        assertEq(lpOutstanding, 1_000 * 1e27);
        assertEq(bucketCollateral, 0.124955885007559370189665834 * 1e27);

        // claim collateral and deactivate bucket 8_002.824356287850613262
        lender.claimCollateral(
            pool,
            address(lender),
            0.124955885007559370189665834 * 1e27,
            8_002.824356287850613262 * 1e18
        );

        (, , , deposit, debt, , lpOutstanding, bucketCollateral) = pool
            .bucketAt(8_002.824356287850613262 * 1e18);
        assertEq(debt, 0);
        assertEq(deposit, 0);
        assertEq(lpOutstanding, 7949);
        assertEq(bucketCollateral, 0);
        assertEq(
            pool.lpBalance(address(lender), 8_002.824356287850613262 * 1e18),
            7949
        );

        // claim collateral and deactivate bucket 9_020.461710444470171420
        lender.claimCollateral(
            pool,
            address(lender),
            0.110859070422319485680287844 * 1e27,
            9_020.461710444470171420 * 1e18
        );

        (, , , deposit, debt, , lpOutstanding, bucketCollateral) = pool
            .bucketAt(9_020.461710444470171420 * 1e18);
        assertEq(debt, 0);
        assertEq(deposit, 0);
        assertEq(lpOutstanding, 7826);
        assertEq(bucketCollateral, 0);
        assertEq(
            pool.lpBalance(address(lender), 9_020.461710444470171420 * 1e18),
            7826
        );

        // claim collateral and deactivate bucket 10_016.501589292607751220
        lender.claimCollateral(
            pool,
            address(lender),
            0.998352559609210511014078361 * 1e27,
            10_016.501589292607751220 * 1e18
        );

        (, , , deposit, debt, , lpOutstanding, bucketCollateral) = pool
            .bucketAt(10_016.501589292607751220 * 1e18);
        assertEq(debt, 0);
        assertEq(deposit, 0);
        assertEq(lpOutstanding, 6046);
        assertEq(bucketCollateral, 0);
        assertEq(
            pool.lpBalance(address(lender), 10_016.501589292607751220 * 1e18),
            6046
        );
    }
}
