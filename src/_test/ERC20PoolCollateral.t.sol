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
    UserWithCollateral internal borrower2;
    UserWithQuoteToken internal lender;
    UserWithQuoteToken internal lender1;
    UserWithCollateral internal bidder;

    function setUp() public {
        collateral = new CollateralToken();
        quote = new QuoteToken();

        ERC20PoolFactory factory = new ERC20PoolFactory();
        pool = factory.deployPool(address(collateral), address(quote));

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

        lender1 = new UserWithQuoteToken();
        quote.mint(address(lender1), 200_000 * 1e18);
        lender1.approveToken(quote, address(pool), 200_000 * 1e18);
    }

    // @notice: With 1 lender and 1 borrower tests adding collateral,
    // @notice: repay and removeCollateral
    // @notice: borrower reverts:
    // @notice:     attempts to withdraw collateral when none is available
    // @notice:     attempts to withdraw all collateral deposited with outstanding debt

    function testAddRemoveCollateral() public {
        // should revert if trying to remove collateral when no available
        vm.expectRevert(
            abi.encodeWithSelector(
                ERC20Pool.AmountExceedsAvailableCollateral.selector,
                0
            )
        );
        borrower.removeCollateral(pool, 10 * 1e18);
        // lender deposits 20_000 DAI in one bucket
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
        emit AddCollateral(address(borrower), 100 * 1e27);
        borrower.addCollateral(pool, 100 * 1e18);

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
        borrower.borrow(pool, 20_000 * 1e18, 2500 * 1e18);
        (, , deposited, encumbered, , , ) = pool.getBorrowerInfo(
            address(borrower)
        );
        assertEq(deposited, 100 * 1e27);
        assertEq(encumbered, 3.993893827662208275880152017 * 1e27);

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
        emit RemoveCollateral(address(borrower), 100 * 1e27);
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

    // @notice: With 2 lenders, 1 borrower and 1 bidder tests adding quote token, adding collateral
    // @notice: and borrowing. purchaseBid is made then collateral is claimed and quote token is removed
    // @notice: lender1 reverts:
    // @notice:     attempts to claim from invalidPrice
    // @notice:     attempts to claim more than LP balance allows
    // @notice: lender reverts:
    // @notice:     attempts to claim from bucket with no claimable collateral

    function testClaimCollateral() public {
        uint256 priceHigh = 4_000.927678580567537368 * 1e18;
        uint256 priceMed = 3_010.892022197881557845 * 1e18;
        uint256 priceLow = 1_004.989662429170775094 * 1e18;
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
        lender.claimCollateral(pool, address(lender), 1 * 1e18, priceHigh);

        // lender deposit DAI in 3 buckets
        lender.addQuoteToken(pool, address(lender), 3_000 * 1e18, priceHigh);
        lender.addQuoteToken(pool, address(lender), 4_000 * 1e18, priceMed);
        lender.addQuoteToken(pool, address(lender), 5_000 * 1e18, priceLow);

        lender1.addQuoteToken(pool, address(lender1), 3_000 * 1e18, priceHigh);

        // check LP balance for lender
        assertEq(pool.lpBalance(address(lender), priceHigh), 3_000 * 1e27);
        assertEq(pool.lpBalance(address(lender), priceMed), 4_000 * 1e27);
        assertEq(pool.lpBalance(address(lender), priceLow), 5_000 * 1e27);

        // check LP balance for lender1
        assertEq(pool.lpBalance(address(lender1), priceHigh), 3_000 * 1e27);

        // should revert when claiming collateral if no purchase bid was done on bucket
        vm.expectRevert(
            abi.encodeWithSelector(Buckets.ClaimExceedsCollateral.selector, 0)
        );

        lender.claimCollateral(pool, address(lender), 1 * 1e18, priceHigh);

        // borrower takes a loan of 4000 DAI
        borrower.addCollateral(pool, 100 * 1e18);
        borrower.borrow(pool, 4_000 * 1e18, 3_000 * 1e18);
        assertEq(pool.lup(), priceHigh);

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
        assertEq(deposit, 2_000 * 1e45);
        assertEq(debt, 4_000 * 1e45);
        assertEq(lpOutstanding, 6_000 * 1e27);
        assertEq(bucketCollateral, 0);

        // bidder purchases some of the top bucket
        bidder.purchaseBid(pool, 1_500 * 1e18, priceHigh);

        // check 4_000.927678580567537368 bucket collateral after purchase Bid
        (, , , , , , , bucketCollateral) = pool.bucketAt(priceHigh);
        assertEq(bucketCollateral, 0.374913050298415729988389873 * 1e27);

        // check balances
        assertEq(collateral.balanceOf(address(lender)), 0);
        assertEq(pool.lpBalance(address(lender), priceMed), 4_000 * 1e27);
        assertEq(
            collateral.balanceOf(address(bidder)),
            99.625086949701584271 * 1e18
        );
        assertEq(
            collateral.balanceOf(address(pool)),
            100.374913050298415729 * 1e18
        );
        assertEq(quote.balanceOf(address(lender)), 188_000 * 1e18);
        assertEq(quote.balanceOf(address(pool)), 9_500 * 1e18);
        assertEq(pool.totalCollateral(), 100 * 1e27);

        lender1.removeQuoteToken(
            pool,
            address(lender1),
            2_000 * 1e18,
            priceHigh
        );

        // should revert if claiming larger amount of collateral than LP balance allows
        vm.expectRevert(
            abi.encodeWithSelector(
                Buckets.InsufficientLpBalance.selector,
                999.999999999999998 * 1e27
            )
        );
        lender1.claimCollateral(pool, address(lender1), 0.3 * 1e18, priceHigh);

        // lender claims 0.374913050298415729 collateral
        vm.expectEmit(true, true, false, true);
        emit Transfer(
            address(pool),
            address(lender),
            0.374913050298415729 * 1e18
        );
        vm.expectEmit(true, true, false, true);
        emit ClaimCollateral(
            address(lender),
            priceHigh,
            0.374913050298415729 * 1e27,
            1_499.999999999999996045523599297 * 1e27
        );
        lender.claimCollateral(
            pool,
            address(lender),
            0.374913050298415729 * 1e18,
            priceHigh
        );

        // check 4_000.927678580567537368 bucket balance after collateral claimed
        (, , , deposit, debt, , lpOutstanding, bucketCollateral) = pool
            .bucketAt(4_000.927678580567537368 * 1e18);
        assertEq(deposit, 0);
        assertEq(debt, 2_500 * 1e45);
        assertEq(lpOutstanding, 2_500.000000000000001954476400703 * 1e27);
        assertEq(bucketCollateral, 988389873);

        // claimer lp tokens for pool should be diminished
        assertEq(
            pool.lpBalance(address(lender), priceMed),
            4_000.000000000000000000 * 1e27
        );
        // claimer collateral balance should increase with claimed amount
        assertEq(
            collateral.balanceOf(address(lender)),
            0.374913050298415729 * 1e18
        );
        // claimer quote token balance should stay the same
        assertEq(quote.balanceOf(address(lender)), 188_000 * 1e18);
        assertEq(collateral.balanceOf(address(pool)), 100 * 1e18);
        assertEq(pool.totalCollateral(), 100 * 1e27);
        assertEq(quote.balanceOf(address(pool)), 7_500 * 1e18);
    }

    // @notice: with 1 lender and 2 borrowers tests addQuoteToken, addCollateral, borrow
    // @notice: liquidate and then all collateral is claimed
    function testLiquidateClaimAllCollateral() public {
        uint256 priceHighest = 10_016.501589292607751220 * 1e18;
        uint256 priceHigh = 9_020.461710444470171420 * 1e18;
        uint256 priceMed = 8_002.824356287850613262 * 1e18;
        uint256 priceLow = 100.332368143282009890 * 1e18;

        // lender deposit in 3 buckets, price spaced
        lender.addQuoteToken(
            pool,
            address(lender),
            10_000 * 1e18,
            priceHighest
        );
        lender.addQuoteToken(pool, address(lender), 1_000 * 1e18, priceHigh);
        lender.addQuoteToken(pool, address(lender), 1_000 * 1e18, priceMed);
        lender.addQuoteToken(pool, address(lender), 1_000 * 1e18, priceLow);

        // borrowers deposit collateral
        borrower.addCollateral(pool, 2 * 1e18);
        borrower2.addCollateral(pool, 200 * 1e18);

        // first borrower takes a loan of 12_000 DAI, pushing lup to 8_002.824356287850613262
        borrower.borrow(pool, 12_000 * 1e18, 8_000 * 1e18);

        // 2nd borrower takes a loan of 1_000 DAI, pushing lup to 100.332368143282009890
        borrower2.borrow(pool, 1_000 * 1e18, 100 * 1e18);

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
        ) = pool.bucketAt(priceHighest);
        assertEq(debt, 0);
        assertEq(deposit, 0);
        assertEq(lpOutstanding, 10_000 * 1e27);
        assertEq(bucketCollateral, 0.998352559609210511014078361 * 1e27);

        (, , , deposit, debt, , lpOutstanding, bucketCollateral) = pool
            .bucketAt(priceHigh);
        assertEq(debt, 0);
        assertEq(deposit, 0);
        assertEq(lpOutstanding, 1_000 * 1e27);
        assertEq(bucketCollateral, 0.110859070422319485680287844 * 1e27);

        (, , , deposit, debt, , lpOutstanding, bucketCollateral) = pool
            .bucketAt(priceMed);
        assertEq(debt, 0);
        assertEq(deposit, 0);
        assertEq(lpOutstanding, 1_000 * 1e27);
        assertEq(bucketCollateral, 0.124955885007559370189665834 * 1e27);

        // claim collateral from bucket 8_002.824356287850613262
        lender.claimCollateral(
            pool,
            address(lender),
            0.124955885007559370 * 1e18,
            priceMed
        );

        (, , , deposit, debt, , lpOutstanding, bucketCollateral) = pool
            .bucketAt(priceMed);
        assertEq(debt, 0);
        assertEq(deposit, 0);
        assertEq(lpOutstanding, 0.000000000000000517862363840 * 1e27);
        assertEq(bucketCollateral, 0.000000000000000000189665834 * 1e27);
        assertEq(
            pool.lpBalance(address(lender), priceMed),
            0.000000000000000517862363840 * 1e27
        );

        // claim collateral from bucket 9_020.461710444470171420
        lender.claimCollateral(
            pool,
            address(lender),
            0.110859070422319485 * 1e18,
            priceHigh
        );

        (, , , deposit, debt, , lpOutstanding, bucketCollateral) = pool
            .bucketAt(priceHigh);
        assertEq(debt, 0);
        assertEq(deposit, 0);
        assertEq(lpOutstanding, 0.000000000000005136510456708 * 1e27);
        assertEq(bucketCollateral, 0.000000000000000000680287844 * 1e27);
        assertEq(
            pool.lpBalance(address(lender), priceHigh),
            0.000000000000005136510456708 * 1e27
        );

        (uint256 col, uint256 quote) = pool.getLPTokenExchangeValue(
            pool.getLPTokenBalance(address(lender), priceHighest),
            priceHighest
        );
        assertEq(col, 0.998352559609210511014078361 * 1e27);
        assertEq(quote, 0);

        // claim collateral from bucket 10_016.501589292607751220
        lender.claimCollateral(
            pool,
            address(lender),
            0.998352559609210510 * 1e18,
            priceHighest
        );

        (, , , deposit, debt, , lpOutstanding, bucketCollateral) = pool
            .bucketAt(priceHighest);
        assertEq(debt, 0);
        assertEq(deposit, 0);
        assertEq(lpOutstanding, 0.000000000000000157517520669 * 1e27);
        assertEq(bucketCollateral, 0.000000000000000001014078361 * 1e27);
        assertEq(
            pool.lpBalance(address(lender), priceHighest),
            0.000000000000000157517520669 * 1e27
        );
    }
}
