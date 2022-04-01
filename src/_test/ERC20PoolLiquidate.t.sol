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
        lender.addQuoteToken(
            pool,
            address(lender),
            10_000 * 1e18,
            10_016.501589292607751220 * 1e18
        );
        lender.addQuoteToken(
            pool,
            address(lender),
            1_000 * 1e18,
            9_020.461710444470171420 * 1e18
        );
        lender.addQuoteToken(
            pool,
            address(lender),
            10_000 * 1e18,
            100.332368143282009890 * 1e18
        );

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
        assertEq(pool.hdp(), 10_016.501589292607751220 * 1e18);

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
        assertEq(collateralEncumbered, 109.635606171392167204 * 1e18);
        assertEq(collateralization, 0.018242248753324002 * 1e18);
        assertEq(borrowerInflator, 1 * 1e18);

        // check pool balance
        assertEq(pool.totalQuoteToken(), 9_000 * 1e18);
        assertEq(pool.totalDebt(), 12_000 * 1e18);
        assertEq(pool.totalCollateral(), 202 * 1e18);
        assertEq(pool.lup(), 100.332368143282009890 * 1e18);
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
        ) = pool.bucketAt(10_016.501589292607751220 * 1e18);
        assertEq(debt, 10_000 * 1e18);
        assertEq(deposit, 0);
        assertEq(bucketCollateral, 0);

        // check 9_020.461710444470171420 bucket balance before liquidate
        (, , , deposit, debt, , , bucketCollateral) = pool.bucketAt(
            9_020.461710444470171420 * 1e18
        );
        assertEq(debt, 1_000 * 1e18);
        assertEq(deposit, 0);
        assertEq(bucketCollateral, 0);

        // check 100.332368143282009890 bucket balance before liquidate
        (, , , deposit, debt, , , bucketCollateral) = pool.bucketAt(
            100.332368143282009890 * 1e18
        );
        assertEq(debt, 1_000 * 1e18);
        assertEq(deposit, 9_000 * 1e18);
        assertEq(bucketCollateral, 0);

        skip(8200);

        // liquidate borrower
        vm.expectEmit(true, false, false, true);
        emit Liquidate(
            address(borrower),
            11_000.143012090549955000 * 1e18,
            1.109226051001900282 * 1e18
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
        assertEq(collateralDeposited, 0.890773948998099718 * 1e18);
        assertEq(collateralEncumbered, 0);
        assertEq(collateralization, 0);
        assertEq(borrowerInflator, 1.000013001099140905 * 1e18);

        // check pool balance and that interest accumulated
        assertEq(pool.totalQuoteToken(), 9_000 * 1e18);
        assertEq(pool.totalDebt(), 1000.013001099140905000 * 1e18);
        assertEq(pool.totalCollateral(), 200.890773948998099718 * 1e18);
        assertEq(pool.inflatorSnapshot(), 1.000013001099140905 * 1e18);
        assertEq(pool.lastInflatorSnapshotUpdate(), 8200);
        assertEq(pool.lup(), 100.332368143282009890 * 1e18);
        assertEq(quote.balanceOf(address(pool)), 9_000 * 1e18);

        // check 10_016.501589292607751220 bucket balance after liquidate
        (, , , deposit, debt, , , bucketCollateral) = pool.bucketAt(
            10_016.501589292607751220 * 1e18
        );
        assertEq(debt, 0);
        assertEq(deposit, 0);
        assertEq(bucketCollateral, 0.998365539289815567 * 1e18);

        // check 9_020.461710444470171420 bucket balance after liquidate
        (, , , deposit, debt, , , bucketCollateral) = pool.bucketAt(
            9_020.461710444470171420 * 1e18
        );
        assertEq(debt, 0);
        assertEq(deposit, 0);
        assertEq(bucketCollateral, 0.110860511712084715 * 1e18);

        // check 100.332368143282009890 bucket balance after purchase bid
        (, , , deposit, debt, , , bucketCollateral) = pool.bucketAt(
            100.332368143282009890 * 1e18
        );
        assertEq(debt, 1_000 * 1e18);
        assertEq(deposit, 9_000 * 1e18);
        assertEq(bucketCollateral, 0);
    }

    function testLiquidateScenario1NoTimeWarp() public {
        // lender deposit in 3 buckets, price spaced
        lender.addQuoteToken(
            pool,
            address(lender),
            10_000 * 1e18,
            10_016.501589292607751220 * 1e18
        );
        lender.addQuoteToken(
            pool,
            address(lender),
            1_000 * 1e18,
            9_020.461710444470171420 * 1e18
        );
        lender.addQuoteToken(
            pool,
            address(lender),
            1_000 * 1e18,
            8_002.824356287850613262 * 1e18
        );
        lender.addQuoteToken(
            pool,
            address(lender),
            1_000 * 1e18,
            100.332368143282009890 * 1e18
        );

        // borrowers deposit collateral
        borrower.addCollateral(pool, 2 * 1e18);
        borrower2.addCollateral(pool, 200 * 1e18);

        // check pool balance
        assertEq(pool.totalQuoteToken(), 13_000 * 1e18);
        assertEq(pool.totalDebt(), 0);
        assertEq(pool.totalCollateral(), 202 * 1e18);
        assertEq(pool.hdp(), 10_016.501589292607751220 * 1e18);

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
        assertEq(borrowerDebt, 12_000 * 1e18);
        assertEq(borrowerPendingDebt, 12_000 * 1e18);
        assertEq(collateralDeposited, 2 * 1e18);
        assertEq(collateralEncumbered, 119.602479459700546041 * 1e18);
        assertEq(collateralization, 0.016722061357213668 * 1e18);
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
        ) = pool.bucketAt(10_016.501589292607751220 * 1e18);
        assertEq(debt, 0);
        assertEq(deposit, 0);
        assertEq(bucketCollateral, 0.998352559609210511 * 1e18);

        (, , , deposit, debt, , , bucketCollateral) = pool.bucketAt(
            9_020.461710444470171420 * 1e18
        );
        assertEq(debt, 0);
        assertEq(deposit, 0);
        assertEq(bucketCollateral, 0.110859070422319486 * 1e18);

        (, , , deposit, debt, , , bucketCollateral) = pool.bucketAt(
            8_002.824356287850613262 * 1e18
        );
        assertEq(debt, 0 * 1e18);
        assertEq(deposit, 0);
        assertEq(bucketCollateral, 0.124955885007559370 * 1e18);

        (, , , deposit, debt, , , bucketCollateral) = pool.bucketAt(
            100.332368143282009890 * 1e18
        );
        assertEq(debt, 1_000 * 1e18);
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
        assertEq(collateralDeposited, 0.765832484960910633 * 1e18);
        assertEq(collateralEncumbered, 0);
        assertEq(collateralization, 0);
        assertEq(borrowerInflator, 1 * 1e18);

        // check pool balance
        assertEq(pool.totalQuoteToken(), 0);
        assertEq(pool.totalDebt(), 1_000 * 1e18);
        assertEq(pool.totalCollateral(), 200.765832484960910633 * 1e18);
    }

    function testLiquidateScenario1TimeWarp() public {
        // lender deposit in 3 buckets, price spaced
        lender.addQuoteToken(
            pool,
            address(lender),
            10_000 * 1e18,
            10_016.501589292607751220 * 1e18
        );
        lender.addQuoteToken(
            pool,
            address(lender),
            1_000 * 1e18,
            9_020.461710444470171420 * 1e18
        );
        lender.addQuoteToken(
            pool,
            address(lender),
            1_000 * 1e18,
            8_002.824356287850613262 * 1e18
        );
        lender.addQuoteToken(
            pool,
            address(lender),
            1_000 * 1e18,
            100.332368143282009890 * 1e18
        );

        // borrowers deposit collateral
        borrower.addCollateral(pool, 2 * 1e18);
        borrower2.addCollateral(pool, 200 * 1e18);

        // check pool balance
        assertEq(pool.totalQuoteToken(), 13_000 * 1e18);
        assertEq(pool.totalDebt(), 0);
        assertEq(pool.totalCollateral(), 202 * 1e18);
        assertEq(pool.hdp(), 10_016.501589292607751220 * 1e18);

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
        assertEq(borrowerDebt, 14_061.711519357563040000 * 1e18);
        assertEq(borrowerPendingDebt, 14_061.711519357563040000 * 1e18);
        assertEq(collateralDeposited, 2 * 1e18);
        assertEq(collateralEncumbered, 140.151296930183124225 * 1e18);
        assertEq(collateralization, 0.014270292489667843 * 1e18);
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
        ) = pool.bucketAt(10_016.501589292607751220 * 1e18);
        assertEq(debt, 0);
        assertEq(deposit, 0);
        assertEq(bucketCollateral, 1.169878807319745296 * 1e18);

        (, , , deposit, debt, , , bucketCollateral) = pool.bucketAt(
            9_020.461710444470171420 * 1e18
        );
        assertEq(debt, 0);
        assertEq(deposit, 0);
        assertEq(bucketCollateral, 0.129905688965233434 * 1e18);

        (, , , deposit, debt, , , bucketCollateral) = pool.bucketAt(
            8_002.824356287850613262 * 1e18
        );
        assertEq(debt, 0);
        assertEq(deposit, 0);
        assertEq(bucketCollateral, 0.146424467301859717 * 1e18);

        (, , , deposit, debt, , , bucketCollateral) = pool.bucketAt(
            100.332368143282009890 * 1e18
        );
        assertEq(debt, 1_000 * 1e18);
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
        assertEq(collateralDeposited, 0.553791036413161553 * 1e18);
        assertEq(collateralEncumbered, 0);
        assertEq(collateralization, 0);
        assertEq(borrowerInflator, 1.171809293279796920 * 1e18);

        // check pool balance
        assertEq(pool.totalQuoteToken(), 0);
        assertEq(pool.totalDebt(), 1_000 * 1e18);
        assertEq(pool.totalCollateral(), 200.553791036413161553 * 1e18);
    }
}
