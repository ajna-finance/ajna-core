// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.11;

import { ERC20Pool }        from "../ERC20Pool.sol";
import { ERC20PoolFactory } from "../ERC20PoolFactory.sol";

import { Maths } from "../libraries/Maths.sol";

import { IPool } from "../interfaces/IPool.sol";

import { DSTestPlus }                             from "./utils/DSTestPlus.sol";
import { CollateralToken, QuoteToken }            from "./utils/Tokens.sol";
import { UserWithCollateral, UserWithQuoteToken } from "./utils/Users.sol";

contract ERC20PoolLiquidateTest is DSTestPlus {

    address            internal _poolAddress;
    CollateralToken    internal _collateral;
    ERC20Pool          internal _pool;
    QuoteToken         internal _quote;
    UserWithCollateral internal _borrower;
    UserWithCollateral internal _borrower2;
    UserWithQuoteToken internal _lender;

    function setUp() external {
        _collateral  = new CollateralToken();
        _quote       = new QuoteToken();
        _poolAddress = new ERC20PoolFactory().deployPool(address(_collateral), address(_quote));
        _pool        = ERC20Pool(_poolAddress);

        _borrower   = new UserWithCollateral();
        _borrower2  = new UserWithCollateral();
        _lender     = new UserWithQuoteToken();

        _collateral.mint(address(_borrower), 2 * 1e18);
        _collateral.mint(address(_borrower2), 200 * 1e18);
        _quote.mint(address(_lender), 200_000 * 1e18);
        _borrower.approveToken(_collateral, address(_pool), 2 * 1e18);
        _borrower2.approveToken(_collateral, address(_pool), 200 * 1e18);
        _lender.approveToken(_quote, address(_pool), 200_000 * 1e18);
    }

    /**
     *  @notice With 1 lender and 2 borrowers -- quote is deposited and borrow occurs.
     *          Time passes then successful liquidation is called.
     *          Lender reverts:
     *              attempts to call liquidate on borrower that is collateralized.
     */
    function testLiquidateTwoBorrowers() external {
        // lender deposit in 3 buckets, price spaced
        uint256 priceHigh = _p10016;
        uint256 priceMed  = _p9020;
        uint256 priceLow  = _p100;

        _lender.addQuoteToken(_pool, address(_lender), 10_000 * 1e18, priceHigh);
        _lender.addQuoteToken(_pool, address(_lender), 1_000 * 1e18, priceMed);
        _lender.addQuoteToken(_pool, address(_lender), 10_000 * 1e18, priceLow);

        // should revert when no debt
        vm.expectRevert("P:L:NO_DEBT");
        _lender.liquidate(_pool, address(_borrower));

        // borrowers deposit collateral
        _borrower.addCollateral(_pool, 2 * 1e18);
        _borrower2.addCollateral(_pool, 200 * 1e18);

        assertEq(_pool.hpb(), priceHigh);
        assertEq(_pool.lup(), 0);

        assertEq(_pool.totalDebt(),       0);
        assertEq(_pool.totalQuoteToken(), 21_000 * 1e18);
        assertEq(_pool.totalCollateral(), 202 * 1e18);
        assertEq(_pool.pdAccumulator(),   110_188_801.284803367782520000 * 1e18);

        // first borrower takes a loan of 11_000 DAI, pushing lup to 9_000
        _borrower.borrow(_pool, 11_000 * 1e18, 9_000 * 1e18);
        (
            uint256 borrowerDebt,
            uint256 borrowerPendingDebt,
            uint256 collateralDeposited,
            uint256 collateralEncumbered,
            uint256 collateralization,
            uint256 borrowerInflator,

        ) = _pool.getBorrowerInfo(address(_borrower));

        // check borrower and pool collateralization after borrowing
        uint256 borrower1CollateralEncumbered = collateralEncumbered;
        assertEq(_pool.getEncumberedCollateral(borrowerDebt), borrower1CollateralEncumbered);
        assertEq(_pool.getBorrowerCollateralization(collateralDeposited, borrowerDebt), collateralization);
        assertEq(_pool.getPoolCollateralization(), 165.648464202946686247 * 1e18);
        assertEq(
            _pool.getBorrowerCollateralization(collateralDeposited, borrowerDebt),
            collateralization
        );
        assertEq(_pool.getPoolActualUtilization(), 0.989989627993477520 * 1e18);

        // 2nd borrower takes a loan of 1_000 DAI, pushing lup to 100
        _borrower2.borrow(_pool, 1_000 * 1e18, 100 * 1e18);
        (
            borrowerDebt,
            borrowerPendingDebt,
            collateralDeposited,
            collateralEncumbered,
            collateralization,
            borrowerInflator,

        ) = _pool.getBorrowerInfo(address(_borrower2));

        // check borrower and pool collateralization after second borrower also borrows
        assertEq(_pool.getEncumberedCollateral(borrowerDebt), collateralEncumbered);
        assertEq(_pool.getBorrowerCollateralization(collateralDeposited, borrowerDebt), collateralization);
        assertEq(_pool.getPoolCollateralization(), 1.688927926417053830 * 1e18);
        assertEq(
            _pool.getBorrowerCollateralization(collateralDeposited, borrowerDebt),
            collateralization
        );
        assertEq(_pool.getPoolActualUtilization(), 0.571428610675035652 * 1e18);

        // should revert when borrower collateralized
        vm.expectRevert("P:L:BORROWER_OK");
        _lender.liquidate(_pool, address(_borrower2));

        assertEq(_pool.hpb(), priceHigh);
        assertEq(_pool.lup(), priceLow);

        assertEq(_pool.totalDebt(),       12_000.001923076923076924 * 1e18);
        assertEq(_pool.totalQuoteToken(), 9_000 * 1e18);
        assertEq(_pool.totalCollateral(), 202 * 1e18);
        assertEq(_pool.pdAccumulator(),   902_991.313289538089010000 * 1e18);

        assertEq(_pool.lastInflatorSnapshotUpdate(), 0);

        // check balances
        assertEq(_quote.balanceOf(address(_pool)), 9_000 * 1e18);

        // check borrower 1 is undercollateralized
        (
            borrowerDebt,
            borrowerPendingDebt,
            collateralDeposited,
            collateralEncumbered,
            collateralization,
            borrowerInflator,
        ) = _pool.getBorrowerInfo(address(_borrower));
        assertEq(borrowerDebt,         11_000.000961538461538462 * 1e18);
        assertEq(borrowerPendingDebt,  11_000.000961538461538462 * 1e18);
        assertEq(collateralDeposited,  2 * 1e18);
        assertEq(collateralEncumbered, 109.635615754924175193081404336 * 1e27);
        assertEq(collateralization,    0.018242247158721977 * 1e18);
        assertEq(borrowerInflator,     1 * 1e27);

        // check 10_016.501589292607751220 bucket balance before liquidate
        (, , , uint256 deposit, uint256 debt, , , uint256 bucketCollateral) = _pool.bucketAt(priceHigh);
        assertEq(debt,             10_000 * 1e18);
        assertEq(deposit,          0);
        assertEq(bucketCollateral, 0);

        // check 9_020.461710444470171420 bucket balance before liquidate
        (, , , deposit, debt, , , bucketCollateral) = _pool.bucketAt(priceMed);
        assertEq(debt,             1_000.000961538461538462 * 1e18);
        assertEq(deposit,          0);
        assertEq(bucketCollateral, 0);

        // check 100.332368143282009890 bucket balance before liquidate
        (, , , deposit, debt, , , bucketCollateral) = _pool.bucketAt(priceLow);
        assertEq(debt,             1_000.000961538461538462 * 1e18);
        assertEq(deposit,          9_000 * 1e18);
        assertEq(bucketCollateral, 0);

        skip(8200);

        // liquidate borrower
        vm.expectEmit(true, false, false, true);
        emit Liquidate(address(_borrower), 11_000.143973642345139318 * 1e18, 1.209062807524305698 * 1e18);
        _lender.liquidate(_pool, address(_borrower));

        assertEq(_pool.hpb(), priceLow);
        assertEq(_pool.lup(), priceLow);

        assertEq(_pool.totalDebt(),       1000.013962650179190302 * 1e18);
        assertEq(_pool.totalQuoteToken(), 9_000 * 1e18);
        assertEq(_pool.totalCollateral(), 200.790937192475694302 * 1e18);
        assertEq(_pool.pdAccumulator(),   902_991.313289538089010000 * 1e18);

        assertEq(_pool.inflatorSnapshot(),           1.000013001099216594901568631 * 1e27);
        assertEq(_pool.lastInflatorSnapshotUpdate(), 8200);

        assertEq(_pool.getPoolCollateralization(), 20.145548944977500763 * 1e18);
        assertEq(_pool.getPoolActualUtilization(), 0.100001256636761529 * 1e18);

        // check balances
        assertEq(_quote.balanceOf(address(_pool)), 9_000 * 1e18);

        // check borrower 1 balances and that interest accumulated
        (
            borrowerDebt,
            borrowerPendingDebt,
            collateralDeposited,
            collateralEncumbered,
            collateralization,
            borrowerInflator,
        ) = _pool.getBorrowerInfo(address(_borrower));
        assertEq(borrowerDebt,         0);
        assertEq(borrowerPendingDebt,  0);
        assertEq(collateralDeposited,  0.790937192475694302 * 1e18);
        assertEq(collateralEncumbered, 0);
        assertEq(collateralization,    Maths.ONE_WAD);
        assertEq(borrowerInflator,     1.000013001099216594901568631 * 1e27);
        assertEq(_pool.getEncumberedCollateral(borrowerDebt), collateralEncumbered);
        assertEq(_pool.getBorrowerCollateralization(collateralDeposited, borrowerDebt), collateralization);
        assertEq(
            _pool.getBorrowerCollateralization(collateralDeposited, borrowerDebt),
            collateralization
        );

        // check 10_016.501589292607751220 bucket balance after liquidate
        (, , , deposit, debt, , , bucketCollateral) = _pool.bucketAt(priceHigh);
        assertEq(debt,             0);
        assertEq(deposit,          0);
        assertEq(bucketCollateral, 1.098202189215566715 * 1e18);

        // check 9_020.461710444470171420 bucket balance after liquidate
        (, , , deposit, debt, , , bucketCollateral) = _pool.bucketAt(priceMed);
        assertEq(debt,             0);
        assertEq(deposit,          0);
        assertEq(bucketCollateral, 0.110860618308738983 * 1e18);

        // check 100.332368143282009890 bucket balance after purchase bid
        (, , , deposit, debt, , , bucketCollateral) = _pool.bucketAt(priceLow);
        assertEq(debt,             1_000.013962650179190301 * 1e18);
        assertEq(deposit,          9_000 * 1e18);
        assertEq(bucketCollateral, 0);
    }

    /**
     *  @notice With 1 lender and 2 borrowers -- quote is deposited,
     *          borrow occurs then successful liquidation is called.
     *          Borrower balances are checked.
     */
    function testLiquidateScenario1NoTimeWarp() external {
        uint256 priceHighest = _p10016;
        uint256 priceHigh    = _p9020;
        uint256 priceMed     = _p8002;
        uint256 priceLow     = _p100;

        // lender deposit in 4 buckets, price spaced
        _lender.addQuoteToken(_pool, address(_lender), 10_000 * 1e18, priceHighest);
        _lender.addQuoteToken(_pool, address(_lender), 1_000 * 1e18, priceHigh);
        _lender.addQuoteToken(_pool, address(_lender), 1_000 * 1e18, priceMed);
        _lender.addQuoteToken(_pool, address(_lender), 1_000 * 1e18, priceLow);

        // borrowers deposit collateral
        _borrower.addCollateral(_pool, 2 * 1e18);
        _borrower2.addCollateral(_pool, 200 * 1e18);

        assertEq(_pool.hpb(), priceHighest);
        assertEq(_pool.lup(), 0);

        assertEq(_pool.totalDebt(),       0);
        assertEq(_pool.totalQuoteToken(), 13_000 * 1e18);
        assertEq(_pool.totalCollateral(), 202 * 1e18);
        assertEq(_pool.pdAccumulator(),   117_288_634.327801680306772000 * 1e18);

        assertEq(_pool.getPoolCollateralization(), Maths.ONE_WAD);
        assertEq(_pool.getPoolActualUtilization(), 0);

        // first borrower takes a loan of 12_000 DAI, pushing lup to 8_002.824356287850613262
        _borrower.borrow(_pool, 12_000 * 1e18, 8_000 * 1e18);

        // 2nd borrower takes a loan of 1_000 DAI, pushing lup to 100.332368143282009890
        _borrower2.borrow(_pool, 1_000 * 1e18, 100 * 1e18);

        assertEq(_pool.hpb(), priceHighest);
        assertEq(_pool.lup(), _p100);

        assertEq(_pool.totalDebt(),       13_000.001923076923076924 * 1e18);
        assertEq(_pool.totalQuoteToken(), 0);
        assertEq(_pool.totalCollateral(), 202 * 1e18);
        assertEq(_pool.pdAccumulator(),   0);

        // check borrower 1 is undercollateralized and collateral not enough to cover debt
        (
            uint256 borrowerDebt,
            uint256 borrowerPendingDebt,
            uint256 collateralDeposited,
            uint256 collateralEncumbered,
            uint256 collateralization,
            uint256 borrowerInflator,

        ) = _pool.getBorrowerInfo(address(_borrower));
        assertEq(borrowerDebt,         12_000.000961538461538462 * 1e18);
        assertEq(borrowerPendingDebt,  12_000.000961538461538462 * 1e18);
        assertEq(collateralDeposited,  2 * 1e18);
        assertEq(collateralEncumbered, 119.602489043232554029831495215 * 1e27);
        assertEq(collateralization,    0.016722060017305013 * 1e18);
        assertEq(borrowerInflator,     1 * 1e27);

        // check borrower and pool collateralization after borrowing
        assertEq(_pool.getEncumberedCollateral(borrowerDebt), collateralEncumbered);
        assertEq(_pool.getBorrowerCollateralization(collateralDeposited, borrowerDebt), collateralization);
        assertEq(_pool.getPoolCollateralization(), 1.559010412834309095 * 1e18);
        assertEq(
            _pool.getBorrowerCollateralization(collateralDeposited, borrowerDebt),
            collateralization
        );
        // check pool is fully utilized
        assertEq(_pool.getPoolActualUtilization(), 1 * 1e18);

        // liquidate borrower
        _lender.liquidate(_pool, address(_borrower));

        assertEq(_pool.hpb(), _p100);
        assertEq(_pool.lup(), _p100);

        assertEq(_pool.totalDebt(),       1_000.000961538461538462 * 1e18);
        assertEq(_pool.totalQuoteToken(), 0);
        assertEq(_pool.totalCollateral(), 200.455302579876161169 * 1e18);
        assertEq(_pool.pdAccumulator(),   0);

        assertEq(_pool.getPoolCollateralization(), 20.112135876124934462 * 1e18);
        assertEq(_pool.getPoolActualUtilization(), 1 * 1e18);

        // check buckets debt and collateral after liquidation
        (, , , uint256 deposit, uint256 debt, , , uint256 bucketCollateral) = _pool.bucketAt(priceHighest);
        assertEq(debt,             0);
        assertEq(deposit,          0);
        assertEq(bucketCollateral, 1.198023167526491037 * 1e18);

        (, , , deposit, debt, , , bucketCollateral) = _pool.bucketAt(priceHigh);
        assertEq(debt,             0);
        assertEq(deposit,          0);
        assertEq(bucketCollateral, 0.221718247439898993 * 1e18);

        (, , , deposit, debt, , , bucketCollateral) = _pool.bucketAt(priceMed);
        assertEq(debt,             0);
        assertEq(deposit,          0);
        assertEq(bucketCollateral, 0.124956005157448801 * 1e18);

        (, , , deposit, debt, , , bucketCollateral) = _pool.bucketAt(priceLow);
        assertEq(debt,             1_000.000961538461538462 * 1e18);
        assertEq(deposit,          0);
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

        ) = _pool.getBorrowerInfo(address(_borrower));
        assertEq(borrowerDebt,         0);
        assertEq(borrowerPendingDebt,  0);
        assertEq(collateralDeposited,  0.455302579876161169 * 1e18);
        assertEq(collateralEncumbered, 0);
        assertEq(collateralization,    Maths.ONE_WAD);
        assertEq(borrowerInflator,     1 * 1e27);

        // check borrower collateralization after liquidation
        assertEq(_pool.getEncumberedCollateral(borrowerDebt), collateralEncumbered);
        assertEq(_pool.getBorrowerCollateralization(collateralDeposited, borrowerDebt), collateralization);
        assertEq(
            _pool.getBorrowerCollateralization(collateralDeposited, borrowerDebt),
            collateralization
        );
    }

    /**
     *  @notice With 1 lender and 2 borrowers -- quote is deposited,
     *          borrows occur accross a time skip then successful liquidation is called.
     *          Borrower balances are checked.
     */
    function testLiquidateScenario1TimeWarp() external {
        uint256 priceHighest = _p10016;
        uint256 priceHigh    = _p9020;
        uint256 priceMed     = _p8002;
        uint256 priceLow     = _p100;

        // lender deposit in 4 buckets, price spaced
        _lender.addQuoteToken(_pool, address(_lender), 10_000 * 1e18, priceHighest);
        _lender.addQuoteToken(_pool, address(_lender), 1_000 * 1e18, priceHigh);
        _lender.addQuoteToken(_pool, address(_lender), 1_000 * 1e18, priceMed);
        _lender.addQuoteToken(_pool, address(_lender), 1_000 * 1e18, priceLow);

        // borrowers deposit collateral
        _borrower.addCollateral(_pool, 2 * 1e18);
        _borrower2.addCollateral(_pool, 200 * 1e18);

        assertEq(_pool.hpb(), priceHighest);
        assertEq(_pool.lup(), 0);

        assertEq(_pool.totalDebt(),       0);
        assertEq(_pool.totalQuoteToken(), 13_000 * 1e18);
        assertEq(_pool.totalCollateral(), 202 * 1e18);
        assertEq(_pool.pdAccumulator(),   117_288_634.327801680306772000 * 1e18);

        assertEq(_pool.getPoolCollateralization(), Maths.ONE_WAD);
        assertEq(_pool.getPoolActualUtilization(), 0);

        // first borrower takes a loan of 12_000 DAI, pushing lup to 8_000
        _borrower.borrow(_pool, 12_000 * 1e18, 8_000 * 1e18);
        // time warp
        skip(100000000);

        // 2nd borrower takes a loan of 1_000 DAI, pushing lup to 100
        _borrower2.borrow(_pool, 1_000 * 1e18, 100 * 1e18);

        assertEq(_pool.hpb(), priceHighest);
        assertEq(_pool.lup(), priceLow);

        assertEq(_pool.totalDebt(),       15_061.713620615184107197 * 1e18);
        assertEq(_pool.totalQuoteToken(), 0);
        assertEq(_pool.totalCollateral(), 202 * 1e18);
        assertEq(_pool.pdAccumulator(),   0);

        assertEq(_pool.getPoolCollateralization(), 1.345606408105054007 * 1e18);
        assertEq(_pool.getPoolActualUtilization(), 1 * 1e18);

        // check borrower 1 is undercollateralized and collateral not enough to cover debt
        (
            uint256 borrowerDebt,
            uint256 borrowerPendingDebt,
            uint256 collateralDeposited,
            uint256 collateralEncumbered,
            uint256 collateralization,
            uint256 borrowerInflator,

        ) = _pool.getBorrowerInfo(address(_borrower));
        assertEq(borrowerDebt,         12_000.000961538461538462 * 1e18);
        assertEq(borrowerPendingDebt,  14_061.712659076722568735 * 1e18);
        assertEq(collateralDeposited,  2 * 1e18);
        assertEq(collateralEncumbered, 140.151308289619571505431722405 * 1e27);
        assertEq(collateralization,    0.014270291333043030 * 1e18);
        assertEq(borrowerInflator,     1 * 1e27);

        // check pool and borrowers collateralization after both borrows
        assertLt(borrowerDebt, borrowerPendingDebt);
        assertEq(_pool.getEncumberedCollateral(borrowerPendingDebt), collateralEncumbered);
        assertEq(_pool.getBorrowerCollateralization(collateralDeposited, borrowerPendingDebt), collateralization);
        assertEq(
            _pool.getBorrowerCollateralization(collateralDeposited, borrowerPendingDebt),
            collateralization
        );

        // liquidate borrower
        _lender.liquidate(_pool, address(_borrower));

        assertEq(_pool.hpb(), priceLow);
        assertEq(_pool.lup(), priceLow);

        assertEq(_pool.totalDebt(),       1_000.000961538461538462 * 1e18);
        assertEq(_pool.totalQuoteToken(), 0);
        assertEq(_pool.totalCollateral(), 200.189909206122781517 * 1e18);
        assertEq(_pool.pdAccumulator(),   0);

        assertEq(_pool.getPoolCollateralization(), 20.085508356050107425 * 1e18);
        assertEq(_pool.getPoolActualUtilization(), 1 * 1e18);

        // check buckets debt and collateral after liquidation
        (, , , uint256 deposit, uint256 debt, , , uint256 bucketCollateral) = _pool.bucketAt(priceHighest);
        assertEq(debt,             0);
        assertEq(deposit,          0);
        assertEq(bucketCollateral, 1.403854682567848371 * 1e18);

        (, , , deposit, debt, , , bucketCollateral) = _pool.bucketAt(priceHigh);
        assertEq(debt,             0);
        assertEq(deposit,          0);
        assertEq(bucketCollateral, 0.259811503079598320 * 1e18);

        (, , , deposit, debt, , , bucketCollateral) = _pool.bucketAt(priceMed);
        assertEq(debt,             0);
        assertEq(deposit,          0);
        assertEq(bucketCollateral, 0.146424608229771792 * 1e18);

        (, , , deposit, debt, , , bucketCollateral) = _pool.bucketAt(priceLow);
        assertEq(debt,             1_000.000961538461538462 * 1e18);
        assertEq(deposit,          0);
        assertEq(bucketCollateral, 0);

        // check borrower after liquidation
        (
            borrowerDebt,
            borrowerPendingDebt,
            collateralDeposited,
            collateralEncumbered,
            collateralization,
            borrowerInflator,

        ) = _pool.getBorrowerInfo(address(_borrower));
        assertEq(borrowerDebt,         0);
        assertEq(borrowerPendingDebt,  0);
        assertEq(collateralDeposited,  0.189909206122781517 * 1e18);
        assertEq(collateralEncumbered, 0);
        assertEq(collateralization,    Maths.ONE_WAD);
        assertEq(borrowerInflator,     1.171809294361418037665607534 * 1e27);
    }

}
