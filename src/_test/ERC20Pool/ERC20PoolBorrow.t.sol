// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.11;

import { ERC20Pool }        from "../../ERC20Pool.sol";
import { ERC20PoolFactory } from "../../ERC20PoolFactory.sol";

import { Buckets } from "../../base/Buckets.sol";

import { IPool } from "../../interfaces/IPool.sol";

import { Maths }   from "../../libraries/Maths.sol";

import { DSTestPlus }                             from "../utils/DSTestPlus.sol";
import { CollateralToken, QuoteToken }            from "../utils/Tokens.sol";
import { UserWithCollateral, UserWithQuoteToken } from "../utils/Users.sol";

contract ERC20PoolBorrowTest is DSTestPlus {

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

        _collateral.mint(address(_borrower), 100 * 1e18);
        _collateral.mint(address(_borrower2), 100 * 1e18);
        _quote.mint(address(_lender), 300_000 * 1e18);

        _borrower.approveToken(_collateral, address(_pool), 100 * 1e18);
        _borrower2.approveToken(_collateral, address(_pool), 100 * 1e18);
        _lender.approveToken(_quote, address(_pool), 300_000 * 1e18);
    }

    /**
     *  @notice With 1 lender and 1 borrower tests addQuoteToken (subsequently reallocation), addCollateral and borrow.
     *          Borrower reverts:
     *              attempts to borrow more than available quote.
     *              attempts to borrow more than their collateral supports.
     *              attempts to borrow but stop price is exceeded.
     */
    function testBorrow() external {
        uint256 priceHighest = _p4000;
        uint256 priceHigh    = _p3514;
        uint256 priceMed     = _p3010;
        uint256 priceLow     = _p2503;
        uint256 priceLowest  = _p2000;

        // lender deposits 10000 DAI in 5 buckets each
        _lender.addQuoteToken(_pool, address(_lender), 10_000 * 1e18, priceHighest);
        _lender.addQuoteToken(_pool, address(_lender), 10_000 * 1e18, priceHigh);
        _lender.addQuoteToken(_pool, address(_lender), 10_000 * 1e18, priceMed);
        _lender.addQuoteToken(_pool, address(_lender), 10_000 * 1e18, priceLow);
        _lender.addQuoteToken(_pool, address(_lender), 10_000 * 1e18, priceLowest);

        assertEq(_pool.hpb(), priceHighest);
        assertEq(_pool.lup(), 0);

        assertEq(_pool.totalDebt(),       0);
        assertEq(_pool.totalQuoteToken(), 50_000 * 1e18);
        assertEq(_pool.totalCollateral(), 0);
        assertEq(_pool.pdAccumulator(),   150_298_948.393042738130440000 * 1e18);

        assertEq(_pool.getPoolCollateralization(), Maths.ONE_WAD);
        assertEq(_pool.getPoolActualUtilization(), 0);

        assertEq(_pool.getPendingPoolInterest(),               0);
        assertEq(_pool.getPendingBucketInterest(priceHighest), 0);

        // should revert if borrower wants to borrow a greater amount than in pool
        vm.expectRevert("P:B:INSUF_LIQ");
        _borrower.borrow(_pool, 60_000 * 1e18, 2_000 * 1e18);

        // should revert if insufficient collateral deposited by borrower
        vm.expectRevert("P:B:INSUF_COLLAT");
        _borrower.borrow(_pool, 10_000 * 1e18, 4_000 * 1e18);

        // borrower deposit 10 MKR collateral
        _borrower.addCollateral(_pool, 10 * 1e18);

        // should revert if limit price exceeded
        vm.expectRevert("B:B:PRICE_LT_LIMIT");
        _borrower.borrow(_pool, 15_000 * 1e18, 4_000 * 1e18);

        // borrower deposits additional 90 MKR collateral
        _borrower.addCollateral(_pool, 90 * 1e18);

        // get a 21_000 DAI loan from 3 buckets, loan price should be 3000 DAI
        assertEq(_pool.estimatePriceForLoan(21_000 * 1e18), priceMed);

        vm.expectEmit(true, true, false, true);
        emit Transfer(address(_pool), address(_borrower), 21_000 * 1e18);
        vm.expectEmit(true, true, false, true);
        emit Borrow(address(_borrower), priceMed, 21_000 * 1e18);
        _borrower.borrow(_pool, 21_000 * 1e18, 2_500 * 1e18);

        assertEq(_pool.hpb(), priceHighest);
        assertEq(_pool.lup(), priceMed);

        assertEq(_pool.totalDebt(),       21_000.000961538461538462 * 1e18);
        assertEq(_pool.totalQuoteToken(), 29_000 * 1e18);
        assertEq(_pool.totalCollateral(), 100 * 1e18);
        assertEq(_pool.pdAccumulator(),   72_135_434.631135162709645000 * 1e18);

        assertEq(_pool.getPoolCollateralization(), 14.337580401602531154 * 1e18);
        assertEq(_pool.getPoolActualUtilization(), 0.467100971880547845 * 1e18);

        assertEq(_pool.getPendingPoolInterest(),               0);
        assertEq(_pool.getPendingBucketInterest(priceHighest), 0);

        assertEq(_quote.balanceOf(address(_borrower)), 21_000 * 1e18);
        assertEq(_quote.balanceOf(address(_pool)),     29_000 * 1e18);

        // check bucket deposit and debt at 3_010.892022197881557845
        (, , , uint256 deposit, uint256 debt, , , ) = _pool.bucketAt(priceMed);
        assertEq(deposit, 9_000 * 1e18);

        // check borrower balance
        (uint256 borrowerDebt, uint256 depositedCollateral, ) = _pool.borrowers(address(_borrower));
        assertEq(borrowerDebt,        21_000.000961538461538462 * 1e18);
        assertEq(depositedCollateral, 100 * 1e18);

        assertEq(
            _pool.getEncumberedCollateral(_pool.totalDebt()),
            _pool.getEncumberedCollateral(borrowerDebt)
        );

        skip(8200);

        // tie out borrower and pool debt
        (, uint256 borrowerPendingDebt, , , , , ) = _pool.getBorrowerInfo(address(_borrower));
        uint256 poolPendingDebt = _pool.totalDebt() + _pool.getPendingPoolInterest();
        assertEq(borrowerPendingDebt, poolPendingDebt);

        // borrow remaining 9_000 DAI from LUP
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(_pool), address(_borrower), 9_000 * 1e18);
        vm.expectEmit(true, true, false, true);
        emit Borrow(address(_borrower), priceMed, 9_000 * 1e18);
        _borrower.borrow(_pool, 9_000 * 1e18, priceLow);

        assertEq(_pool.hpb(), priceHighest);
        assertEq(_pool.lup(), priceMed);

        assertEq(_pool.totalDebt(),       30_000.274946172972626795 * 1e18);
        assertEq(_pool.totalQuoteToken(), 20_000 * 1e18);
        assertEq(_pool.totalCollateral(), 100 * 1e18);
        assertEq(_pool.pdAccumulator(),   45_037_406.431354228689040000 * 1e18);

        assertEq(_pool.getPoolCollateralization(), 10.036214760031625123 * 1e18);
        assertEq(_pool.getPoolActualUtilization(), 0.667289121131590564 * 1e18);

        assertEq(_pool.getPendingPoolInterest(),               0);
        assertEq(_pool.getPendingBucketInterest(priceHighest), 0.130010992165949015 * 1e18);

        assertEq(_quote.balanceOf(address(_borrower)), 30_000 * 1e18);
        assertEq(_quote.balanceOf(address(_pool)),     20_000 * 1e18);

        // check bucket debt at 2_503.519024294695168295
        (, , , deposit, debt, , , ) = _pool.bucketAt(priceLow);
        assertEq(debt,    0);
        assertEq(deposit, 10_000 * 1e18);

        // check bucket debt at 3_010.892022197881557845
        (, , , deposit, debt, , , ) = _pool.bucketAt(priceMed);
        assertEq(debt,    10_000.014924188640728764 * 1e18);
        assertEq(deposit, 0);

        // check bucket debt at 3_514.334495390401848927
        (, , , deposit, debt, , , ) = _pool.bucketAt(priceHigh);
        assertEq(debt,    10_000 * 1e18);
        assertEq(deposit, 0);

        // check bucket debt at 4_000.927678580567537368
        (, , , deposit, debt, , , ) = _pool.bucketAt(priceHighest);
        assertEq(debt,    10_000 * 1e18);
        assertEq(deposit, 0);

        // check borrower balances
        (borrowerDebt, depositedCollateral, ) = _pool.borrowers(address(_borrower));
        assertEq(borrowerDebt,        30_000.274946172972626795 * 1e18);
        assertEq(depositedCollateral, 100 * 1e18);

        assertEq(
            _pool.getEncumberedCollateral(_pool.totalDebt()),
            _pool.getEncumberedCollateral(borrowerDebt)
        );

        (, borrowerPendingDebt, , , , , ) = _pool.getBorrowerInfo(address(_borrower));
        poolPendingDebt = _pool.totalDebt() + _pool.getPendingPoolInterest();
        assertEq(borrowerPendingDebt, poolPendingDebt);

        // deposit at 5_007.644384905151472283 price and reallocate entire debt
        _lender.addQuoteToken(_pool, address(_lender), 40_000 * 1e18, _p5007);

        assertEq(_pool.hpb(), _p5007);
        assertEq(_pool.lup(), _p5007);

        assertEq(_pool.totalDebt(),       30_000.274946172972626795 * 1e18);
        assertEq(_pool.totalQuoteToken(), 60_000 * 1e18);
        assertEq(_pool.totalCollateral(), 100 * 1e18);
        assertEq(_pool.pdAccumulator(),   200_375_037.411247156657331875 * 1e18);

        assertEq(_pool.getPoolCollateralization(), 16.691994969679298519 * 1e18);
        assertEq(_pool.getPoolActualUtilization(), 0.428489008475468263 * 1e18);

        assertEq(_pool.getPendingPoolInterest(),               0);
        assertEq(_pool.getPendingBucketInterest(priceHighest), 0);

        (, borrowerPendingDebt, , , , , ) = _pool.getBorrowerInfo(address(_borrower));
        poolPendingDebt = _pool.totalDebt() + _pool.getPendingPoolInterest();
        assertEq(borrowerPendingDebt, poolPendingDebt);

        // check bucket debt at 2_503.519024294695168295
        (, , , deposit, debt, , , ) = _pool.bucketAt(priceLow);
        assertEq(debt,    0);
        assertEq(deposit, 10_000 * 1e18);

        // check bucket debt at 3_010.892022197881557845
        (, , , deposit, debt, , , ) = _pool.bucketAt(priceMed);
        assertEq(debt,    0);
        assertEq(deposit, 10_000.014924188640728764 * 1e18);

        // check bucket debt at 3_514.334495390401848927
        (, , , deposit, debt, , , ) = _pool.bucketAt(priceHigh);
        assertEq(debt,    0);
        assertEq(deposit, 10_000.130010992165949015 * 1e18);

        // check bucket debt at 4_000.927678580567537368
        (, , , deposit, debt, , , ) = _pool.bucketAt(priceHighest);
        assertEq(debt,    0);
        assertEq(deposit, 10_000.130010992165949015 * 1e18);

        // check bucket debt at 5_007.644384905151472283
        (, , , deposit, debt, , , ) = _pool.bucketAt(_p5007);
        assertEq(debt,    30_000.274946172972626794 * 1e18);
        assertEq(deposit, 9_999.725053827027373206 * 1e18);
    }

    /**
     *  @notice With 1 lender and 2 borrowers tests addQuoteToken,
     *          addCollateral and borrow on an undercollateralized pool.
     *          Borrower2 reverts: attempts to borrow when pool is undercollateralized.
     */
    function testBorrowPoolUndercollateralization() external {
        uint256 priceHigh = _p2000;
        uint256 priceMed  = _p1004;
        uint256 priceLow  = _p502;

        // lender deposits 200_000 DAI in 3 buckets
        _lender.addQuoteToken(_pool, address(_lender), 100_000 * 1e18, priceHigh);
        _lender.addQuoteToken(_pool, address(_lender), 50_000 * 1e18, priceMed);
        _lender.addQuoteToken(_pool, address(_lender), 50_000 * 1e18, priceLow);

        // borrower1 takes a loan of 100_000 DAI
        assertEq(_pool.estimatePriceForLoan(75_000 * 1e18),  priceHigh);
        assertEq(_pool.estimatePriceForLoan(125_000 * 1e18), priceMed);
        assertEq(_pool.estimatePriceForLoan(175_000 * 1e18), priceLow);
        _borrower.addCollateral(_pool, 51 * 1e18);
        _borrower.borrow(_pool, 100_000 * 1e18, 1_000 * 1e18);

        // check pool collateralization after borrower1 takes loan
        uint256 poolCollateralizationAfterB1Actions = _pool.getPoolCollateralization();
        (uint256 borrower1Debt, , ) = _pool.borrowers(address(_borrower));
        assertEq(
            _pool.getEncumberedCollateral(_pool.totalDebt()),
            _pool.getEncumberedCollateral(borrower1Debt)
        );
        assertEq(poolCollateralizationAfterB1Actions, 1.020113015799992129 * 1e18);

        // check utilization after borrow - since pool is barely overcollateralized actual < target
        uint256 targetUtilizationAfterBorrow = _pool.getPoolTargetUtilization();
        uint256 actualUtilizationAfterBorrow = _pool.getPoolActualUtilization();
        assertLt(actualUtilizationAfterBorrow, targetUtilizationAfterBorrow);

        // borrower2 adds collateral to attempt a borrow
        assertEq(_pool.estimatePriceForLoan(25_000 * 1e18),  priceMed);
        assertEq(_pool.estimatePriceForLoan(75_000 * 1e18),  priceLow);
        assertEq(_pool.estimatePriceForLoan(175_000 * 1e18), 0);
        _borrower2.addCollateral(_pool, 51 * 1e18);

        // check collateralization / utilization after borrower adds collateral
        uint256 poolCollateralizationAfterB2Actions = _pool.getPoolCollateralization();
        uint256 targetUtilizationAfterAddCollateral = _pool.getPoolTargetUtilization();
        uint256 actualUtilizationAfterAddCollateral = _pool.getPoolActualUtilization();

        assertEq(_pool.getPoolCollateralization(),    2.040226031599984258 * 1e18);
        assertGt(poolCollateralizationAfterB2Actions, poolCollateralizationAfterB1Actions);
        assertEq(actualUtilizationAfterAddCollateral, actualUtilizationAfterBorrow);
        assertLt(targetUtilizationAfterAddCollateral, targetUtilizationAfterBorrow);

        assertEq(_pool.getPoolMinDebtAmount(), 100.000000961538461538 * 1e18);
        assertEq(_pool.totalBorrowers(),       1);

        // should revert when taking a loan below pool min debt amount
        vm.expectRevert("P:B:AMT_LT_AVG_DEBT");
        _borrower2.borrow(_pool, 100 * 1e18, 1_000 * 1e18);

        // should revert when taking a loan of 5_000 DAI that will drive pool undercollateralized
        vm.expectRevert("P:B:POOL_UNDER_COLLAT");
        _borrower2.borrow(_pool, 11_000 * 1e18, 1_000 * 1e18);
    }

    /**
     *  @notice With 1 lender and 1 borrower tests addQuoteToken, addCollateral and borrow.
     *          Collateral amount is verified for correctness.
     */
    function testBorrowTestCollateralValidation() external {
        uint256 priceLow = _p13_57;
        // lender deposits 10_000 DAI at 13.578453165083418466 * 1e18
        _lender.addQuoteToken(_pool, address(_lender), 10_000 * 1e18, priceLow);
        _borrower.addCollateral(_pool, 100 * 1e18);
        // should not revert when borrower takes a loan on 10_000 DAI
        _borrower.borrow(_pool, 1_000 * 1e18, 13.537 * 1e18);
        skip(3600);

        // tie out debt between bucket, borrower, and pool
        (, , , , uint256 debt, , , )              = _pool.bucketAt(priceLow);
        uint256 bucketPendingDebt                 = debt + _pool.getPendingBucketInterest(priceLow);
        (, uint256 borrowerPendingDebt, , , , , ) = _pool.getBorrowerInfo(address(_borrower));
        uint256 poolPendingDebt                   = _pool.totalDebt() + _pool.getPendingPoolInterest();
        assertEq(bucketPendingDebt,   borrowerPendingDebt);
        assertEq(bucketPendingDebt,   poolPendingDebt);
        assertEq(borrowerPendingDebt, poolPendingDebt);
    }

    /**
     *  @notice With 1 lender and 2 borrower tests HUP
     *          moves down when pool is borrowed against
     *          and
     *          moves up when quote token is added.
     */
    function testGetHup() external {
        uint256 priceHigh = _p2000;
        uint256 priceMed  = _p1004;
        uint256 priceLow  = _p502;

        // lender deposits 150_000 DAI in 3 buckets
        _lender.addQuoteToken(_pool, address(_lender), 50_000 * 1e18, priceHigh);
        _lender.addQuoteToken(_pool, address(_lender), 50_000 * 1e18, priceMed);
        _lender.addQuoteToken(_pool, address(_lender), 50_000 * 1e18, priceLow);

        // borrow max possible from hdp
        _borrower.addCollateral(_pool, 51 * 1e18);
        _borrower.borrow(_pool, 50_000 * 1e18, 2_000 * 1e18);

        // check hup is below lup and lup equals hdp
        assertEq(_pool.lup(),    priceHigh);
        assertEq(_pool.hpb(),    _pool.lup());
        assertEq(_pool.getHup(), priceMed);

        // borrow max possible from previous hup
        _borrower2.addCollateral(_pool, 51 * 1e18);
        _borrower2.borrow(_pool, 50_000 * 1e18, 1000 * 1e18);

        // check hup moves down
        assertEq(_pool.getHup(), priceLow);
        assert(_pool.getHup() < _pool.lup());

        // add additional quote token to the maxed out priceMed bucket
        assertEq(_pool.getPoolMinDebtAmount(), 100.000001923076923077 * 1e18);

        // should revert when deposit lower than pool min debt amount
        vm.expectRevert("P:AQT:AMT_LT_AVG_DEBT");
        _lender.addQuoteToken(_pool, address(_lender), 100 * 1e18, priceMed);

        _lender.addQuoteToken(_pool, address(_lender), 50_100 * 1e18, priceMed);

        // check hup moves up as additional quote tokens become available
        assertEq(_pool.getHup(), priceMed);
        assertEq(_pool.getHup(), _pool.lup());
    }

    // TODO: finish implemeting
    function testGetMinimumPoolPrice() external {}

}
