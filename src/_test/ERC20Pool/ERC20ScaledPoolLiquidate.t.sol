// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.14;

import { ERC20Pool }        from "../../erc20/ERC20Pool.sol";
import { ERC20PoolFactory } from "../../erc20/ERC20PoolFactory.sol";

import { Maths } from "../../libraries/Maths.sol";

import { DSTestPlus }                             from "../utils/DSTestPlus.sol";
import { CollateralToken, QuoteToken }            from "../utils/Tokens.sol";

contract ERC20PoolLiquidateTest is DSTestPlus {

    address            internal _poolAddress;
    CollateralToken    internal _collateral;
    ERC20Pool          internal _pool;
    QuoteToken         internal _quote;
    address            internal _borrower;
    address            internal _borrower2;
    address            internal _lender;

    function skip_setUp() external {
        _collateral  = new CollateralToken();
        _quote       = new QuoteToken();
        _poolAddress = new ERC20PoolFactory().deployPool(address(_collateral), address(_quote), 0.05 * 10**18);
        _pool        = ERC20Pool(_poolAddress);

        _borrower   = makeAddr("borrower");
        _borrower2  = makeAddr("borrower2");
        _lender     = makeAddr("lender");

        _collateral.mint(address(_borrower), 2 * 1e18);
        _collateral.mint(address(_borrower2), 200 * 1e18);
        _quote.mint(address(_lender), 200_000 * 1e18);

        vm.startPrank(_borrower);
        _collateral.approve(address(_pool), 2 * 1e18);
        changePrank(_borrower2);
        _collateral.approve(address(_pool), 200 * 1e18);
        changePrank(_lender);
        _quote.approve(address(_pool), 200_000 * 1e18);
    }

    /**
     *  @notice With 1 lender and 2 borrowers -- quote is deposited and borrow occurs.
     *          Time passes then successful liquidation is called.
     *          Lender reverts:
     *              attempts to call liquidate on borrower that is collateralized.
     */
    function skip_testLiquidateTwoBorrowers() external {
        // lender deposit in 3 buckets, price spaced
        uint256 priceHigh = _p10016;
        uint256 priceMed  = _p9020;
        uint256 priceLow  = _p100;

        changePrank(_lender);
        _pool.addQuoteToken(10_000 * 1e18, priceHigh);
        _pool.addQuoteToken(1_000 * 1e18, priceMed);
        _pool.addQuoteToken(10_200 * 1e18, priceLow);

        // should revert when no debt
        vm.expectRevert("P:L:NO_DEBT");
        _pool.liquidate(address(_borrower));

        // borrowers deposit collateral
        changePrank(_borrower);
        _pool.pledgeCollateral(_borrower, 2 * 1e18, address(0), address(0));
        changePrank(_borrower2);
        _pool.pledgeCollateral(_borrower2, 200 * 1e18, address(0), address(0));

        assertEq(_pool.hpb(), priceHigh);
        assertEq(_pool.lup(), 0);

        assertEq(_pool.borrowerDebt(),      0);
        assertEq(_pool.poolSize(),          21_200 * 1e18);
        assertEq(_pool.pledgedCollateral(), 202 * 1e18);
        assertEq(_pool.totalBorrowers(),    0);

        // first borrower takes a loan of 11_000 DAI, pushing lup to 9_000
        _pool.borrow(11_000 * 1e18, 9_000 * 1e18, address(0), address(0));
        (
            uint256 borrowerDebt,
            uint256 borrowerPendingDebt,
            uint256 collateralDeposited,
            uint256 borrowerInflator
        ) = _pool.borrowerInfo(address(_borrower));

        // check borrower and pool collateralization after borrowing
        assertGt(_pool.encumberedCollateral(borrowerDebt, _pool.lup()), 0);                                   // TODO: check value
        assertGt(_pool.borrowerCollateralization(borrowerDebt, collateralDeposited, _pool.lup()), 1 * 1e18);  // TODO: check value
        assertEq(_pool.poolCollateralization(), 165.648464202946686247 * 1e18);
        assertEq(_pool.poolActualUtilization(), 0.989791464378131405 * 1e18);

        // 2nd borrower takes a loan of 1_200 DAI, pushing lup to 100
        changePrank(_borrower2);
        _pool.borrow(1_200 * 1e18, 100 * 1e18, address(0), address(0));
        (
            borrowerDebt,
            borrowerPendingDebt,
            collateralDeposited,
            borrowerInflator
        ) = _pool.borrowerInfo(address(_borrower2));

        // check borrower and pool collateralization after second borrower also borrows
        assertGt(_pool.encumberedCollateral(borrowerDebt, _pool.lup()), 0);                                   // TODO: check value
        assertGt(_pool.borrowerCollateralization(borrowerDebt, collateralDeposited, _pool.lup()), 1 * 1e18);  // TODO: check value
        assertEq(_pool.poolCollateralization(), 1.661240587725371153 * 1e18);
        assertEq(_pool.poolActualUtilization(), 0.575471736622665401 * 1e18);

        // should revert when borrower collateralized
        changePrank(_lender);
        vm.expectRevert("P:L:BORROWER_OK");
        _pool.liquidate(address(_borrower2));

        assertEq(_pool.hpb(), priceHigh);
        assertEq(_pool.lup(), priceLow);

        assertEq(_pool.borrowerDebt(),      12_200.001923076923076924 * 1e18);
        assertEq(_pool.poolSize(),          9_000 * 1e18);
        assertEq(_pool.pledgedCollateral(), 202 * 1e18);
        assertEq(_pool.totalBorrowers(),    2);

        assertEq(_pool.lastInflatorSnapshotUpdate(), 0);

        // check balances
        assertEq(_quote.balanceOf(address(_pool)), 9_000 * 1e18);

        // check borrower 1 is undercollateralized
        (
            borrowerDebt,
            borrowerPendingDebt,
            collateralDeposited,
            borrowerInflator
        ) = _pool.borrowerInfo(address(_borrower));
        assertEq(borrowerDebt,                             11_000.000961538461538462 * 1e18);
        assertEq(borrowerPendingDebt,                      11_000.000961538461538462 * 1e18);
        assertEq(collateralDeposited,                      2 * 1e18);
        assertEq(_pool.encumberedCollateral(borrowerDebt, _pool.lup()), 109.635615754924175193081404336 * 1e27);
        assertEq(_pool.borrowerCollateralization(borrowerDebt, collateralDeposited, _pool.lup()), 0.018242247158721977 * 1e18);
        assertEq(borrowerInflator,                         1 * 1e27);

        // check 10_016.501589292607751220 bucket balance before liquidate
        (uint256 quoteToken, uint256 bucketCollateral, ,) = _pool.bucketAt(priceHigh);
        assertEq(quoteToken,       10_000 * 1e18);
        assertEq(bucketCollateral, 0);

        // check 9_020.461710444470171420 bucket balance before liquidate
        (quoteToken, bucketCollateral, ,) = _pool.bucketAt(priceMed);
        assertEq(quoteToken,       1_000.000961538461538462 * 1e18);
        assertEq(bucketCollateral, 0);

        // check 100.332368143282009890 bucket balance before liquidate
        (quoteToken, bucketCollateral, ,) = _pool.bucketAt(priceLow);
        assertEq(quoteToken,       10_200.000961538461538462 * 1e18);
        assertEq(bucketCollateral, 0);

        skip(8200);

        // liquidate borrower
        vm.expectEmit(true, false, false, true);
        emit Liquidate(address(_borrower), 11_000.143973642345139318 * 1e18, 1.209062807524305698 * 1e18);
        _pool.liquidate(address(_borrower));

        assertEq(_pool.hpb(), priceLow);
        assertEq(_pool.lup(), priceLow);

        assertEq(_pool.borrowerDebt(),      1_200.016562870022509283 * 1e18);
        assertEq(_pool.poolSize(),          9_000 * 1e18);
        assertEq(_pool.pledgedCollateral(), 200.790937192475694302 * 1e18);
        assertEq(_pool.totalBorrowers(),    1);

        assertEq(_pool.inflatorSnapshot(),           1.000013001099216594901568631 * 1e27);
        assertEq(_pool.lastInflatorSnapshotUpdate(), 8200);

        assertEq(_pool.poolCollateralization(), 16.787960144523558692 * 1e18);
        assertEq(_pool.poolActualUtilization(), 0.117648491595426262 * 1e18);

        // check balances
        assertEq(_quote.balanceOf(address(_pool)), 9_000 * 1e18);

        // check borrower 1 balances and that interest accumulated
        (
            borrowerDebt,
            borrowerPendingDebt,
            collateralDeposited,
            borrowerInflator
        ) = _pool.borrowerInfo(address(_borrower));
        assertEq(borrowerDebt,                             0);
        assertEq(borrowerPendingDebt,                      0);
        assertEq(collateralDeposited,                      0.790937192475694302 * 1e18);
        assertEq(_pool.encumberedCollateral(borrowerDebt, _pool.lup()), 0);
        assertEq(_pool.borrowerCollateralization(borrowerDebt, collateralDeposited, _pool.lup()), Maths.WAD);
        assertEq(borrowerInflator,                         1.000013001099216594901568631 * 1e27);

        // check 10_016.501589292607751220 bucket balance after liquidate
        (quoteToken, bucketCollateral, ,) = _pool.bucketAt(priceHigh);
        assertEq(quoteToken,       0);
        assertEq(bucketCollateral, 1.098202189215566715 * 1e18);

        // check 9_020.461710444470171420 bucket balance after liquidate
        (quoteToken, bucketCollateral, ,) = _pool.bucketAt(priceMed);
        assertEq(quoteToken,       0);
        assertEq(bucketCollateral, 0.110860618308738983 * 1e18);

        // check 100.332368143282009890 bucket balance after purchase bid
        (quoteToken, bucketCollateral, ,) = _pool.bucketAt(priceLow);
        assertEq(quoteToken,       10_200.016562870022509281 * 1e18);
        assertEq(bucketCollateral, 0);
    }

    /**
     *  @notice With 1 lender and 2 borrowers -- quote is deposited,
     *          borrow occurs then successful liquidation is called.
     *          Borrower balances are checked.
     */
    function skip_testLiquidateScenario1NoTimeWarp() external {
        uint256 priceHighest = _p10016;
        uint256 priceHigh    = _p9020;
        uint256 priceMed     = _p8002;
        uint256 priceLow     = _p100;

        // lender deposit in 4 buckets, price spaced
        changePrank(_lender);
        _pool.addQuoteToken(10_000 * 1e18, priceHighest);
        _pool.addQuoteToken(1_000 * 1e18, priceHigh);
        _pool.addQuoteToken(1_000 * 1e18, priceMed);
        _pool.addQuoteToken(1_300 * 1e18, priceLow);

        // borrowers deposit collateral
        changePrank(_borrower);
        _pool.pledgeCollateral(_borrower, 2 * 1e18, address(0), address(0));
        changePrank(_borrower2);
        _pool.pledgeCollateral(_borrower2, 200 * 1e18, address(0), address(0));

        assertEq(_pool.hpb(), priceHighest);
        assertEq(_pool.lup(), 0);

        assertEq(_pool.borrowerDebt(),      0);
        assertEq(_pool.poolSize(),          13_300 * 1e18);
        assertEq(_pool.pledgedCollateral(), 202 * 1e18);
        assertEq(_pool.totalBorrowers(),    0);

        assertEq(_pool.poolCollateralization(), Maths.WAD);
        assertEq(_pool.poolActualUtilization(), 0);

        // first borrower takes a loan of 12_000 DAI, pushing lup to 8_002.824356287850613262
        changePrank(_borrower);
        _pool.borrow(12_000 * 1e18, 8_000 * 1e18, address(0), address(0));

        // 2nd borrower takes a loan of 1_300 DAI, pushing lup to 100.332368143282009890
        changePrank(_borrower2);
        _pool.borrow(1_300 * 1e18, 100 * 1e18, address(0), address(0));

        assertEq(_pool.hpb(), priceHighest);
        assertEq(_pool.lup(), _p100);

        assertEq(_pool.borrowerDebt(),      13_300.001923076923076924 * 1e18);
        assertEq(_pool.poolSize(),          0);
        assertEq(_pool.pledgedCollateral(), 202 * 1e18);
        assertEq(_pool.totalBorrowers(),    2);

        // check borrower 1 is undercollateralized and collateral not enough to cover debt
        (
            uint256 borrowerDebt,
            uint256 borrowerPendingDebt,
            uint256 collateralDeposited,
            uint256 borrowerInflator

        ) = _pool.borrowerInfo(address(_borrower));
        assertEq(borrowerDebt,                             12_000.000961538461538462 * 1e18);
        assertEq(borrowerPendingDebt,                      12_000.000961538461538462 * 1e18);
        assertEq(collateralDeposited,                      2 * 1e18);
        assertEq(_pool.encumberedCollateral(borrowerDebt, _pool.lup()), 119.6024890432325540 * 1e18);
        assertEq(_pool.borrowerCollateralization(borrowerDebt, collateralDeposited, _pool.lup()), 0.016722060017305013 * 1e18);
        assertEq(_pool.poolCollateralization(),            1.523844769509192136 * 1e18);
        assertEq(borrowerInflator,                         1 * 1e27);

        // check pool is fully utilized
        assertEq(_pool.poolActualUtilization(), 1 * 1e18);

        // liquidate borrower
        changePrank(_lender);
        _pool.liquidate(address(_borrower));

        assertEq(_pool.hpb(), _p100);
        assertEq(_pool.lup(), _p100);

        assertEq(_pool.borrowerDebt(),      1_300.000961538461538462 * 1e18);
        assertEq(_pool.poolSize(),          0);
        assertEq(_pool.pledgedCollateral(), 200.455302579876161169 * 1e18);
        assertEq(_pool.totalBorrowers(),    1);

        assertEq(_pool.poolCollateralization(), 15.470877183748982409 * 1e18);
        assertEq(_pool.poolActualUtilization(), 1 * 1e18);

        // check buckets debt and collateral after liquidation
        (uint256 quoteToken, uint256 bucketCollateral, ,) = _pool.bucketAt(priceHighest);
        assertEq(quoteToken,       0);
        assertEq(bucketCollateral, 1.198023167526491037 * 1e18);

        (quoteToken, bucketCollateral, ,) = _pool.bucketAt(priceHigh);
        assertEq(quoteToken,          0);
        assertEq(bucketCollateral, 0.221718247439898993 * 1e18);

        (quoteToken, bucketCollateral, ,) = _pool.bucketAt(priceMed);
        assertEq(quoteToken,          0);
        assertEq(bucketCollateral, 0.124956005157448801 * 1e18);

        (quoteToken, bucketCollateral, ,) = _pool.bucketAt(priceLow);
        assertEq(quoteToken,       1_300.000961538461538462 * 1e18);
        assertEq(bucketCollateral, 0);

        // check borrower after liquidation
        assertEq(bucketCollateral, 0);
        (
            borrowerDebt,
            borrowerPendingDebt,
            collateralDeposited,
            borrowerInflator
        ) = _pool.borrowerInfo(address(_borrower));
        assertEq(borrowerDebt,                             0);
        assertEq(borrowerPendingDebt,                      0);
        assertEq(collateralDeposited,                      0.455302579876161169 * 1e18);
        assertEq(_pool.encumberedCollateral(borrowerDebt, _pool.lup()), 0);
        assertEq(_pool.poolCollateralization(),            Maths.WAD);
        assertEq(borrowerInflator,                         1 * 1e27);
    }

    /**
     *  @notice With 1 lender and 2 borrowers -- quote is deposited,
     *          borrows occur accross a time skip then successful liquidation is called.
     *          Borrower balances are checked.
     */
    function skip_testLiquidateScenario1TimeWarp() external {
        uint256 priceHighest = _p10016;
        uint256 priceHigh    = _p9020;
        uint256 priceMed     = _p8002;
        uint256 priceLow     = _p3010;

        // lender deposit in 4 buckets, price spaced
        changePrank(_lender);
        _pool.addQuoteToken(1_000 * 1e18, priceHighest);
        _pool.addQuoteToken(1_000 * 1e18, priceHigh);
        _pool.addQuoteToken(10_000 * 1e18, priceMed);
        _pool.addQuoteToken(12_500 * 1e18, priceLow);

        // borrowers deposit collateral
        changePrank(_borrower);
        _pool.pledgeCollateral(_borrower, 2 * 1e18, address(0), address(0));
        changePrank(_borrower2);
        _pool.pledgeCollateral(_borrower2, 200 * 1e18, address(0), address(0));

        assertEq(_pool.hpb(), priceHighest);
        assertEq(_pool.lup(), 0);

        assertEq(_pool.borrowerDebt(),      0);
        assertEq(_pool.poolSize(),          24_500 * 1e18);
        assertEq(_pool.pledgedCollateral(), 202 * 1e18);
        assertEq(_pool.totalBorrowers(),    0);

        assertEq(_pool.poolCollateralization(), Maths.WAD);
        assertEq(_pool.poolActualUtilization(), 0);

        // first borrower takes a loan of 12_000 DAI, pushing lup to 8_000
        changePrank(_borrower);
        _pool.borrow(12_000 * 1e18, 8_000 * 1e18, address(0), address(0));
        // time warp
        skip(100000000);

        assertEq(_pool.poolMinDebtAmount(), 12.000000961538461538 * 1e18);
        // 2nd borrower takes a loan of 12_100 DAI, pushing lup to 100
        changePrank(_borrower2);
        _pool.borrow(12_100 * 1e18, 100 * 1e18, address(0), address(0));

        assertEq(_pool.hpb(), priceHighest);
        assertEq(_pool.lup(), priceLow);

        assertEq(_pool.borrowerDebt(),      26_161.713620615184107197 * 1e18);
        assertEq(_pool.poolSize(),          400 * 1e18);
        assertEq(_pool.pledgedCollateral(), 202 * 1e18);
        assertEq(_pool.totalBorrowers(),    2);

        assertEq(_pool.poolCollateralization(), 23.247719828441056336 * 1e18);
        assertEq(_pool.poolActualUtilization(), 0.984940730642862199 * 1e18);

        // check borrower 1 is undercollateralized and collateral not enough to cover debt
        (
            uint256 borrowerDebt,
            uint256 borrowerPendingDebt,
            uint256 collateralDeposited,
            uint256 borrowerInflator
        ) = _pool.borrowerInfo(address(_borrower));
        assertEq(borrowerDebt,                             12_000.000961538461538462 * 1e18);
        assertEq(borrowerPendingDebt,                      14_061.712659076722568735 * 1e18);
        assertEq(collateralDeposited,                      2 * 1e18);
        assertEq(_pool.encumberedCollateral(borrowerDebt, _pool.lup()), 4.670281283887423324 * 1e18);
        assertEq(_pool.borrowerCollateralization(borrowerDebt, collateralDeposited, _pool.lup()), 0.428239730848770394 * 1e18);
        assertEq(borrowerInflator,                         1 * 1e27);
        assertLt(borrowerDebt, borrowerPendingDebt);

        // liquidate borrower
        changePrank(_lender);
        _pool.liquidate(address(_borrower));

        assertEq(_pool.hpb(), priceMed);
        assertEq(_pool.lup(), priceLow);

        assertEq(_pool.borrowerDebt(),      12_100.000961538461538462 * 1e18);
        assertEq(_pool.poolSize(),          400 * 1e18);
        assertEq(_pool.pledgedCollateral(), 200 * 1e18);
        assertEq(_pool.totalBorrowers(),    1);

        assertEq(_pool.poolCollateralization(), 49.766806329494042795 * 1e18);
        assertEq(_pool.poolActualUtilization(), 0.968000002461538272 * 1e18);

        // check buckets debt and collateral after liquidation
        (uint256 quoteToken, uint256 bucketCollateral, ,) = _pool.bucketAt(priceHighest);
        assertEq(quoteToken,       0);
        assertEq(bucketCollateral, 1.403854682567848371 * 1e18);

        (quoteToken, bucketCollateral, ,) = _pool.bucketAt(priceHigh);
        assertEq(quoteToken,       0);
        assertEq(bucketCollateral, 0.596145317432151629 * 1e18);

        (quoteToken, bucketCollateral, ,) = _pool.bucketAt(priceMed);
        assertEq(quoteToken,       11_718.094070353886493404 * 1e18);
        assertEq(bucketCollateral, 0);

        (quoteToken, bucketCollateral, ,) = _pool.bucketAt(priceLow);
        assertEq(quoteToken,       12_500.000961538461538462 * 1e18);
        assertEq(bucketCollateral, 0);

        // check borrower after liquidation
        (
            borrowerDebt,
            borrowerPendingDebt,
            collateralDeposited,
            borrowerInflator
        ) = _pool.borrowerInfo(address(_borrower));
        assertEq(borrowerDebt,                             0);
        assertEq(borrowerPendingDebt,                      0);
        assertEq(collateralDeposited,                      0);
        assertEq(_pool.encumberedCollateral(borrowerDebt, _pool.lup()), 0);
        assertEq(_pool.borrowerCollateralization(borrowerDebt, collateralDeposited, _pool.lup()), Maths.WAD);
        assertEq(borrowerInflator,                         1.171809294361418037665607534 * 1e27);
    }

}
