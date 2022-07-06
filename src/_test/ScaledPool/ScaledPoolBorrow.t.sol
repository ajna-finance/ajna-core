// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.14;

import { ScaledPool }        from "../../ScaledPool.sol";
import { ScaledPoolFactory } from "../../ScaledPoolFactory.sol";

import { BucketMath }        from "../../libraries/BucketMath.sol";

import { DSTestPlus }                             from "../utils/DSTestPlus.sol";
import { CollateralToken, QuoteToken }            from "../utils/Tokens.sol";
import { UserWithCollateralInScaledPool, UserWithQuoteTokenInScaledPool } from "../utils/Users.sol";

contract ScaledQuoteTokenTest is DSTestPlus {

    uint256 public constant LARGEST_AMOUNT = type(uint256).max / 10**27;

    address                        internal _poolAddress;
    CollateralToken                internal _collateral;
    ScaledPool                     internal _pool;
    QuoteToken                     internal _quote;
    UserWithCollateralInScaledPool internal _borrower;
    UserWithCollateralInScaledPool internal _borrower2;
    UserWithQuoteTokenInScaledPool internal _lender;
    UserWithQuoteTokenInScaledPool internal _lender1;

    function setUp() external {
        _collateral  = new CollateralToken();
        _quote       = new QuoteToken();
        _poolAddress = new ScaledPoolFactory().deployPool(address(_collateral), address(_quote),0.05 * 10**18 );
        _pool        = ScaledPool(_poolAddress);

        _borrower   = new UserWithCollateralInScaledPool();
        _borrower2  = new UserWithCollateralInScaledPool();
        _lender     = new UserWithQuoteTokenInScaledPool();
        _lender1    = new UserWithQuoteTokenInScaledPool();

        _collateral.mint(address(_borrower), 100 * 1e18);
        _collateral.mint(address(_borrower2), 200 * 1e18);

        _quote.mint(address(_lender), 200_000 * 1e18);
        _quote.mint(address(_lender1), 200_000 * 1e18);

        _borrower.approveToken(_collateral, address(_pool), 100 * 1e18);
        _borrower.approveToken(_quote,      address(_pool), 200_000 * 1e18);

        _borrower2.approveToken(_collateral, address(_pool), 200 * 1e18);
        _borrower2.approveToken(_quote,      address(_pool), 200_000 * 1e18);

        _lender.approveToken(_quote,  address(_pool), 200_000 * 1e18);
        _lender1.approveToken(_quote, address(_pool), 200_000 * 1e18);
    }

    function testScaledPoolBorrow() external {
        uint256 priceHighest = _p4000;
        uint256 priceHigh    = _p3514;
        uint256 priceMed     = _p3010;
        uint256 priceLow     = _p2503;
        uint256 priceLowest  = _p2000;

        // lender deposits 10000 DAI in 5 buckets each
        _lender.addQuoteToken(_pool, 10_000 * 1e18, priceHighest);
        _lender.addQuoteToken(_pool, 10_000 * 1e18, priceHigh);
        _lender.addQuoteToken(_pool, 10_000 * 1e18, priceMed);
        _lender.addQuoteToken(_pool, 10_000 * 1e18, priceLow);
        _lender.addQuoteToken(_pool, 10_000 * 1e18, priceLowest);

        assertEq(_pool.htp(), 0);
        assertEq(_pool.lup(), 0.000000099836282890 * 1e18);

        assertEq(_pool.treeSum(),            50_000 * 1e18);
        assertEq(_pool.depositAccumulator(), 50_000 * 1e18);

        // check balances
        assertEq(_quote.balanceOf(address(_pool)),   50_000 * 1e18);
        assertEq(_quote.balanceOf(address(_lender)), 150_000 * 1e18);

        // borrower deposit 100 MKR collateral
        _borrower.addCollateral(_pool, 100 * 1e18);

        // assertEq(15, _pool._findSum(21_000 * 1e18));
        // assertEq(15, _pool._prefixSum(10000));
        // assertEq(15, _pool._lupIndex(21_000 * 1e18));
        // assertEq(11, BucketMath.indexToPrice(4959 - 3232));
        // get a 21_000 DAI loan
        // vm.expectEmit(true, true, false, true);
        // emit Transfer(address(_pool), address(_borrower), 21_000 * 1e18);
        // vm.expectEmit(true, true, false, true);
        // emit Borrow(address(_borrower), priceMed, 21_000 * 1e18);
        // _borrower.borrow(_pool, 21_000 * 1e18, address(0), address(0));

        // assertEq(_pool.hpb(), priceHighest);
        // assertEq(_pool.lup(), priceMed);

        // assertEq(_pool.totalDebt(),       21_000.000961538461538462 * 1e18);
        // assertEq(_pool.totalQuoteToken(), 29_000 * 1e18);
        // assertEq(_pool.totalCollateral(), 100 * 1e18);
        // assertEq(_pool.pdAccumulator(),   72_135_434.631135162709645000 * 1e18);

        // assertEq(_pool.getPoolCollateralization(), 14.337580401602531154 * 1e18);
        // assertEq(_pool.getPoolActualUtilization(), 0.467100971880547845 * 1e18);

        // assertEq(_pool.getPendingPoolInterest(),               0);
        // assertEq(_pool.getPendingBucketInterest(priceHighest), 0);

        // assertEq(_quote.balanceOf(address(_borrower)), 21_000 * 1e18);
        // assertEq(_quote.balanceOf(address(_pool)),     29_000 * 1e18);

        // // check bucket deposit and debt at 3_010.892022197881557845
        // (, , , uint256 deposit, uint256 debt, , , ) = _pool.bucketAt(priceMed);
        // assertEq(deposit, 9_000 * 1e18);

        // // check borrower balance
        // (uint256 borrowerDebt, uint256 depositedCollateral, ) = _pool.borrowers(address(_borrower));
        // assertEq(borrowerDebt,        21_000.000961538461538462 * 1e18);
        // assertEq(depositedCollateral, 100 * 1e18);

        // assertEq(
        //     _pool.getEncumberedCollateral(_pool.totalDebt()),
        //     _pool.getEncumberedCollateral(borrowerDebt)
        // );

        // skip(8200);

        // // tie out borrower and pool debt
        // (, uint256 borrowerPendingDebt, , , , , ) = _pool.getBorrowerInfo(address(_borrower));
        // uint256 poolPendingDebt = _pool.totalDebt() + _pool.getPendingPoolInterest();
        // assertEq(borrowerPendingDebt, poolPendingDebt);

        // // borrow remaining 9_000 DAI from LUP
        // vm.expectEmit(true, true, false, true);
        // emit Transfer(address(_pool), address(_borrower), 9_000 * 1e18);
        // vm.expectEmit(true, true, false, true);
        // emit Borrow(address(_borrower), priceMed, 9_000 * 1e18);
        // _borrower.borrow(_pool, 9_000 * 1e18, priceLow);

        // assertEq(_pool.hpb(), priceHighest);
        // assertEq(_pool.lup(), priceMed);

        // assertEq(_pool.totalDebt(),       30_000.274946172972626795 * 1e18);
        // assertEq(_pool.totalQuoteToken(), 20_000 * 1e18);
        // assertEq(_pool.totalCollateral(), 100 * 1e18);
        // assertEq(_pool.pdAccumulator(),   45_037_406.431354228689040000 * 1e18);

        // assertEq(_pool.getPoolCollateralization(), 10.036214760031625123 * 1e18);
        // assertEq(_pool.getPoolActualUtilization(), 0.667289121131590564 * 1e18);

        // assertEq(_pool.getPendingPoolInterest(),               0);
        // assertEq(_pool.getPendingBucketInterest(priceHighest), 0.130010992165949015 * 1e18);

        // assertEq(_quote.balanceOf(address(_borrower)), 30_000 * 1e18);
        // assertEq(_quote.balanceOf(address(_pool)),     20_000 * 1e18);

        // // check bucket debt at 2_503.519024294695168295
        // (, , , deposit, debt, , , ) = _pool.bucketAt(priceLow);
        // assertEq(debt,    0);
        // assertEq(deposit, 10_000 * 1e18);

        // // check bucket debt at 3_010.892022197881557845
        // (, , , deposit, debt, , , ) = _pool.bucketAt(priceMed);
        // assertEq(debt,    10_000.014924188640728764 * 1e18);
        // assertEq(deposit, 0);

        // // check bucket debt at 3_514.334495390401848927
        // (, , , deposit, debt, , , ) = _pool.bucketAt(priceHigh);
        // assertEq(debt,    10_000 * 1e18);
        // assertEq(deposit, 0);

        // // check bucket debt at 4_000.927678580567537368
        // (, , , deposit, debt, , , ) = _pool.bucketAt(priceHighest);
        // assertEq(debt,    10_000 * 1e18);
        // assertEq(deposit, 0);

        // // check borrower balances
        // (borrowerDebt, depositedCollateral, ) = _pool.borrowers(address(_borrower));
        // assertEq(borrowerDebt,        30_000.274946172972626795 * 1e18);
        // assertEq(depositedCollateral, 100 * 1e18);

        // assertEq(
        //     _pool.getEncumberedCollateral(_pool.totalDebt()),
        //     _pool.getEncumberedCollateral(borrowerDebt)
        // );

        // (, borrowerPendingDebt, , , , , ) = _pool.getBorrowerInfo(address(_borrower));
        // poolPendingDebt = _pool.totalDebt() + _pool.getPendingPoolInterest();
        // assertEq(borrowerPendingDebt, poolPendingDebt);

        // // deposit at 5_007.644384905151472283 price and reallocate entire debt
        // _lender.addQuoteToken(_pool, address(_lender), 40_000 * 1e18, _p5007);

        // assertEq(_pool.hpb(), _p5007);
        // assertEq(_pool.lup(), _p5007);

        // assertEq(_pool.totalDebt(),       30_000.274946172972626795 * 1e18);
        // assertEq(_pool.totalQuoteToken(), 60_000 * 1e18);
        // assertEq(_pool.totalCollateral(), 100 * 1e18);
        // assertEq(_pool.pdAccumulator(),   200_375_037.411247156657331875 * 1e18);

        // assertEq(_pool.getPoolCollateralization(), 16.691994969679298519 * 1e18);
        // assertEq(_pool.getPoolActualUtilization(), 0.428489008475468263 * 1e18);

        // assertEq(_pool.getPendingPoolInterest(),               0);
        // assertEq(_pool.getPendingBucketInterest(priceHighest), 0);

        // (, borrowerPendingDebt, , , , , ) = _pool.getBorrowerInfo(address(_borrower));
        // poolPendingDebt = _pool.totalDebt() + _pool.getPendingPoolInterest();
        // assertEq(borrowerPendingDebt, poolPendingDebt);

        // // check bucket debt at 2_503.519024294695168295
        // (, , , deposit, debt, , , ) = _pool.bucketAt(priceLow);
        // assertEq(debt,    0);
        // assertEq(deposit, 10_000 * 1e18);

        // // check bucket debt at 3_010.892022197881557845
        // (, , , deposit, debt, , , ) = _pool.bucketAt(priceMed);
        // assertEq(debt,    0);
        // assertEq(deposit, 10_000.014924188640728764 * 1e18);

        // // check bucket debt at 3_514.334495390401848927
        // (, , , deposit, debt, , , ) = _pool.bucketAt(priceHigh);
        // assertEq(debt,    0);
        // assertEq(deposit, 10_000.130010992165949015 * 1e18);

        // // check bucket debt at 4_000.927678580567537368
        // (, , , deposit, debt, , , ) = _pool.bucketAt(priceHighest);
        // assertEq(debt,    0);
        // assertEq(deposit, 10_000.130010992165949015 * 1e18);

        // // check bucket debt at 5_007.644384905151472283
        // (, , , deposit, debt, , , ) = _pool.bucketAt(_p5007);
        // assertEq(debt,    30_000.274946172972626794 * 1e18);
        // assertEq(deposit, 9_999.725053827027373206 * 1e18);
    }

}
