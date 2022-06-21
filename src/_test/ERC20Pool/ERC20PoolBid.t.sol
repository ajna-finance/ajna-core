// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.14;

import { ERC20Pool  }      from "../../ERC20Pool.sol";
import { ERC20PoolFactory} from "../../ERC20PoolFactory.sol";

import { IPool } from "../../interfaces/IPool.sol";

import { Buckets }    from "../../base/Buckets.sol";

import { BucketMath } from "../../libraries/BucketMath.sol";
import { Maths }      from "../../libraries/Maths.sol";

import { DSTestPlus }                             from "../utils/DSTestPlus.sol";
import { CollateralToken, QuoteToken }            from "../utils/Tokens.sol";
import { UserWithCollateral, UserWithQuoteToken } from "../utils/Users.sol";

contract ERC20PoolBidTest is DSTestPlus {

    address            internal _poolAddress;
    CollateralToken    internal _collateral;
    ERC20Pool          internal _pool;
    QuoteToken         internal _quote;
    UserWithCollateral internal _borrower;
    UserWithQuoteToken internal _lender;
    UserWithCollateral internal _bidder;

    function setUp() external {
        _collateral  = new CollateralToken();
        _quote       = new QuoteToken();
        _poolAddress = new ERC20PoolFactory().deployPool(address(_collateral), address(_quote), 0.05 * 10**18);
        _pool        = ERC20Pool(_poolAddress);

        _borrower   = new UserWithCollateral();
        _bidder     = new UserWithCollateral();
        _lender     = new UserWithQuoteToken();

        _collateral.mint(address(_borrower), 100 * 1e18);
        _collateral.mint(address(_bidder), 100 * 1e18);
        _quote.mint(address(_lender), 200_000 * 1e18);

        _borrower.approveToken(_collateral, address(_pool), 100 * 1e18);
        _bidder.approveToken(_collateral, address(_pool), 100 * 1e18);
        _lender.approveToken(_quote, address(_pool), 200_000 * 1e18);
    }

    /**
     *  @notice Lender deposits 9000 quote accross 3 buckets and borrower borrows 4000.
     *          Bidder successfully purchases 6000 quote partially in 2 purchases.
     */
    function testPurchaseBidPartialAmount() external {
        _lender.addQuoteToken(_pool, address(_lender), 3_000 * 1e18, _p4000);
        _lender.addQuoteToken(_pool, address(_lender), 3_000 * 1e18, _p3010);
        _lender.addQuoteToken(_pool, address(_lender), 3_000 * 1e18, _p1004);

        assertEq(_pool.lup(), 0);

        assertEq(_pool.totalDebt(),       0);
        assertEq(_pool.totalQuoteToken(), 9_000 * 1e18);
        assertEq(_pool.pdAccumulator(),   24_050_428.089622859610921000 * 1e18);

        assertEq(_pool.getPoolCollateralization(), Maths.WAD);
        assertEq(_pool.getPoolActualUtilization(), 0);

        // borrower takes a loan of 4000 DAI making bucket 4000 to be fully utilized
        _borrower.addCollateral(_pool, 100 * 1e18);
        _borrower.borrow(_pool, 4_000 * 1e18, 3_000 * 1e18);

        assertEq(_pool.lup(), _p3010);

        assertEq(_pool.totalDebt(),       4_000.000961538461538462 * 1e18);
        assertEq(_pool.totalQuoteToken(), 5_000 * 1e18);
        assertEq(_pool.totalCollateral(), 100 * 1e18);
        assertEq(_pool.pdAccumulator(),   9_036_753.031683275440972000 * 1e18);

        assertEq(_pool.getPoolCollateralization(), 75.272282460648370521 * 1e18);
        assertEq(_pool.getPoolActualUtilization(), 0.571318115176428157 * 1e18);

        // check bidder and pool balances after borrowing and before purchaseBid
        assertEq(_collateral.balanceOf(address(_bidder)), 100 * 1e18);
        assertEq(_quote.balanceOf(address(_bidder)),      0);
        assertEq(_collateral.balanceOf(address(_pool)),   100 * 1e18);
        assertEq(_quote.balanceOf(address(_pool)),        5_000 * 1e18);

        // check 4_000.927678580567537368 bucket balance before purchase bid
        (, , , uint256 deposit, uint256 debt, , , uint256 bucketCollateral) = _pool.bucketAt(_p4000);
        assertEq(deposit, 0);
        assertEq(debt,    3_000 * 1e18);

        // check 3_010.892022197881557845 bucket balance before purchase bid
        (, , , deposit, debt, , , bucketCollateral) = _pool.bucketAt(_p3010);
        assertEq(deposit,          2_000 * 1e18);
        assertEq(debt,             1_000.000961538461538462 * 1e18);
        assertEq(bucketCollateral, 0);

        // should revert if invalid price
        vm.expectRevert("BM:PTI:OOB");
        _bidder.purchaseBid(_pool, _p1, 1_000);

        // should revert if bidder doesn't have enough collateral
        vm.expectRevert("P:PB:INSUF_COLLAT");
        _bidder.purchaseBid(_pool, 2_000_000 * 1e18, _p4000);

        // should revert if trying to purchase more than on bucket
        vm.expectRevert("B:PB:INSUF_BUCKET_LIQ");
        _bidder.purchaseBid(_pool, 4_000 * 1e18, _p4000);

        // purchase 2000 bid from 4_000.927678580567537368 bucket
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(_bidder), address(_pool), 0.499884067064554307 * 1e18);
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(_pool), address(_bidder), 2_000 * 1e18);
        vm.expectEmit(true, true, false, true);
        emit Purchase(address(_bidder), _p4000, 2_000 * 1e18, 0.499884067064554307 * 1e18);
        _bidder.purchaseBid(_pool, 2_000 * 1e18, _p4000);

        assertEq(_pool.lup(), _p1004);

        assertEq(_pool.totalDebt(),       4_000.000961538461538462 * 1e18);
        assertEq(_pool.totalQuoteToken(), 3_000 * 1e18);
        assertEq(_pool.totalCollateral(), 100 * 1e18);
        assertEq(_pool.pdAccumulator(),   3_014_968.987287512325282000 * 1e18);

        assertEq(_pool.getPoolCollateralization(), 25.124735521129384490 * 1e18);
        assertEq(_pool.getPoolActualUtilization(), 0.571428630298265069 * 1e18);

        // check bidder and pool balances
        assertEq(_collateral.balanceOf(address(_bidder)), 99.500115932935445693 * 1e18);
        assertEq(_quote.balanceOf(address(_bidder)),      2_000 * 1e18);
        assertEq(_collateral.balanceOf(address(_pool)),   100.499884067064554307 * 1e18);
        assertEq(_quote.balanceOf(address(_pool)),        3_000 * 1e18);

        // check 4_000.927678580567537368 bucket balance after purchase bid
        (, , , deposit, debt, , , bucketCollateral) = _pool.bucketAt(_p4000);
        assertEq(deposit,          0);
        assertEq(debt,             1_000 * 1e18);
        assertEq(bucketCollateral, 0.499884067064554307 * 1e18);

        // check 3_010.892022197881557845 bucket balance after purchase bid
        (, , , deposit, debt, , , bucketCollateral) = _pool.bucketAt(_p3010);
        assertEq(deposit,          0);
        assertEq(debt,             3_000.000961538461538462 * 1e18);
        assertEq(bucketCollateral, 0);

        // check 1_004.989662429170775094 bucket balance after purchase bid
        (, , , deposit, debt, , , bucketCollateral) = _pool.bucketAt(_p1004);
        assertEq(deposit,          3_000 * 1e18);
        assertEq(debt,             0);
        assertEq(bucketCollateral, 0);
    }

    /**
     *  @notice Lender deposits 7000 quote accross 3 buckets and borrower borrows 2000 quote.
     *          Bidder successfully purchases 6000 quote fully accross 2 purchases.
     */
    function testPurchaseBidEntireAmount() external {
        _lender.addQuoteToken(_pool, address(_lender), 1_000 * 1e18, _p4000);
        _lender.addQuoteToken(_pool, address(_lender), 1_000 * 1e18, _p3010);
        _lender.addQuoteToken(_pool, address(_lender), 5_000 * 1e18, _p2000);

        assertEq(_pool.hpb(), _p4000);
        assertEq(_pool.lup(), 0);

        assertEq(_pool.totalDebt(),       0);
        assertEq(_pool.totalQuoteToken(), 7_000 * 1e18);
        assertEq(_pool.totalCollateral(), 0);
        assertEq(_pool.pdAccumulator(),   17_012_927.794982087598258000 * 1e18);

        assertEq(_pool.getPoolCollateralization(), Maths.WAD);
        assertEq(_pool.getPoolActualUtilization(), 0);

        // borrower takes a loan of 1000 DAI from bucket 4000
        _borrower.addCollateral(_pool, 100 * 1e18);
        _borrower.borrow(_pool, 1_000 * 1e18, 3_000 * 1e18);
        // borrower takes a loan of 1000 DAI from bucket 3000
        _borrower.borrow(_pool, 1_000 * 1e18, 3_000 * 1e18);

        assertEq(_pool.hpb(), _p4000);
        assertEq(_pool.lup(), _p3010);

        assertEq(_pool.totalDebt(),       2_000.001923076923076924 * 1e18);
        assertEq(_pool.totalQuoteToken(), 5_000 * 1e18);
        assertEq(_pool.totalCollateral(), 100 * 1e18);
        assertEq(_pool.pdAccumulator(),   10_001_108.094203638503045000 * 1e18);

        assertEq(_pool.getPoolCollateralization(), 150.544456355609120576 * 1e18);
        assertEq(_pool.getPoolActualUtilization(), 0.375824015190028699 * 1e18);

        // check bidder and pool balances
        assertEq(_collateral.balanceOf(address(_bidder)), 100 * 1e18);
        assertEq(_quote.balanceOf(address(_bidder)),      0);
        assertEq(_collateral.balanceOf(address(_pool)),   100 * 1e18);
        assertEq(_quote.balanceOf(address(_pool)),        5_000 * 1e18);

        // check 4_000.927678580567537368 bucket balance before purchase Bid
        (, , , uint256 deposit, uint256 debt, , , uint256 bucketCollateral) = _pool.bucketAt(_p4000);
        assertEq(deposit,          0);
        assertEq(debt,             1_000.000961538461538462 * 1e18);
        assertEq(bucketCollateral, 0);

        // check 3_010.892022197881557845 bucket balance before purchase bid
        (, , , deposit, debt, , , bucketCollateral) = _pool.bucketAt(_p3010);
        assertEq(deposit,          0);
        assertEq(debt,             1_000.000961538461538462 * 1e18);
        assertEq(bucketCollateral, 0);

        // check 2_000.221618840727700609 bucket balance before purchase bid
        (, , , deposit, debt, , , bucketCollateral) = _pool.bucketAt(_p2000);
        assertEq(deposit,          5_000 * 1e18);
        assertEq(debt,             0);
        assertEq(bucketCollateral, 0);

        // purchase 1000 bid - entire amount in 4000 bucket
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(_bidder), address(_pool), 0.249942273861155550 * 1e18);
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(_pool), address(_bidder), 1_000.000961538461538462 * 1e18);
        vm.expectEmit(true, true, false, true);
        emit Purchase(address(_bidder), _p4000, 1_000.000961538461538462 * 1e18, 0.249942273861155550 * 1e18);
        _bidder.purchaseBid(_pool, 1_000.000961538461538462 * 1e18, _p4000);

        assertEq(_pool.hpb(), _p3010); // hbp should be pushed downwards
        assertEq(_pool.lup(), _p2000); // lup should be pushed downwards

        assertEq(_pool.totalDebt(),       2_000.001923076923076924 * 1e18);
        assertEq(_pool.totalQuoteToken(), 3_999.999038461538461538 * 1e18);
        assertEq(_pool.totalCollateral(), 100 * 1e18);
        assertEq(_pool.pdAccumulator(),   8_000_884.552072892686350749 * 1e18);

        assertEq(_pool.getPoolCollateralization(), 100.010984777627945004 * 1e18);
        assertEq(_pool.getPoolActualUtilization(), 0.333333600427307624 * 1e18);

        // check bidder and pool balances
        assertEq(_collateral.balanceOf(address(_bidder)), 99.750057726138844450 * 1e18);
        assertEq(_quote.balanceOf(address(_bidder)),      1_000.000961538461538462 * 1e18);
        assertEq(_collateral.balanceOf(address(_pool)),   100.249942273861155550 * 1e18);
        assertEq(_quote.balanceOf(address(_pool)),        3_999.999038461538461538 * 1e18);

        // check 4_000.927678580567537368 bucket balance after purchase Bid
        (, , , deposit, debt, , , bucketCollateral) = _pool.bucketAt(_p4000);
        assertEq(deposit,          0);
        assertEq(debt,             0);
        assertEq(bucketCollateral, 0.249942273861155550 * 1e18);

        // check 3_010.892022197881557845 bucket balance
        (, , , deposit, debt, , , bucketCollateral) = _pool.bucketAt(_p3010);
        assertEq(deposit,          0);
        assertEq(debt,             1_000.000961538461538462 * 1e18);
        assertEq(bucketCollateral, 0);

        // check 2_000.221618840727700609 bucket balance
        (, , , deposit, debt, , , bucketCollateral) = _pool.bucketAt(_p2000);
        assertEq(deposit,          3_999.999038461538461538 * 1e18);
        assertEq(debt,             1_000.000961538461538462 * 1e18);
        assertEq(bucketCollateral, 0);
    }

    function testPurchaseBidCannotReallocate() external {
        _lender.addQuoteToken(_pool, address(_lender), 1_000 * 1e18, _p4000);
        _lender.addQuoteToken(_pool, address(_lender), 1_000 * 1e18, _p3010);
        _lender.addQuoteToken(_pool, address(_lender), 500 * 1e18,   _p2000);

        assertEq(_pool.hpb(), _p4000);
        assertEq(_pool.lup(), 0);

        assertEq(_pool.totalDebt(),       0);
        assertEq(_pool.totalQuoteToken(), 2_500 * 1e18);
        assertEq(_pool.totalCollateral(), 0);
        assertEq(_pool.pdAccumulator(),   8_011_930.510198812945517500 * 1e18);

        assertEq(_pool.getPoolCollateralization(), Maths.WAD);
        assertEq(_pool.getPoolActualUtilization(), 0);

        // borrower takes a loan of 1000 DAI from bucket 4000
        _borrower.addCollateral(_pool, 100 * 1e18);
        _borrower.borrow(_pool, 1_000 * 1e18, 3_000 * 1e18);

        // borrower takes a loan of 1000 DAI from bucket 3000
        _borrower.borrow(_pool, 1_000 * 1e18, 3_000 * 1e18);

        assertEq(_pool.hpb(), _p4000);
        assertEq(_pool.lup(), _p3010);

        assertEq(_pool.totalDebt(),       2_000.001923076923076924 * 1e18);
        assertEq(_pool.totalQuoteToken(), 500 * 1e18);
        assertEq(_pool.totalCollateral(), 100 * 1e18);
        assertEq(_pool.pdAccumulator(),   1_000_110.809420363850304500 * 1e18);

        assertEq(_pool.getPoolCollateralization(), 150.544456355609120576 * 1e18);
        assertEq(_pool.getPoolActualUtilization(), 0.857572634515142018 * 1e18);

        // should revert if trying to bid more than available liquidity (1000 vs 500)
        vm.expectRevert("B:RD:NO_REALLOC_LOCATION");
        _bidder.purchaseBid(_pool, 1_000 * 1e18, _p4000);
    }

    /**
     *  @notice Lender deposits 4000 quote accross 3 buckets and borrower borrows 2000 quote.
     *          Bidder reverts: attempt to purchase 1000 quote.
     */
    function testPurchaseBidUndercollateralized() external {
        _lender.addQuoteToken(_pool, address(_lender), 1_000 * 1e18, _p4000);
        _lender.addQuoteToken(_pool, address(_lender), 1_000 * 1e18, _p3010);
        _lender.addQuoteToken(_pool, address(_lender), 2_000 * 1e18, _p1);

        assertEq(_pool.hpb(), _p4000);
        assertEq(_pool.lup(), 0);

        assertEq(_pool.totalDebt(),       0);
        assertEq(_pool.totalQuoteToken(), 4_000 * 1e18);
        assertEq(_pool.totalCollateral(), 0);
        assertEq(_pool.pdAccumulator(),   7_013_819.700778449095213000 * 1e18);

        assertEq(_pool.getPoolCollateralization(), Maths.WAD);
        assertEq(_pool.getPoolActualUtilization(), 0);

        // borrower takes a loan of 1000 DAI from bucket 4000
        _borrower.addCollateral(_pool, 100 * 1e18);
        _borrower.borrow(_pool, 1_000 * 1e18, 3_000 * 1e18);

        // borrower takes a loan of 1000 DAI from bucket 3000
        _borrower.borrow(_pool, 1_000 * 1e18, 3_000 * 1e18);

        assertEq(_pool.hpb(), _p4000);
        assertEq(_pool.lup(), _p3010);

        assertEq(_pool.totalDebt(),       2_000.001923076923076924 * 1e18);
        assertEq(_pool.totalQuoteToken(), 2_000 * 1e18);
        assertEq(_pool.totalCollateral(), 100 * 1e18);
        assertEq(_pool.pdAccumulator(),   2000 * 1e18);

        assertEq(_pool.getPoolCollateralization(), 150.544456355609120576 * 1e18);
        assertEq(_pool.getPoolActualUtilization(), 0.999667983104503203 * 1e18);

        // should revert when leave pool undercollateralized
        vm.expectRevert("P:PB:POOL_UNDER_COLLAT");
        _bidder.purchaseBid(_pool, 1_000 * 1e18, _p4000);
    }

}
