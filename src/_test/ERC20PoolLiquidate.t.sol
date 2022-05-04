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

    CollateralToken    internal _collateral;
    ERC20Pool          internal _pool;
    QuoteToken         internal _quote;
    UserWithCollateral internal _borrower;
    UserWithCollateral internal _borrower2;
    UserWithQuoteToken internal _lender;

    function setUp() external {
        _collateral = new CollateralToken();
        _quote      = new QuoteToken();
        _pool       = new ERC20PoolFactory().deployPool(address(_collateral), address(_quote));
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

    // @notice: with 1 lender and 2 borrowers -- quote is deposited
    // @notice: borrow occurs, time passes then successful liquidation
    // @notice: is called
    // @notice: lender reverts:
    // @notice:    attempts to call liquidate on borrower that is collateralized
    function testLiquidate() external {
        // lender deposit in 3 buckets, price spaced
        uint256 priceHigh = _p10016;
        uint256 priceMed  = _p9020;
        uint256 priceLow  = _p100;

        _lender.addQuoteToken(_pool, address(_lender), 10_000 * 1e18, priceHigh);
        _lender.addQuoteToken(_pool, address(_lender), 1_000 * 1e18, priceMed);
        _lender.addQuoteToken(_pool, address(_lender), 10_000 * 1e18, priceLow);

        // should revert when no debt
        vm.expectRevert(IPool.NoDebtToLiquidate.selector);
        _lender.liquidate(_pool, address(_borrower));

        // borrowers deposit collateral
        _borrower.addCollateral(_pool, 2 * 1e18);
        _borrower2.addCollateral(_pool, 200 * 1e18);

        // check pool balance
        assertEq(_pool.totalQuoteToken(), 21_000 * 1e45);
        assertEq(_pool.totalDebt(),       0);
        assertEq(_pool.totalCollateral(), 202 * 1e27);
        assertEq(_pool.hpb(),             priceHigh);
        assertEq(_pool.getPoolCollateralization(), Maths.ONE_RAY);
        assertEq(_pool.getPoolActualUtilization(), 0);

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
        assertEq(_pool.getPoolCollateralization(), Maths.rdiv(_pool.totalCollateral(), borrower1CollateralEncumbered));
        assertEq(
            _pool.getBorrowerCollateralization(collateralDeposited, borrowerDebt),
            collateralization
        );
        assertEq(_pool.getPoolActualUtilization(), 0.523809523809523809523809524 * 1e27);

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
        assertEq(_pool.getPoolCollateralization(), Maths.rdiv(_pool.totalCollateral(), _pool.getEncumberedCollateral(_pool.totalDebt())));
        assertEq(
            _pool.getBorrowerCollateralization(collateralDeposited, borrowerDebt),
            collateralization
        );
        assertEq(_pool.getPoolActualUtilization(), 0.571428571428571428571428571 * 1e27);

        // should revert when borrower collateralized
        vm.expectRevert(
            abi.encodeWithSelector(
                IPool.BorrowerIsCollateralized.selector,
                20.066473628656401978000000001 * 1e27
            )
        );
        _lender.liquidate(_pool, address(_borrower2));

        // check borrower 1 is undercollateralized
        (
            borrowerDebt,
            borrowerPendingDebt,
            collateralDeposited,
            collateralEncumbered,
            collateralization,
            borrowerInflator,

        ) = _pool.getBorrowerInfo(address(_borrower));
        assertEq(borrowerDebt,         11_000 * 1e45);
        assertEq(borrowerPendingDebt,  11_000 * 1e45);
        assertEq(collateralDeposited,  2 * 1e27);
        assertEq(collateralEncumbered, 109.635606171392167204250999673 * 1e27);
        assertEq(collateralization,    0.018242248753324001798181818 * 1e27);
        assertEq(borrowerInflator,     1 * 1e27);

        // check pool balance
        assertEq(_pool.totalQuoteToken(),          9_000 * 1e45);
        assertEq(_pool.totalDebt(),                12_000 * 1e45);
        assertEq(_pool.totalCollateral(),          202 * 1e27);
        assertEq(_pool.lup(),                      priceLow);
        assertEq(_quote.balanceOf(address(_pool)), 9_000 * 1e18);
        assertEq(_pool.lastInflatorSnapshotUpdate(), 0);

        // check 10_016.501589292607751220 bucket balance before liquidate
        (, , , uint256 deposit, uint256 debt, , , uint256 bucketCollateral) = _pool.bucketAt(
            priceHigh
        );
        assertEq(debt,             10_000 * 1e45);
        assertEq(deposit,          0);
        assertEq(bucketCollateral, 0);

        // check 9_020.461710444470171420 bucket balance before liquidate
        (, , , deposit, debt, , , bucketCollateral) = _pool.bucketAt(priceMed);
        assertEq(debt,             1_000 * 1e45);
        assertEq(deposit,          0);
        assertEq(bucketCollateral, 0);

        // check 100.332368143282009890 bucket balance before liquidate
        (, , , deposit, debt, , , bucketCollateral) = _pool.bucketAt(priceLow);
        assertEq(debt,             1_000 * 1e45);
        assertEq(deposit,          9_000 * 1e45);
        assertEq(bucketCollateral, 0);

        skip(8200);

        // liquidate borrower
        vm.expectEmit(true, false, false, true);
        emit Liquidate(
            address(_borrower),
            11_000.14301209138254391725494100 * 1e45,
            1.209062604930973350756362484 * 1e27
        );
        _lender.liquidate(_pool, address(_borrower));

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
        assertEq(collateralDeposited,  0.790937395069026649243637516 * 1e27);
        assertEq(collateralEncumbered, 0);
        assertEq(collateralization,    Maths.ONE_RAY);
        assertEq(borrowerInflator,     1.000013001099216594901568631 * 1e27);
        assertEq(_pool.getEncumberedCollateral(borrowerDebt), collateralEncumbered);
        assertEq(_pool.getBorrowerCollateralization(collateralDeposited, borrowerDebt), collateralization);
        assertEq(
            _pool.getBorrowerCollateralization(collateralDeposited, borrowerDebt),
            collateralization
        );

        // check pool balance and that interest accumulated
        assertEq(_pool.totalQuoteToken(),            9_000 * 1e45);
        assertEq(_pool.totalDebt(),                  1000.013001099216594901568631 * 1e45);
        assertEq(_pool.totalCollateral(),            200.790937395069026649243637516 * 1e27);
        assertEq(_pool.inflatorSnapshot(),           1.000013001099216594901568631 * 1e27);
        assertEq(_pool.lastInflatorSnapshotUpdate(), 8200);
        assertEq(_pool.lup(),                        priceLow);
        assertEq(_quote.balanceOf(address(_pool)),   9_000 * 1e18);
        assertEq(_pool.getPoolCollateralization(), Maths.rdiv(_pool.totalCollateral(), _pool.getEncumberedCollateral(_pool.totalDebt())));
        assertEq(_pool.getPoolActualUtilization(), 0.100001170097408238291382519 * 1e27);

        // check 10_016.501589292607751220 bucket balance after liquidate
        (, , , deposit, debt, , , bucketCollateral) = _pool.bucketAt(priceHigh);
        assertEq(debt,             0);
        assertEq(deposit,          0);
        assertEq(bucketCollateral, 1.098202093218880245019185568 * 1e27);

        // check 9_020.461710444470171420 bucket balance after liquidate
        (, , , deposit, debt, , , bucketCollateral) = _pool.bucketAt(priceMed);
        assertEq(debt,             0);
        assertEq(deposit,          0);
        assertEq(bucketCollateral, 0.110860511712093105737176916 * 1e27);

        // check 100.332368143282009890 bucket balance after purchase bid
        (, , , deposit, debt, , , bucketCollateral) = _pool.bucketAt(priceLow);
        assertEq(debt,             1_000 * 1e45);
        assertEq(deposit,          9_000 * 1e45);
        assertEq(bucketCollateral, 0);
    }

    // @notice: with 1 lender and 2 borrowers --  quote is deposited
    // @notice: borrow occurs then successful liquidation is called.
    // @notice: borrower balances are checked
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

        // check pool balance
        assertEq(_pool.totalQuoteToken(),           13_000 * 1e45);
        assertEq(_pool.totalDebt(),                 0);
        assertEq(_pool.totalCollateral(),           202 * 1e27);
        assertEq(_pool.hpb(),                       priceHighest);
        assertEq(_pool.getPoolCollateralization(),  Maths.ONE_RAY);
        assertEq(_pool.getPoolActualUtilization(),  0);

        // first borrower takes a loan of 12_000 DAI, pushing lup to 8_002.824356287850613262
        _borrower.borrow(_pool, 12_000 * 1e18, 8_000 * 1e18);

        // 2nd borrower takes a loan of 1_000 DAI, pushing lup to 100.332368143282009890
        _borrower2.borrow(_pool, 1_000 * 1e18, 100 * 1e18);

        // check borrower 1 is undercollateralized and collateral not enough to cover debt
        (
            uint256 borrowerDebt,
            uint256 borrowerPendingDebt,
            uint256 collateralDeposited,
            uint256 collateralEncumbered,
            uint256 collateralization,
            uint256 borrowerInflator,

        ) = _pool.getBorrowerInfo(address(_borrower));
        assertEq(borrowerDebt,         12_000 * 1e45);
        assertEq(borrowerPendingDebt,  12_000 * 1e45);
        assertEq(collateralDeposited,  2 * 1e27);
        assertEq(collateralEncumbered, 119.602479459700546041001090553 * 1e27);
        assertEq(collateralization,    0.016722061357213668315000000 * 1e27);
        assertEq(borrowerInflator,     1 * 1e27);

        // check borrower and pool collateralization after borrowing
        assertEq(_pool.getEncumberedCollateral(borrowerDebt), collateralEncumbered);
        assertEq(_pool.getBorrowerCollateralization(collateralDeposited, borrowerDebt), collateralization);
        assertEq(_pool.getPoolCollateralization(), Maths.rdiv(_pool.totalCollateral(), _pool.getEncumberedCollateral(_pool.totalDebt())));
        assertEq(
            _pool.getBorrowerCollateralization(collateralDeposited, borrowerDebt),
            collateralization
        );
        // check pool is fully utilized
        assertEq(_pool.getPoolActualUtilization(), 1.000000000000000000000000000 * 1e27);

        // liquidate borrower
        _lender.liquidate(_pool, address(_borrower));

        // check buckets debt and collateral after liquidation
        (, , , uint256 deposit, uint256 debt, , , uint256 bucketCollateral) = _pool.bucketAt(
            priceHighest
        );
        assertEq(debt,             0);
        assertEq(deposit,          0);
        assertEq(bucketCollateral, 1.198023071531052613216894034 * 1e27);

        (, , , deposit, debt, , , bucketCollateral) = _pool.bucketAt(priceHigh);
        assertEq(debt,             0);
        assertEq(deposit,          0);
        assertEq(bucketCollateral, 0.221718140844638971360575690 * 1e27);

        (, , , deposit, debt, , , bucketCollateral) = _pool.bucketAt(priceMed);
        assertEq(debt,             0);
        assertEq(deposit,          0);
        assertEq(bucketCollateral, 0.124955885007559370189665835 * 1e27);

        (, , , deposit, debt, , , bucketCollateral) = _pool.bucketAt(priceLow);
        assertEq(debt,             1_000 * 1e45);
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
        assertEq(collateralDeposited,  0.455302902616749045232864441 * 1e27);
        assertEq(collateralEncumbered, 0);
        assertEq(collateralization,    Maths.ONE_RAY);
        assertEq(borrowerInflator,     1 * 1e27);

        // check borrower collateralization after liquidation
        assertEq(_pool.getEncumberedCollateral(borrowerDebt), collateralEncumbered);
        assertEq(_pool.getBorrowerCollateralization(collateralDeposited, borrowerDebt), collateralization);
        assertEq(
            _pool.getBorrowerCollateralization(collateralDeposited, borrowerDebt),
            collateralization
        );

        // check pool balance
        assertEq(_pool.totalQuoteToken(),           0);
        assertEq(_pool.totalDebt(),                 1_000 * 1e45);
        assertEq(_pool.totalCollateral(),           200.455302902616749045232864441 * 1e27);
        assertEq(_pool.getPoolCollateralization(),  Maths.rdiv(_pool.totalCollateral(), _pool.getEncumberedCollateral(_pool.totalDebt())));
        assertEq(_pool.getPoolCollateralization(),  20.112155247098450521165631145 * 1e27);
        assertEq(_pool.getPoolActualUtilization(),  1.000000000000000000000000000 * 1e27);
    }

    // @notice: with 1 lender and 2 borrowers -- quote is deposited
    // @notice: borrows occur accross a time skip then successful liquidation is called.
    // @notice: borrower balances are checked
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

        // check pool balance
        assertEq(_pool.totalQuoteToken(),           13_000 * 1e45);
        assertEq(_pool.totalDebt(),                 0);
        assertEq(_pool.totalCollateral(),           202 * 1e27);
        assertEq(_pool.hpb(),                       priceHighest);
        assertEq(_pool.getPoolCollateralization(),  Maths.ONE_RAY);
        assertEq(_pool.getPoolActualUtilization(),  0);

        // first borrower takes a loan of 12_000 DAI, pushing lup to 8_000
        _borrower.borrow(_pool, 12_000 * 1e18, 8_000 * 1e18);

        // time warp
        skip(100000000);

        // 2nd borrower takes a loan of 1_000 DAI, pushing lup to 100
        _borrower2.borrow(_pool, 1_000 * 1e18, 100 * 1e18);

        // check borrower 1 is undercollateralized and collateral not enough to cover debt
        (
            uint256 borrowerDebt,
            uint256 borrowerPendingDebt,
            uint256 collateralDeposited,
            uint256 collateralEncumbered,
            uint256 collateralization,
            uint256 borrowerInflator,

        ) = _pool.getBorrowerInfo(address(_borrower));
        assertEq(borrowerDebt,         12_000 * 1e45);
        assertEq(borrowerPendingDebt,  14_061.7115323370164519872904080 * 1e45);
        assertEq(collateralDeposited,  2 * 1e27);
        assertEq(collateralEncumbered, 140.151297059547691733986086345 * 1e27);
        assertEq(collateralization,    0.014270292476495861630562031 * 1e27);
        assertEq(borrowerInflator,     1 * 1e27);

        // TODO: fix these asserts -> pending debt is not 0
        // check pool and borrowers collateralization after both borrows
        assertEq(_pool.getEncumberedCollateral(borrowerPendingDebt), collateralEncumbered);
        assertEq(_pool.getBorrowerCollateralization(collateralDeposited, borrowerPendingDebt), collateralization);
        assertEq(
            _pool.getBorrowerCollateralization(collateralDeposited, borrowerPendingDebt),
            collateralization
        );

        assertEq(_pool.getPoolCollateralization(), Maths.rdiv(_pool.totalCollateral(), _pool.getEncumberedCollateral(_pool.totalDebt())));
        // assertEq(_pool.getPoolCollateralization(), 1);
        assertEq(_pool.getPoolActualUtilization(), 1.000000000000000000000000000 * 1e27);

        // liquidate borrower
        _lender.liquidate(_pool, address(_borrower));

        // check buckets debt and collateral after liquidation
        (, , , uint256 deposit, uint256 debt, , , uint256 bucketCollateral) = _pool.bucketAt(
            priceHighest
        );
        assertEq(debt,             0);
        assertEq(deposit,          0);
        assertEq(bucketCollateral, 1.403854570079501409361420469 * 1e27);

        (, , , deposit, debt, , , bucketCollateral) = _pool.bucketAt(priceHigh);
        assertEq(debt,             0);
        assertEq(deposit,          0);
        assertEq(bucketCollateral, 0.259811378170281892093858622 * 1e27);

        (, , , deposit, debt, , , bucketCollateral) = _pool.bucketAt(priceMed);
        assertEq(debt,             0);
        assertEq(deposit,          0);
        assertEq(bucketCollateral, 0.146424467437014640999238384 * 1e27);

        (, , , deposit, debt, , , bucketCollateral) = _pool.bucketAt(100.332368143282009890 * 1e18);
        assertEq(debt,             1_000 * 1e45);
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
        assertEq(collateralDeposited,  0.189909584313202057545482525 * 1e27);
        assertEq(collateralEncumbered, 0);
        assertEq(collateralization,    Maths.ONE_RAY);
        assertEq(borrowerInflator,     1.171809294361418037665607534 * 1e27);

        // check pool balance
        assertEq(_pool.totalQuoteToken(),           0);
        assertEq(_pool.totalDebt(),                 1_000 * 1e45);
        assertEq(_pool.totalCollateral(),           200.189909584313202057545482525 * 1e27);
        assertEq(_pool.getPoolCollateralization(),  Maths.rdiv(_pool.totalCollateral(), _pool.getEncumberedCollateral(_pool.totalDebt())));
        assertEq(_pool.getPoolCollateralization(),  20.085527706983651821033780536 * 1e27);
        assertEq(_pool.getPoolActualUtilization(),  1.000000000000000000000000000 * 1e27);
    }

}
