// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.11;

import { ERC20Pool  }      from "../ERC20Pool.sol";
import { ERC20PoolFactory} from "../ERC20PoolFactory.sol";

import { IPool } from "../interfaces/IPool.sol";

import { Buckets }    from "../libraries/Buckets.sol";
import { BucketMath } from "../libraries/BucketMath.sol";
import { Maths }      from "../libraries/Maths.sol";

import { DSTestPlus }                             from "./utils/DSTestPlus.sol";
import { CollateralToken, QuoteToken }            from "./utils/Tokens.sol";
import { UserWithCollateral, UserWithQuoteToken } from "./utils/Users.sol";

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
        _poolAddress = new ERC20PoolFactory().deployPool(address(_collateral), address(_quote));
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

    // @notice: lender deposits 9000 quote accross 3 buckets
    // @notice: borrower borrows 4000
    // @notice: bidder successfully purchases 6000 quote partially in 2 purchases
    function testPurchaseBidPartialAmount() external {
        _lender.addQuoteToken(_pool, address(_lender), 3_000 * 1e18, _p4000);
        _lender.addQuoteToken(_pool, address(_lender), 3_000 * 1e18, _p3010);
        _lender.addQuoteToken(_pool, address(_lender), 3_000 * 1e18, _p1004);
        assertEq(_pool.totalQuoteToken(),          9_000 * 1e18);
        assertEq(_pool.getPoolCollateralization(), Maths.ONE_RAY);
        assertEq(_pool.getPoolActualUtilization(), 0);

        // borrower takes a loan of 4000 DAI making bucket 4000 to be fully utilized
        _borrower.addCollateral(_pool, 100 * 1e18);
        _borrower.borrow(_pool, 4_000 * 1e18, 3_000 * 1e18);
        assertEq(_pool.lup(), 3_010.892022197881557845 * 1e18);
        assertEq(_pool.getPoolCollateralization(), 75.272300554947038946124999990 * 1e27);

        // should revert if invalid price
        vm.expectRevert(BucketMath.PriceOutsideBoundry.selector);
        _bidder.purchaseBid(_pool, _p1, 1_000);

        // should revert if bidder doesn't have enough collateral
        vm.expectRevert(IPool.InsufficientCollateralBalance.selector);
        _bidder.purchaseBid(_pool, 2_000_000 * 1e18, _p4000);

        // should revert if trying to purchase more than on bucket
        (, , , uint256 amount, uint256 bucketDebt, , , ) = _pool.bucketAt(_p4000);

        vm.expectRevert(
            abi.encodeWithSelector(
                Buckets.InsufficientBucketLiquidity.selector,
                amount + bucketDebt
            )
        );
        _bidder.purchaseBid(_pool, 4_000 * 1e18, _p4000);

        // check bidder and pool balances after borrowing and before purchaseBid
        assertEq(_collateral.balanceOf(address(_bidder)), 100 * 1e18);
        assertEq(_quote.balanceOf(address(_bidder)),      0);
        assertEq(_collateral.balanceOf(address(_pool)),   100 * 1e18);
        assertEq(_quote.balanceOf(address(_pool)),        5_000 * 1e18);
        assertEq(_pool.totalQuoteToken(),                 5_000 * 1e18);
        assertEq(_pool.totalCollateral(),                 100 * 1e18);
        assertEq(_pool.getPoolCollateralization(),        75.272300554947038946124999990 * 1e27);
        assertEq(_pool.getPoolActualUtilization(),        0.444444444444444444444444444 * 1e27);

        // check 4_000.927678580567537368 bucket balance before purchase bid
        (, , , uint256 deposit, uint256 debt, , , uint256 bucketCollateral) = _pool.bucketAt(_p4000);
        assertEq(deposit, 0);
        assertEq(debt,    3_000 * 1e18);

        // check 3_010.892022197881557845 bucket balance before purchase bid
        (, , , deposit, debt, , , bucketCollateral) = _pool.bucketAt(_p3010);
        assertEq(deposit,          2_000 * 1e18);
        assertEq(debt,             1_000 * 1e18);
        assertEq(bucketCollateral, 0);

        // purchase 2000 bid from 4_000.927678580567537368 bucket
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(_bidder), address(_pool), 0.499884067064554307 * 1e18);
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(_pool), address(_bidder), 2_000 * 1e18);
        vm.expectEmit(true, true, false, true);
        emit Purchase(
            address(_bidder),
            _p4000,
            2_000 * 1e18,
            0.499884067064554307 * 1e18
        );
        _bidder.purchaseBid(_pool, 2_000 * 1e18, _p4000);

        assertEq(_pool.lup(), _p1004);
        assertEq(_pool.getPoolCollateralization(), 25.124741560729269377350000003 * 1e27);
        // check 4_000.927678580567537368 bucket balance after purchase bid
        (, , , deposit, debt, , , bucketCollateral) = _pool.bucketAt(_p4000);
        assertEq(deposit,          0);
        assertEq(debt,             1_000 * 1e18);
        assertEq(bucketCollateral, 0.499884067064554307 * 1e18);

        // check 3_010.892022197881557845 bucket balance after purchase bid
        (, , , deposit, debt, , , bucketCollateral) = _pool.bucketAt(_p3010);
        assertEq(deposit,          0);
        assertEq(debt,             3_000 * 1e18);
        assertEq(bucketCollateral, 0);

        // check 1_004.989662429170775094 bucket balance after purchase bid
        (, , , deposit, debt, , , bucketCollateral) = _pool.bucketAt(_p1004);
        assertEq(deposit,          3_000 * 1e18);
        assertEq(debt,             0);
        assertEq(bucketCollateral, 0);

        // check bidder and pool balances
        assertEq(_collateral.balanceOf(address(_bidder)), 99.500115932935445693 * 1e18);
        assertEq(_quote.balanceOf(address(_bidder)),      2_000 * 1e18);
        assertEq(_collateral.balanceOf(address(_pool)),   100.499884067064554307 * 1e18);
        assertEq(_quote.balanceOf(address(_pool)),        3_000 * 1e18);
        assertEq(_pool.totalQuoteToken(),                 3_000 * 1e18);
        assertEq(_pool.totalCollateral(),                 100 * 1e18);
        assertEq(_pool.getPoolCollateralization(),        25.124741560729269377350000003 * 1e27);
        assertEq(_pool.getPoolActualUtilization(),        0.571428571428571428571428571 * 1e27);
    }

    // @notice: lender deposits 7000 quote accross 3 buckets
    // @notice: borrower borrows 2000 quote
    // @notice: bidder successfully purchases 6000 quote fully accross 2 purchases
    function testPurchaseBidEntireAmount() external {
        _lender.addQuoteToken(_pool, address(_lender), 1_000 * 1e18, _p4000);
        _lender.addQuoteToken(_pool, address(_lender), 1_000 * 1e18, _p3010);
        _lender.addQuoteToken(_pool, address(_lender), 5_000 * 1e18, _p2000);

        // borrower takes a loan of 1000 DAI from bucket 4000
        _borrower.addCollateral(_pool, 100 * 1e18);
        _borrower.borrow(_pool, 1_000 * 1e18, 3_000 * 1e18);
        // borrower takes a loan of 1000 DAI from bucket 3000
        _borrower.borrow(_pool, 1_000 * 1e18, 3_000 * 1e18);

        // check bidder and pool balances
        assertEq(_collateral.balanceOf(address(_bidder)), 100 * 1e18);
        assertEq(_quote.balanceOf(address(_bidder)),      0);
        assertEq(_collateral.balanceOf(address(_pool)),   100 * 1e18);
        assertEq(_quote.balanceOf(address(_pool)),        5_000 * 1e18);
        assertEq(_pool.totalCollateral(),                 100 * 1e18);
        assertEq(_pool.getPoolCollateralization(),        150.544601109894077892249999979 * 1e27);
        assertEq(_pool.getPoolActualUtilization(),        0.285714285714285714285714286 * 1e27);

        assertEq(_pool.hpb(), _p4000);
        assertEq(_pool.lup(), _p3010);

        // check 4_000.927678580567537368 bucket balance before purchase Bid
        (, , , uint256 deposit, uint256 debt, , , uint256 bucketCollateral) = _pool.bucketAt(_p4000);
        assertEq(deposit,          0);
        assertEq(debt,             1_000 * 1e18);
        assertEq(bucketCollateral, 0);

        // check 3_010.892022197881557845 bucket balance before purchase bid
        (, , , deposit, debt, , , bucketCollateral) = _pool.bucketAt(_p3010);
        assertEq(deposit,          0);
        assertEq(debt,             1_000 * 1e18);
        assertEq(bucketCollateral, 0);

        // check 2_000.221618840727700609 bucket balance before purchase bid
        (, , , deposit, debt, , , bucketCollateral) = _pool.bucketAt(_p2000);
        assertEq(deposit,          5_000 * 1e18);
        assertEq(debt,             0);
        assertEq(bucketCollateral, 0);

        // purchase 1000 bid - entire amount in 4000 bucket
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(_bidder), address(_pool), 0.249942033532277153 * 1e18);
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(_pool), address(_bidder), 1_000 * 1e18);
        vm.expectEmit(true, true, false, true);
        emit Purchase(
            address(_bidder),
            _p4000,
            1_000 * 1e18,
            0.249942033532277153 * 1e18
        );
        _bidder.purchaseBid(_pool, 1_000 * 1e18, _p4000);

        assertEq(_pool.hpb(), _p3010); // hbp should be pushed downwards
        assertEq(_pool.lup(), _p2000); // lup should be pushed downwards

        // check 4_000.927678580567537368 bucket balance after purchase Bid
        (, , , deposit, debt, , , bucketCollateral) = _pool.bucketAt(_p4000);
        assertEq(deposit,          0);
        assertEq(debt,             0);
        assertEq(bucketCollateral, 0.249942033532277153 * 1e18);

        // check 3_010.892022197881557845 bucket balance
        (, , , deposit, debt, , , bucketCollateral) = _pool.bucketAt(_p3010);
        assertEq(deposit,          0);
        assertEq(debt,             1_000 * 1e18);
        assertEq(bucketCollateral, 0);

        // check 2_000.221618840727700609 bucket balance
        (, , , deposit, debt, , , bucketCollateral) = _pool.bucketAt(_p2000);
        assertEq(deposit,          4_000 * 1e18);
        assertEq(debt,             1_000 * 1e18);
        assertEq(bucketCollateral, 0);

        // check bidder and pool balances
        assertEq(_collateral.balanceOf(address(_bidder)), 99.750057966467722847 * 1e18);
        assertEq(_quote.balanceOf(address(_bidder)),      1_000 * 1e18);
        assertEq(_collateral.balanceOf(address(_pool)),   100.249942033532277153 * 1e18);
        assertEq(_quote.balanceOf(address(_pool)),        4_000 * 1e18);
        assertEq(_pool.totalCollateral(),                 100 * 1e18);
        assertEq(_pool.getPoolCollateralization(),        100.011080942036385030449999999 * 1e27);
        assertEq(_pool.getPoolActualUtilization(),        0.333333333333333333333333333 * 1e27);

    }

    function testPurchaseBidCannotReallocate() external {
        _lender.addQuoteToken(_pool, address(_lender), 1_000 * 1e18, _p4000);
        _lender.addQuoteToken(_pool, address(_lender), 1_000 * 1e18, _p3010);
        _lender.addQuoteToken(_pool, address(_lender), 500 * 1e18,   _p2000);

        // borrower takes a loan of 1000 DAI from bucket 4000
        _borrower.addCollateral(_pool, 100 * 1e18);
        _borrower.borrow(_pool, 1_000 * 1e18, 3_000 * 1e18);

        // borrower takes a loan of 1000 DAI from bucket 3000
        _borrower.borrow(_pool, 1_000 * 1e18, 3_000 * 1e18);

        assertEq(_pool.lup(), _p3010);

        // should revert if trying to bid more than available liquidity (1000 vs 500)
        vm.expectRevert(Buckets.NoDepositToReallocateTo.selector);
        _bidder.purchaseBid(_pool, 1_000 * 1e18, _p4000);
    }

    // @notice: lender deposits 4000 quote accross 3 buckets
    // @notice: borrower borrows 2000 quote
    // @notice: bidder attempts to purchase 1000 quote, it reverts
    function testPurchaseBidUndercollateralized() external {
        _lender.addQuoteToken(_pool, address(_lender), 1_000 * 1e18, _p4000);
        _lender.addQuoteToken(_pool, address(_lender), 1_000 * 1e18, _p3010);
        _lender.addQuoteToken(_pool, address(_lender), 2_000 * 1e18, _p1);

        // borrower takes a loan of 1000 DAI from bucket 4000
        _borrower.addCollateral(_pool, 100 * 1e18);
        _borrower.borrow(_pool, 1_000 * 1e18, 3_000 * 1e18);

        // borrower takes a loan of 1000 DAI from bucket 3000
        _borrower.borrow(_pool, 1_000 * 1e18, 3_000 * 1e18);

        assertEq(_pool.lup(), _p3010);

        // should revert when leave pool undercollateralized
        vm.expectRevert(
            abi.encodeWithSelector(IPool.PoolUndercollateralized.selector, 0.05 * 1e27)
        );
        _bidder.purchaseBid(_pool, 1_000 * 1e18, _p4000);
    }

}
