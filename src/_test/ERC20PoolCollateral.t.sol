// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.11;

import {DSTestPlus} from "./utils/DSTestPlus.sol";
import {UserWithCollateral, UserWithQuoteToken} from "./utils/Users.sol";
import {CollateralToken, QuoteToken} from "./utils/Tokens.sol";

import {ERC20Pool} from "../ERC20Pool.sol";
import {ERC20PoolFactory} from "../ERC20PoolFactory.sol";
import {Buckets} from "../libraries/Buckets.sol";
import {Maths} from "../libraries/Maths.sol";

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

    /**
    With 1 lender and 1 borrower test adding collateral.
    1) repay and removeCollateral
    2) borrower reverts from attempt to withdraw collateral when all collateral is encumbered
    */
    function testAddRemoveCollateral() public {
        // should revert if trying to remove collateral when no available
        vm.expectRevert(
            abi.encodeWithSelector(ERC20Pool.AmountExceedsAvailableCollateral.selector, 0)
        );
        borrower.removeCollateral(pool, 10 * 1e18);
        // lender deposits 20_000 DAI in 5 buckets each
        lender.addQuoteToken(pool, address(lender), 20_000 * 1e18, 5_007.644384905151472283 * 1e18);

        // check initial pool state
        uint256 poolEncumbered = pool.getEncumberedCollateral(pool.totalDebt());
        uint256 collateralization = pool.getPoolCollateralization();
        assertEq(poolEncumbered, 0);
        assertEq(collateralization, Maths.ONE_RAY);
        uint256 targetUtilization = pool.getPoolTargetUtilization();
        uint256 actualUtilization = pool.getPoolActualUtilization();

        // test deposit collateral
        assertEq(collateral.balanceOf(address(borrower)), 100 * 1e18);
        assertEq(collateral.balanceOf(address(pool)), 0);
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(borrower), address(pool), 70 * 1e18);
        vm.expectEmit(true, true, false, true);
        emit AddCollateral(address(borrower), 70 * 1e27);
        borrower.addCollateral(pool, 70 * 1e18);

        // check balances
        assertEq(collateral.balanceOf(address(borrower)), 30 * 1e18);
        assertEq(collateral.balanceOf(address(pool)), 70 * 1e18);
        assertEq(pool.totalCollateral(), 70 * 1e27);

        // check borrower
        (, , uint256 deposited, uint256 borrowerEncumbered, uint256 borrowerCollateralization, ,)
            = pool.getBorrowerInfo(address(borrower));
        assertEq(deposited, 70 * 1e27);
        assertEq(borrowerEncumbered, 0);
        assertEq(borrowerCollateralization, Maths.ONE_RAY);

        // get loan of 20_000 DAI, recheck borrower
        borrower.borrow(pool, 20_000 * 1e18, 2500 * 1e18);
        (, , deposited, borrowerEncumbered, borrowerCollateralization, , ) = pool.getBorrowerInfo(
            address(borrower)
        );
        assertEq(deposited, 70 * 1e27);
        assertEq(borrowerEncumbered, 3.993893827662208275880152017 * 1e27);
        assertEq(borrowerCollateralization, 17.526755347168030152990500002 * 1e27);
        collateralization = pool.getPoolCollateralization();
        assertEq(collateralization, borrowerCollateralization);

        // check pool state after loan
        poolEncumbered = pool.getEncumberedCollateral(pool.totalDebt());
        targetUtilization = pool.getPoolTargetUtilization();
        actualUtilization = pool.getPoolActualUtilization();
        assertEq(poolEncumbered, borrowerEncumbered);
        assertGt(actualUtilization, targetUtilization);

        // add some collateral
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(borrower), address(pool), 30 * 1e18);
        vm.expectEmit(true, true, false, true);
        emit AddCollateral(address(borrower), 30 * 1e27);
        borrower.addCollateral(pool, 30 * 1e18);
        (, , deposited, borrowerEncumbered, borrowerCollateralization, , ) = pool.getBorrowerInfo(
            address(borrower)
        );
        assertEq(deposited, 100 * 1e27);
        assertEq(borrowerEncumbered, 3.993893827662208275880152017 * 1e27);
        // ensure collateralization increased and target utilization decreased
        assertLt(collateralization, pool.getPoolCollateralization());
        assertGt(targetUtilization, pool.getPoolTargetUtilization());
        collateralization = pool.getPoolCollateralization();
        targetUtilization = pool.getPoolTargetUtilization();

        // should revert if trying to remove all collateral deposited
        vm.expectRevert(
            abi.encodeWithSelector(
                ERC20Pool.AmountExceedsAvailableCollateral.selector,
                deposited - borrowerEncumbered
            )
        );
        borrower.removeCollateral(pool, 100 * 1e18);

        // remove some collateral
        borrower.removeCollateral(pool, 20 * 1e18);
        (, , deposited, borrowerEncumbered, borrowerCollateralization, , ) = pool.getBorrowerInfo(
            address(borrower)
        );
        assertEq(deposited, 80 * 1e27);
        assertEq(borrowerEncumbered, 3.993893827662208275880152017 * 1e27);
        assertEq(borrowerCollateralization, 20.030577539620605889132000002 * 1e27);
        assertEq(pool.getPoolCollateralization(), borrowerCollateralization);
        // ensure collateralization decreased and target utilization increased
        assertGt(collateralization, pool.getPoolCollateralization());
        assertLt(targetUtilization, pool.getPoolTargetUtilization());
        collateralization = pool.getPoolCollateralization();
        actualUtilization = pool.getPoolActualUtilization();
        targetUtilization = pool.getPoolTargetUtilization();

        // borrower repays part of the loan
        quote.mint(address(borrower), 5_000 * 1e18);
        borrower.approveToken(quote, address(pool), 5_000 * 1e18);
        borrower.repay(pool, 5_000 * 1e18);
        (, , deposited, borrowerEncumbered, borrowerCollateralization, , ) = pool.getBorrowerInfo(
            address(borrower)
        );
        assertEq(deposited, 80 * 1e27);
        assertEq(borrowerEncumbered, 2.995420370746656206910114013 * 1e27);
        assertEq(borrowerCollateralization, 26.707436719494141185509333334 * 1e27);
        assertEq(pool.getPoolCollateralization(), borrowerCollateralization);
        // collateralization should increase, decreasing target utilization
        assertLt(collateralization, pool.getPoolCollateralization());
        assertGt(actualUtilization, pool.getPoolActualUtilization());
        assertGt(targetUtilization, pool.getPoolTargetUtilization());
        actualUtilization = pool.getPoolActualUtilization();
        targetUtilization = pool.getPoolTargetUtilization();

        // borrower pays back entire loan and accumulated debt
        quote.mint(address(borrower), 15_001 * 1e18);
        borrower.approveToken(quote, address(pool), 15_001 * 1e18);
        borrower.repay(pool, 15_001 * 1e18);
        // since collateralization dropped to 100%, target utilization should increase
        assertEq(pool.getPoolCollateralization(), Maths.ONE_RAY);
        assertGt(actualUtilization, pool.getPoolActualUtilization());
        assertLt(targetUtilization, pool.getPoolTargetUtilization());
        actualUtilization = pool.getPoolActualUtilization();
        targetUtilization = pool.getPoolTargetUtilization();

        // remove remaining collateral
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(pool), address(borrower), 80 * 1e18);
        vm.expectEmit(true, false, false, true);
        emit RemoveCollateral(address(borrower), 80 * 1e27);
        borrower.removeCollateral(pool, 80 * 1e18);
        assertEq(pool.getPoolCollateralization(), Maths.ONE_RAY);
        assertEq(actualUtilization, pool.getPoolActualUtilization());
        assertEq(targetUtilization, pool.getPoolTargetUtilization());

        // check borrower balances
        (, , deposited, borrowerEncumbered, borrowerCollateralization, , ) = pool.getBorrowerInfo(
            address(borrower)
        );
        assertEq(deposited, 0);
        assertEq(borrowerEncumbered, 0);
        assertEq(borrowerCollateralization, Maths.ONE_RAY);
        assertEq(collateral.balanceOf(address(borrower)), 100 * 1e18);
        // check pool balances
        poolEncumbered = pool.getEncumberedCollateral(pool.totalDebt());
        assertEq(poolEncumbered, borrowerEncumbered);
        assertEq(pool.getPoolCollateralization(), borrowerCollateralization);
        assertEq(pool.getPoolTargetUtilization(), Maths.ONE_RAY);
        assertEq(pool.getPoolActualUtilization(), 0);
        assertEq(pool.totalCollateral(), 0);
        assertEq(collateral.balanceOf(address(pool)), 0);
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
        lender.claimCollateral(pool, address(lender), 10_000 * 1e18, 4_000 * 1e18);

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
        vm.expectRevert(abi.encodeWithSelector(Buckets.ClaimExceedsCollateral.selector, 0));

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
        assertEq(pool.lpBalance(address(lender), priceHigh), 3_000 * 1e27);
        assertEq(collateral.balanceOf(address(bidder)), 99.625086949701584271 * 1e18);
        assertEq(collateral.balanceOf(address(pool)), 100.374913050298415729 * 1e18);
        assertEq(quote.balanceOf(address(lender)), 188_000 * 1e18);
        assertEq(quote.balanceOf(address(pool)), 9_500 * 1e18);
        assertEq(pool.totalCollateral(), 100 * 1e27);

        lender1.removeQuoteToken(pool, address(lender1), 2_000 * 1e18, priceHigh);

        // should revert if claiming larger amount of collateral than LP balance allows
        vm.expectRevert(
            abi.encodeWithSelector(Buckets.InsufficientLpBalance.selector, 1000 * 1e27)
        );
        lender1.claimCollateral(pool, address(lender1), 0.3 * 1e18, priceHigh);

        // lender claims 0.2811 collateral
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(pool), address(lender), 0.2811 * 1e18);
        vm.expectEmit(true, true, false, true);
        emit ClaimCollateral(
            address(lender),
            priceHigh,
            0.2811 * 1e27,
            2_999.095387863993426011052800000 * 1e27
        );
        lender.claimCollateral(pool, address(lender), 0.2811 * 1e18, priceHigh);

        // check 4_000.927678580567537368 bucket balance after collateral claimed
        (, , , deposit, debt, , lpOutstanding, bucketCollateral) = pool.bucketAt(
            4_000.927678580567537368 * 1e18
        );
        assertEq(deposit, 0);
        assertEq(debt, 0);
        assertEq(lpOutstanding, 1_000.9046121360065739889472 * 1e27);
        assertEq(bucketCollateral, 0.093813050298415729988389873 * 1e27);

        // claimer lp tokens for pool should be diminished
        assertEq(pool.lpBalance(address(lender), priceHigh), 0.9046121360065739889472 * 1e27);
        // claimer collateral balance should increase with claimed amount
        assertEq(collateral.balanceOf(address(lender)), 0.2811 * 1e18);
        // claimer quote token balance should stay the same
        assertEq(quote.balanceOf(address(lender)), 188_000 * 1e18);
        assertEq(collateral.balanceOf(address(pool)), 100.093813050298415729 * 1e18);
        assertEq(pool.totalCollateral(), 100 * 1e27);
        assertEq(quote.balanceOf(address(pool)), 7_500 * 1e18);
    }

    // @notice: with 1 lender and 2 borrowers tests addQuoteToken, addCollateral, borrow
    // @notice: liquidate and then all collateral is claimed
    function testLiquidateClaimAllCollateral() public {
        uint256 p10016 = 10_016.501589292607751220 * 1e18;
        uint256 p9020 = 9_020.461710444470171420 * 1e18;
        uint256 p8002 = 8_002.824356287850613262 * 1e18;
        uint256 p100 = 100.332368143282009890 * 1e18;
        lender.addQuoteToken(pool, address(lender), 10_000 * 1e18, p10016);
        lender.addQuoteToken(pool, address(lender), 1_000 * 1e18, p9020);
        lender.addQuoteToken(pool, address(lender), 1_000 * 1e18, p8002);
        lender.addQuoteToken(pool, address(lender), 1_000 * 1e18, p100);

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
        ) = pool.bucketAt(p10016);
        assertEq(debt, 0);
        assertEq(deposit, 0);
        assertEq(lpOutstanding, 10_000 * 1e27);
        assertEq(bucketCollateral, 1.198023071531052613216894034 * 1e27);

        (, , , deposit, debt, , lpOutstanding, bucketCollateral) = pool.bucketAt(p9020);
        assertEq(debt, 0);
        assertEq(deposit, 0);
        assertEq(lpOutstanding, 1_000 * 1e27);
        assertEq(bucketCollateral, 0.221718140844638971360575690 * 1e27);

        (, , , deposit, debt, , lpOutstanding, bucketCollateral) = pool.bucketAt(p8002);
        assertEq(debt, 0);
        assertEq(deposit, 0);
        assertEq(lpOutstanding, 1_000 * 1e27);
        assertEq(bucketCollateral, 0.124955885007559370189665835 * 1e27);

        // claim collateral from bucket 8_002.824356287850613262
        lender.claimCollateral(pool, address(lender), 0.124955885007559370 * 1e18, p8002);

        (, , , deposit, debt, , lpOutstanding, bucketCollateral) = pool.bucketAt(p8002);
        assertEq(debt, 0);
        assertEq(deposit, 0);
        assertEq(lpOutstanding, 0.000000000000001517862363840 * 1e27);
        assertEq(bucketCollateral, 0.000000000000000000189665835 * 1e27);
        assertEq(pool.lpBalance(address(lender), p8002), 0.000000000000001517862363840 * 1e27);

        // claim collateral from bucket 9_020.461710444470171420
        lender.claimCollateral(pool, address(lender), 0.221718140844638971 * 1e18, p9020);

        (, , , deposit, debt, , lpOutstanding, bucketCollateral) = pool.bucketAt(p9020);
        assertEq(debt, 0);
        assertEq(deposit, 0);
        assertEq(lpOutstanding, 1626279602486); // RAY dust
        assertEq(bucketCollateral, 360575690); // RAY dust
        assertEq(pool.lpBalance(address(lender), p9020), 1626279602486); // RAY dust

        (uint256 col, uint256 quoteVal) = pool.getLPTokenExchangeValue(
            pool.getLPTokenBalance(address(lender), 10_016.501589292607751220 * 1e18),
            10_016.501589292607751220 * 1e18
        );
        assertEq(col, 1.198023071531052613216894034 * 1e27);
        assertEq(quoteVal, 0);

        // claim collateral from bucket 10_016.501589292607751220
        lender.claimCollateral(pool, address(lender), 1.198023071531052613 * 1e18, p10016);

        (, , , deposit, debt, , lpOutstanding, bucketCollateral) = pool.bucketAt(p10016);
        assertEq(debt, 0);
        assertEq(deposit, 0);
        assertEq(lpOutstanding, 1810432862926); // RAY dust
        assertEq(bucketCollateral, 216894034); // RAY dust
        assertEq(pool.lpBalance(address(lender), p10016), 1810432862926); // RAy dust
    }
}
