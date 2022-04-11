// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.11;

import {DSTestPlus} from "./utils/DSTestPlus.sol";
import {UserWithCollateral, UserWithQuoteToken} from "./utils/Users.sol";
import {CollateralToken, QuoteToken} from "./utils/Tokens.sol";

import {ERC20Pool} from "../ERC20Pool.sol";
import {ERC20PoolFactory} from "../ERC20PoolFactory.sol";
import {Buckets} from "../libraries/Buckets.sol";

contract ERC20PoolCollateralTest is DSTestPlus {
    ERC20Pool internal pool;
    CollateralToken internal collateral;
    QuoteToken internal quote;

    UserWithCollateral internal borrower;
    UserWithQuoteToken internal lender;
    UserWithQuoteToken internal lender1;
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

        lender1 = new UserWithQuoteToken();
        quote.mint(address(lender1), 200_000 * 1e18);
        lender1.approveToken(quote, address(pool), 200_000 * 1e18);
    }

    function testAddRemoveCollateral() public {
        // should revert if trying to remove collateral when no available
        vm.expectRevert(
            abi.encodeWithSelector(
                ERC20Pool.AmountExceedsAvailableCollateral.selector,
                0
            )
        );
        borrower.removeCollateral(pool, 10 * 1e18);
        // lender deposits 10000 DAI in 5 buckets each
        lender.addQuoteToken(
            pool,
            address(lender),
            20_000 * 1e18,
            5_007.644384905151472283 * 1e18
        );

        // test deposit collateral
        assertEq(collateral.balanceOf(address(borrower)), 100 * 1e18);
        assertEq(collateral.balanceOf(address(pool)), 0);
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(borrower), address(pool), 100 * 1e18);
        vm.expectEmit(true, true, false, true);
        emit AddCollateral(address(borrower), 100 * 1e18);
        borrower.addCollateral(pool, 100 * 1e18);

        // check balances
        assertEq(collateral.balanceOf(address(borrower)), 0);
        assertEq(collateral.balanceOf(address(pool)), 100 * 1e18);
        assertEq(pool.totalCollateral(), 100 * 1e18);

        // check borrower
        (, , uint256 deposited, uint256 encumbered, , , ) = pool
            .getBorrowerInfo(address(borrower));
        assertEq(deposited, 100 * 1e18);
        assertEq(encumbered, 0);

        // get loan of 20_000 DAI, recheck borrower
        borrower.borrow(pool, 20_000 * 1e18, 2500 * 1e18);
        (, , deposited, encumbered, , , ) = pool.getBorrowerInfo(
            address(borrower)
        );
        assertEq(deposited, 100 * 1e18);
        assertEq(encumbered, 3.993893827662208276 * 1e18);

        // should revert if trying to remove all collateral deposited
        vm.expectRevert(
            abi.encodeWithSelector(
                ERC20Pool.AmountExceedsAvailableCollateral.selector,
                deposited - encumbered
            )
        );
        borrower.removeCollateral(pool, 100 * 1e18);

        // borrower pays back entire loan and accumulated debt
        quote.mint(address(borrower), 20_001 * 1e18);
        borrower.approveToken(quote, address(pool), 20_001 * 1e18);
        borrower.repay(pool, 20_001 * 1e18);

        // remove collateral
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(pool), address(borrower), 100 * 1e18);
        vm.expectEmit(true, false, false, true);
        emit RemoveCollateral(address(borrower), 100 * 1e18);
        borrower.removeCollateral(pool, 100 * 1e18);

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
        vm.expectRevert(ERC20Pool.InvalidPrice.selector);
        lender.claimCollateral(
            pool,
            address(lender),
            10_000 * 1e18,
            4_000 * 1e18
        );

        // should revert if no lp tokens in bucket
        vm.expectRevert(ERC20Pool.NoClaimToBucket.selector);
        lender.claimCollateral(
            pool,
            address(lender),
            1 * 1e18,
            4_000.927678580567537368 * 1e18
        );

        // lender deposit DAI in 3 buckets
        lender.addQuoteToken(
            pool,
            address(lender),
            3_000 * 1e18,
            4_000.927678580567537368 * 1e18
        );

        lender.addQuoteToken(
            pool,
            address(lender),
            4_000 * 1e18,
            3_010.892022197881557845 * 1e18
        );
        lender.addQuoteToken(
            pool,
            address(lender),
            5_000 * 1e18,
            1_004.989662429170775094 * 1e18
        );

        lender1.addQuoteToken(
            pool,
            address(lender1),
            3_000 * 1e18,
            4_000.927678580567537368 * 1e18
        );

        // check LP balance for lender
        assertEq(
            pool.lpBalance(address(lender), 4_000.927678580567537368 * 1e18),
            3_000 * 1e18
        );
        assertEq(
            pool.lpBalance(address(lender), 3_010.892022197881557845 * 1e18),
            4_000 * 1e18
        );
        assertEq(
            pool.lpBalance(address(lender), 1_004.989662429170775094 * 1e18),
            5_000 * 1e18
        );

        // check LP balance for lender1
        assertEq(
            pool.lpBalance(address(lender1), 4_000.927678580567537368 * 1e18),
            3_000 * 1e18
        );

        // should revert when claiming collateral if no purchase bid was done on bucket
        vm.expectRevert(
            abi.encodeWithSelector(Buckets.ClaimExceedsCollateral.selector, 0)
        );

        lender.claimCollateral(
            pool,
            address(lender),
            1 * 1e18,
            4_000.927678580567537368 * 1e18
        );

        // borrower takes a loan of 4000 DAI
        borrower.addCollateral(pool, 100 * 1e18);
        borrower.borrow(pool, 4_000 * 1e18, 3_000 * 1e18);
        assertEq(pool.lup(), 4_000.927678580567537368 * 1e18);

        // check 4_000.927678580567537368 bucket balance before purchase Bid
        (
            ,
            ,
            ,
            uint256 deposit,
            uint256 debt,
            ,
            uint256 lpOutstanding,
            uint256 bucketCollateral
        ) = pool.bucketAt(4_000.927678580567537368 * 1e18);
        assertEq(deposit, 2_000 * 1e18);
        assertEq(debt, 4_000 * 1e18);
        assertEq(lpOutstanding, 6_000 * 1e18);
        assertEq(bucketCollateral, 0);

        // bidder purchases some of the top bucket
        bidder.purchaseBid(pool, 1_500 * 1e18, 4_000.927678580567537368 * 1e18);

        // check balances
        assertEq(collateral.balanceOf(address(lender)), 0);
        assertEq(
            collateral.balanceOf(address(bidder)),
            99.625086949701584270 * 1e18
        );
        assertEq(
            collateral.balanceOf(address(pool)),
            100.374913050298415730 * 1e18
        );
        assertEq(quote.balanceOf(address(lender)), 188_000 * 1e18);
        assertEq(quote.balanceOf(address(pool)), 9_500 * 1e18);
        assertEq(pool.totalCollateral(), 100 * 1e18);

        lender1.removeQuoteToken(
            pool,
            address(lender1),
            2_000 * 1e18,
            4_000.927678580567537368 * 1e18
        );

        // should revert if claiming larger amount of collateral than LP balance allows
        vm.expectRevert(
            abi.encodeWithSelector(
                Buckets.InsufficientLpBalance.selector,
                1_000 * 1e18
            )
        );
        lender1.claimCollateral(
            pool,
            address(lender1),
            0.3 * 1e18,
            4_000.927678580567537368 * 1e18
        );

        // lender claims 0.374913050298415730 collateral
        vm.expectEmit(true, true, false, true);
        emit Transfer(
            address(pool),
            address(lender),
            0.374913050298415730 * 1e18
        );
        vm.expectEmit(true, true, false, true);
        emit ClaimCollateral(
            address(lender),
            4_000.927678580567537368 * 1e18,
            0.374913050298415730 * 1e18,
            1_500.000000000000000046 * 1e18
        );
        lender.claimCollateral(
            pool,
            address(lender),
            0.374913050298415730 * 1e18,
            4_000.927678580567537368 * 1e18
        );

        // check 4_000.927678580567537368 bucket balance after collateral claimed
        (, , , deposit, debt, , lpOutstanding, bucketCollateral) = pool
            .bucketAt(4_000.927678580567537368 * 1e18);
        assertEq(deposit, 0);
        assertEq(debt, 2_500 * 1e18);
        assertEq(lpOutstanding, 2_499.999999999999999954 * 1e18);
        assertEq(bucketCollateral, 0);

        // claimer lp tokens for pool should be diminished
        assertEq(
            pool.lpBalance(address(lender), 3_010.892022197881557845 * 1e18),
            4_000.000000000000000000 * 1e18
        );
        // claimer collateral balance should increase with claimed amount
        assertEq(
            collateral.balanceOf(address(lender)),
            0.374913050298415730 * 1e18
        );
        // claimer quote token balance should stay the same
        assertEq(quote.balanceOf(address(lender)), 188_000 * 1e18);
        assertEq(collateral.balanceOf(address(pool)), 100 * 1e18);
        assertEq(pool.totalCollateral(), 100 * 1e18);
        assertEq(quote.balanceOf(address(pool)), 7_500 * 1e18);
    }
}
