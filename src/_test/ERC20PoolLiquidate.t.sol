// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.11;

import {DSTestPlus} from "./utils/DSTestPlus.sol";
import {UserWithCollateral, UserWithQuoteToken} from "./utils/Users.sol";
import {CollateralToken, QuoteToken} from "./utils/Tokens.sol";

import {ERC20Pool} from "../ERC20Pool.sol";
import {ERC20PoolFactory} from "../ERC20PoolFactory.sol";

import {Maths} from "../libraries/Maths.sol";

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
        pool = factory.deployPool(address(collateral), address(quote));

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

    // @notice: with 1 lender and 2 borrowers -- quote is deposited
    // @notice: borrow occurs, time passes then successful liquidation
    // @notice: is called
    // @notice: lender reverts:
    // @notice:    attempts to call liquidate on borrower that is collateralized

    function testLiquidate() public {
        // lender deposit in 3 buckets, price spaced
        uint256 priceHigh = 10_016.501589292607751220 * 1e18;
        uint256 priceMed = 9_020.461710444470171420 * 1e18;
        uint256 priceLow = 100.332368143282009890 * 1e18;

        lender.addQuoteToken(pool, address(lender), 10_000 * 1e18, priceHigh);
        lender.addQuoteToken(pool, address(lender), 1_000 * 1e18, priceMed);
        lender.addQuoteToken(pool, address(lender), 10_000 * 1e18, priceLow);

        // should revert when no debt
        vm.expectRevert(ERC20Pool.NoDebtToLiquidate.selector);
        lender.liquidate(pool, address(borrower));

        // borrowers deposit collateral
        borrower.addCollateral(pool, 2 * 1e18);
        borrower2.addCollateral(pool, 200 * 1e18);

        // check pool balance
        assertEq(pool.totalQuoteToken(), 21_000 * 1e45);
        assertEq(pool.totalDebt(), 0);
        assertEq(pool.totalCollateral(), 202 * 1e27);
        assertEq(pool.hdp(), priceHigh);

        // first borrower takes a loan of 11_000 DAI, pushing lup to 9_000
        borrower.borrow(pool, 11_000 * 1e18, 9_000 * 1e18);
        // 2nd borrower takes a loan of 1_000 DAI, pushing lup to 100
        borrower2.borrow(pool, 1_000 * 1e18, 100 * 1e18);
        (
            uint256 borrowerDebt,
            uint256 borrowerPendingDebt,
            uint256 collateralDeposited,
            uint256 collateralEncumbered,
            uint256 collateralization,
            uint256 borrowerInflator,

        ) = pool.getBorrowerInfo(address(borrower2));

        // should revert when borrower collateralized
        vm.expectRevert(
            abi.encodeWithSelector(
                ERC20Pool.BorrowerIsCollateralized.selector,
                20.066473628656401978000000001 * 1e27
            )
        );
        lender.liquidate(pool, address(borrower2));

        // check borrower 1 is undercollateralized
        (
            borrowerDebt,
            borrowerPendingDebt,
            collateralDeposited,
            collateralEncumbered,
            collateralization,
            borrowerInflator,

        ) = pool.getBorrowerInfo(address(borrower));
        assertEq(borrowerDebt, 11_000 * 1e45);
        assertEq(borrowerPendingDebt, 11_000 * 1e45);
        assertEq(collateralDeposited, 2 * 1e27);
        assertEq(collateralEncumbered, 109.635606171392167204250999673 * 1e27);
        assertEq(collateralization, 0.018242248753324001798181818 * 1e27);
        assertEq(borrowerInflator, 1 * 1e18);

        // check pool balance
        assertEq(pool.totalQuoteToken(), 9_000 * 1e45);
        assertEq(pool.totalDebt(), 12_000 * 1e45);
        assertEq(pool.totalCollateral(), 202 * 1e27);
        assertEq(pool.lup(), priceLow);
        assertEq(quote.balanceOf(address(pool)), 9_000 * 1e18);

        assertEq(pool.lastInflatorSnapshotUpdate(), 0);

        // check 10_016.501589292607751220 bucket balance before liquidate
        (
            ,
            ,
            ,
            uint256 deposit,
            uint256 debt,
            ,
            ,
            uint256 bucketCollateral
        ) = pool.bucketAt(priceHigh);
        assertEq(debt, 10_000 * 1e45);
        assertEq(deposit, 0);
        assertEq(bucketCollateral, 0);

        // check 9_020.461710444470171420 bucket balance before liquidate
        (, , , deposit, debt, , , bucketCollateral) = pool.bucketAt(priceMed);
        assertEq(debt, 1_000 * 1e45);
        assertEq(deposit, 0);
        assertEq(bucketCollateral, 0);

        // check 100.332368143282009890 bucket balance before liquidate
        (, , , deposit, debt, , , bucketCollateral) = pool.bucketAt(priceLow);
        assertEq(debt, 1_000 * 1e45);
        assertEq(deposit, 9_000 * 1e45);
        assertEq(bucketCollateral, 0);

        skip(8200);

        // liquidate borrower
        vm.expectEmit(true, false, false, true);
        emit Liquidate(
            address(borrower),
            11_000.143012090549955 * 1e45,
            1.109226051001900281453704292 * 1e27
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
        assertEq(collateralDeposited, 0.890773948998099718546295708 * 1e27);
        assertEq(collateralEncumbered, 0);
        assertEq(collateralization, 0);
        assertEq(borrowerInflator, 1.000013001099140905 * 1e18);

        // check pool balance and that interest accumulated
        assertEq(pool.totalQuoteToken(), 9_000 * 1e45);
        assertEq(pool.totalDebt(), 1000.013001099140905000 * 1e45);
        assertEq(
            pool.totalCollateral(),
            200.890773948998099718546295708 * 1e27
        );
        assertEq(pool.inflatorSnapshot(), 1.000013001099140905 * 1e18);
        assertEq(pool.lastInflatorSnapshotUpdate(), 8200);
        assertEq(pool.lup(), priceLow);
        assertEq(quote.balanceOf(address(pool)), 9_000 * 1e18);

        // check 10_016.501589292607751220 bucket balance after liquidate
        (, , , deposit, debt, , , bucketCollateral) = pool.bucketAt(priceHigh);
        assertEq(debt, 0);
        assertEq(deposit, 0);
        assertEq(bucketCollateral, 0.998365539289815566628655632 * 1e27);

        // check 9_020.461710444470171420 bucket balance after liquidate
        (, , , deposit, debt, , , bucketCollateral) = pool.bucketAt(priceMed);
        assertEq(debt, 0);
        assertEq(deposit, 0);
        assertEq(bucketCollateral, 0.110860511712084714825048660 * 1e27);

        // check 100.332368143282009890 bucket balance after purchase bid
        (, , , deposit, debt, , , bucketCollateral) = pool.bucketAt(priceLow);
        assertEq(debt, 1_000 * 1e45);
        assertEq(deposit, 9_000 * 1e45);
        assertEq(bucketCollateral, 0);
    }

    // @notice: with 1 lender and 2 borrowers --  quote is deposited
    // @notice: borrow occurs then successful liquidation is called.
    // @notice: borrower balances are checked
    function testLiquidateScenario1NoTimeWarp() public {
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

        // check pool balance
        assertEq(pool.totalQuoteToken(), 13_000 * 1e45);
        assertEq(pool.totalDebt(), 0);
        assertEq(pool.totalCollateral(), 202 * 1e27);
        assertEq(pool.hdp(), priceHighest);

        // first borrower takes a loan of 12_000 DAI, pushing lup to 8_002.824356287850613262
        borrower.borrow(pool, 12_000 * 1e18, 8_000 * 1e18);

        // 2nd borrower takes a loan of 1_000 DAI, pushing lup to 100.332368143282009890
        borrower2.borrow(pool, 1_000 * 1e18, 100 * 1e18);

        // check borrower 1 is undercollateralized and collateral not enough to cover debt
        (
            uint256 borrowerDebt,
            uint256 borrowerPendingDebt,
            uint256 collateralDeposited,
            uint256 collateralEncumbered,
            uint256 collateralization,
            uint256 borrowerInflator,

        ) = pool.getBorrowerInfo(address(borrower));
        assertEq(borrowerDebt, 12_000 * 1e45);
        assertEq(borrowerPendingDebt, 12_000 * 1e45);
        assertEq(collateralDeposited, 2 * 1e27);
        assertEq(collateralEncumbered, 119.602479459700546041001090552 * 1e27);
        assertEq(collateralization, 0.016722061357213668315000000 * 1e27);
        assertEq(borrowerInflator, 1 * 1e18);

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
            ,
            uint256 bucketCollateral
        ) = pool.bucketAt(priceHighest);
        assertEq(debt, 0);
        assertEq(deposit, 0);
        assertEq(bucketCollateral, 0.998352559609210511014078361 * 1e27);

        (, , , deposit, debt, , , bucketCollateral) = pool.bucketAt(priceMed);
        assertEq(debt, 0);
        assertEq(deposit, 0);
        assertEq(bucketCollateral, 0.110859070422319485680287844 * 1e27);

        (, , , deposit, debt, , , bucketCollateral) = pool.bucketAt(priceMed);
        assertEq(debt, 0 * 1e18);
        assertEq(deposit, 0);
        assertEq(bucketCollateral, 0.124955885007559370189665834 * 1e27);

        (, , , deposit, debt, , , bucketCollateral) = pool.bucketAt(priceLow);
        assertEq(debt, 1_000 * 1e45);
        assertEq(deposit, 0);
        assertEq(bucketCollateral, 0);

        // check borrower after liquidation
        assertEq(bucketCollateral, 0);
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
        assertEq(collateralDeposited, 0.765832484960910633115967961 * 1e27);
        assertEq(collateralEncumbered, 0);
        assertEq(collateralization, 0);
        assertEq(borrowerInflator, 1 * 1e18);

        // check pool balance
        assertEq(pool.totalQuoteToken(), 0);
        assertEq(pool.totalDebt(), 1_000 * 1e45);
        assertEq(
            pool.totalCollateral(),
            200.765832484960910633115967961 * 1e27
        );
    }

    // @notice: with 1 lender and 2 borrowers -- quote is deposited
    // @notice: borrows occur accross a time skip then successful liquidation is called.
    // @notice: borrower balances are checked
    function testLiquidateScenario1TimeWarp() public {
        // lender deposit in 3 buckets, price spaced
        uint256 priceHighest = 10_016.501589292607751220 * 1e18;
        uint256 priceHigh = 9_020.461710444470171420 * 1e18;
        uint256 priceMed = 8_002.824356287850613262 * 1e18;
        uint256 priceLow = 100.332368143282009890 * 1e18;

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

        // check pool balance
        assertEq(pool.totalQuoteToken(), 13_000 * 1e45);
        assertEq(pool.totalDebt(), 0);
        assertEq(pool.totalCollateral(), 202 * 1e27);
        assertEq(pool.hdp(), priceHighest);

        // first borrower takes a loan of 12_000 DAI, pushing lup to 8_000
        borrower.borrow(pool, 12_000 * 1e18, 8_000 * 1e18);

        // time warp
        skip(100000000);

        // 2nd borrower takes a loan of 1_000 DAI, pushing lup to 100
        borrower2.borrow(pool, 1_000 * 1e18, 100 * 1e18);

        // check borrower 1 is undercollateralized and collateral not enough to cover debt
        (
            uint256 borrowerDebt,
            uint256 borrowerPendingDebt,
            uint256 collateralDeposited,
            uint256 collateralEncumbered,
            uint256 collateralization,
            uint256 borrowerInflator,

        ) = pool.getBorrowerInfo(address(borrower));
        assertEq(borrowerDebt, 14_061.711519357563040000 * 1e45);
        assertEq(borrowerPendingDebt, 14_061.711519357563040000 * 1e45);
        assertEq(collateralDeposited, 2 * 1e27);
        assertEq(collateralEncumbered, 140.151296930183124225206913837 * 1e27);
        assertEq(collateralization, 0.014270292489667842588863823 * 1e27);
        assertEq(borrowerInflator, 1 * 1e27);

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
            ,
            uint256 bucketCollateral
        ) = pool.bucketAt(priceHighest);
        assertEq(debt, 0);
        assertEq(deposit, 0);
        assertEq(bucketCollateral, 1.169878807319745296452349382 * 1e27);

        (, , , deposit, debt, , , bucketCollateral) = pool.bucketAt(priceMed);
        assertEq(debt, 0);
        assertEq(deposit, 0);
        assertEq(bucketCollateral, 0.129905688965233434393369814 * 1e27);

        (, , , deposit, debt, , , bucketCollateral) = pool.bucketAt(priceMed);
        assertEq(debt, 0);
        assertEq(deposit, 0);
        assertEq(bucketCollateral, 0.146424467301859716998466886 * 1e27);

        (, , , deposit, debt, , , bucketCollateral) = pool.bucketAt(priceLow);
        assertEq(debt, 1_000 * 1e45);
        assertEq(deposit, 0);
        assertEq(bucketCollateral, 0);

        // check borrower after liquidation
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
        assertEq(collateralDeposited, 0.553791036413161552155813918 * 1e27);
        assertEq(collateralEncumbered, 0);
        assertEq(collateralization, 0);
        assertEq(borrowerInflator, 1.171809293279796920 * 1e18);

        // check pool balance
        assertEq(pool.totalQuoteToken(), 0);
        assertEq(pool.totalDebt(), 1_000 * 1e45);
        assertEq(
            pool.totalCollateral(),
            200.553791036413161552155813918 * 1e27
        );
    }
}
