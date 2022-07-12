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
        _poolAddress = new ScaledPoolFactory().deployPool(address(_collateral), address(_quote), 0.05 * 10**18);
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

    function testScaledPoolBorrowAndRepay() external {

        uint256 depositPriceHighest = 2550;
        uint256 depositPriceHigh    = 2551;
        uint256 depositPriceMed     = 2552;
        uint256 depositPriceLow     = 2553;
        uint256 depositPriceLowest  = 2554;

        // lender deposits 10000 DAI in 5 buckets each
        _lender.addQuoteToken(_pool, 10_000 * 1e18, depositPriceHighest);
        _lender.addQuoteToken(_pool, 10_000 * 1e18, depositPriceHigh);
        _lender.addQuoteToken(_pool, 10_000 * 1e18, depositPriceMed);
        _lender.addQuoteToken(_pool, 10_000 * 1e18, depositPriceLow);
        _lender.addQuoteToken(_pool, 10_000 * 1e18, depositPriceLowest);

        assertEq(_pool.htp(),      0);
        assertEq(_pool.lupIndex(), 7388);

        assertEq(_pool.treeSum(),            50_000 * 1e18);
        assertEq(_pool.borrowerDebt(),       0);
        assertEq(_pool.lenderDebt(),         0);
        assertEq(_pool.depositAccumulator(), 50_000 * 1e18);

        // check balances
        assertEq(_quote.balanceOf(address(_pool)),   50_000 * 1e18);
        assertEq(_quote.balanceOf(address(_lender)), 150_000 * 1e18);

        // borrower deposit 100 MKR collateral
        _borrower.addCollateral(_pool, 100 * 1e18, address(0), address(0), 1);

        // get a 21_000 DAI loan
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(_pool), address(_borrower), 21_000 * 1e18);
        vm.expectEmit(true, true, false, true);
        emit Borrow(address(_borrower), 2_981.007422784467321543 * 1e18, 21_000 * 1e18);
        _borrower.borrow(_pool, 21_000 * 1e18, 3000, address(0), address(0), 1);

        assertEq(_pool.htp(), 210.201923076923077020 * 1e18);
        assertEq(_pool.lupIndex(), 4836);

        assertEq(_pool.treeSum(),            50_000 * 1e18);
        assertEq(_pool.borrowerDebt(),       21_020.192307692307702000 * 1e18);
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
        emit Borrow(address(_borrower), 2_966.176540084047110076 * 1e18, 19_000 * 1e18);
        _borrower.borrow(_pool, 19_000 * 1e18, 3500, address(0), address(0), 1);

        assertEq(_pool.htp(), 400.384615384615384800 * 1e18);
        assertEq(_pool.lupIndex(), 4835);

        assertEq(_pool.treeSum(),            50_000 * 1e18);
        assertEq(_pool.borrowerDebt(),       40_038.461538461538480000 * 1e18);
        assertEq(_pool.lenderDebt(),         40_000 * 1e18);
        assertEq(_pool.depositAccumulator(), 10_000 * 1e18);

        // check balances
        assertEq(_quote.balanceOf(address(_pool)),   10_000 * 1e18);
        assertEq(_quote.balanceOf(address(_lender)), 150_000 * 1e18);

        // repay partial
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(_borrower), address(_pool), 10_000 * 1e18);
        vm.expectEmit(true, true, false, true);
        emit Repay(address(_borrower), 0.033657201715239149 * 1e18, 10_000 * 1e18);
        _borrower.repay(_pool, 10_000 * 1e18, address(0), address(0), 1);

        assertEq(_pool.htp(), 300.384615384615384800 * 1e18);
        assertEq(_pool.lupIndex(), 4836);

        assertEq(_pool.treeSum(),            50_000 * 1e18);
        assertEq(_pool.borrowerDebt(),       30_038.461538461538480000 * 1e18);
        assertEq(_pool.lenderDebt(),         30_000 * 1e18);
        assertEq(_pool.depositAccumulator(), 10_000 * 1e18);

        // check balances
        assertEq(_quote.balanceOf(address(_pool)),   20_000 * 1e18);
        assertEq(_quote.balanceOf(address(_lender)), 150_000 * 1e18);

        // repay entire loan
        _quote.mint(address(_borrower), 40 * 1e18);
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(_borrower), address(_pool), 30_038.461538461538480000 * 1e18);
        vm.expectEmit(true, true, false, true);
        emit Repay(address(_borrower), 99836282890, 30_038.461538461538480000 * 1e18);
        _borrower.repay(_pool, 30_040 * 1e18, address(0), address(0), 1);

        assertEq(_pool.htp(), 0);
        assertEq(_pool.lupIndex(), 7388);

        assertEq(_pool.treeSum(),            50_000 * 1e18);
        assertEq(_pool.borrowerDebt(),       0);
        assertEq(_pool.lenderDebt(),         0);
        assertEq(_pool.depositAccumulator(), 10_000 * 1e18);

        // check balances
        assertEq(_quote.balanceOf(address(_pool)),   50_038.461538461538480000 * 1e18);
        assertEq(_quote.balanceOf(address(_lender)), 150_000 * 1e18);

    }

}
