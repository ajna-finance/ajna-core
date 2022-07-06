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

        uint256 depositPriceHighest = _pool.priceToIndex(_p4000);
        uint256 depositPriceHigh    = _pool.priceToIndex(_p3514);
        uint256 depositPriceMed     = _pool.priceToIndex(_p3010);
        uint256 depositPriceLow     = _pool.priceToIndex(_p2503);
        uint256 depositPriceLowest  = _pool.priceToIndex(_p2000);

        // lender deposits 10000 DAI in 5 buckets each
        _lender.addQuoteToken(_pool, 10_000 * 1e18, depositPriceHighest);
        _lender.addQuoteToken(_pool, 10_000 * 1e18, depositPriceHigh);
        _lender.addQuoteToken(_pool, 10_000 * 1e18, depositPriceMed);
        _lender.addQuoteToken(_pool, 10_000 * 1e18, depositPriceLow);
        _lender.addQuoteToken(_pool, 10_000 * 1e18, depositPriceLowest);

        assertEq(_pool.htp(), 0);
        assertEq(_pool.lup(), 0.000000099836282890 * 1e18);

        assertEq(_pool.treeSum(),            50_000 * 1e18);
        assertEq(_pool.lenderDebt(),         0);
        assertEq(_pool.depositAccumulator(), 50_000 * 1e18);

        // check balances
        assertEq(_quote.balanceOf(address(_pool)),   50_000 * 1e18);
        assertEq(_quote.balanceOf(address(_lender)), 150_000 * 1e18);

        // borrower deposit 100 MKR collateral
        _borrower.addCollateral(_pool, 100 * 1e18);

        // get a 21_000 DAI loan
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(_pool), address(_borrower), 21_000 * 1e18);
        vm.expectEmit(true, true, false, true);
        emit Borrow(address(_borrower), priceMed, 21_000 * 1e18);
        _borrower.borrow(_pool, 21_000 * 1e18, address(0), address(0));

        assertEq(_pool.htp(), 0.201923076923077020 * 1e18);
        assertEq(_pool._lupIndex(0), 4838);
        assertEq(_pool.lup(), priceMed);

        assertEq(_pool.treeSum(),            50_000 * 1e18);
        assertEq(_pool.lenderDebt(),         21_000 * 1e18);
        assertEq(_pool.depositAccumulator(), 29_000 * 1e18);

        // check balances
        assertEq(_quote.balanceOf(address(_pool)),   29_000 * 1e18);
        assertEq(_quote.balanceOf(address(_lender)), 150_000 * 1e18);

        // check LPs
        assertEq(_pool.lpBalance(depositPriceHighest, address(_lender)), 10_000 * 1e18);
        assertEq(_pool.lpBalance(depositPriceHigh, address(_lender)),    10_000 * 1e18);
        assertEq(_pool.lpBalance(depositPriceMed, address(_lender)),     10_000 * 1e18);
        assertEq(_pool.lpBalance(depositPriceLow, address(_lender)),     10_000 * 1e18);
        assertEq(_pool.lpBalance(depositPriceLowest, address(_lender)),  10_000 * 1e18);

        // check buckets
        (uint256 lpAccumulator, uint256 availableCollateral) = _pool.buckets(depositPriceHighest);
        assertEq(lpAccumulator,       10_000 * 1e18);
        assertEq(availableCollateral, 0);
        (lpAccumulator, availableCollateral) = _pool.buckets(depositPriceHigh);
        assertEq(lpAccumulator,       10_000 * 1e18);
        assertEq(availableCollateral, 0);
        (lpAccumulator, availableCollateral) = _pool.buckets(depositPriceMed);
        assertEq(lpAccumulator,       10_000 * 1e18);
        assertEq(availableCollateral, 0);
        (lpAccumulator, availableCollateral) = _pool.buckets(depositPriceLow);
        assertEq(lpAccumulator,       10_000 * 1e18);
        assertEq(availableCollateral, 0);
        (lpAccumulator, availableCollateral) = _pool.buckets(depositPriceLowest);
        assertEq(lpAccumulator,       10_000 * 1e18);
        assertEq(availableCollateral, 0);

        // borrow 19_000 DAI
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(_pool), address(_borrower), 19_000 * 1e18);
        vm.expectEmit(true, true, false, true);
        emit Borrow(address(_borrower), priceHigh, 19_000 * 1e18);
        _borrower.borrow(_pool, 19_000 * 1e18, address(0), address(0));

        assertEq(_pool.htp(), 0.384615384615384800 * 1e18);
        assertEq(_pool._lupIndex(0), 4869);
        assertEq(_pool.lup(), priceHigh);

        assertEq(_pool.treeSum(),            50_000 * 1e18);
        assertEq(_pool.lenderDebt(),         40_000 * 1e18);
        assertEq(_pool.depositAccumulator(), 10_000 * 1e18);

        // check balances
        assertEq(_quote.balanceOf(address(_pool)),   10_000 * 1e18);
        assertEq(_quote.balanceOf(address(_lender)), 150_000 * 1e18);
    }

}
