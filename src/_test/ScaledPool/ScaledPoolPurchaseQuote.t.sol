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

        _collateral.mint(address(_lender), 100 * 1e18);
        _collateral.mint(address(_borrower), 100 * 1e18);
        _collateral.mint(address(_borrower2), 200 * 1e18);

        _quote.mint(address(_lender), 200_000 * 1e18);
        _quote.mint(address(_lender1), 200_000 * 1e18);

        _borrower.approveToken(_collateral, address(_pool), 100 * 1e18);
        _borrower.approveToken(_quote,      address(_pool), 200_000 * 1e18);

        _borrower2.approveToken(_collateral, address(_pool), 200 * 1e18);
        _borrower2.approveToken(_quote,      address(_pool), 200_000 * 1e18);

        _lender.approveToken(_quote,  address(_pool), 200_000 * 1e18);
        _lender.approveToken(_collateral, address(_pool), 100 * 1e18);
        _lender1.approveToken(_quote, address(_pool), 200_000 * 1e18);
    }

    function testScaledPoolPurchaseQuoteClaimCollateral() external {

        // lender deposits 10000 DAI in 5 buckets each
        _lender.addQuoteToken(_pool, 10_000 * 1e18, 2550);
        _lender.addQuoteToken(_pool, 10_000 * 1e18, 2551);
        _lender.addQuoteToken(_pool, 10_000 * 1e18, 2552);
        _lender.addQuoteToken(_pool, 10_000 * 1e18, 2553);
        _lender.addQuoteToken(_pool, 10_000 * 1e18, 2554);

        _borrower.addCollateral(_pool, 100 * 1e18, address(0), address(0), 1);
        _borrower.borrow(_pool, 21_000 * 1e18, 3000, address(0), address(0), 1);

        // check balances
        assertEq(_quote.balanceOf(address(_lender)),   150_000 * 1e18);
        assertEq(_collateral.balanceOf(address(_lender)), 100 * 1e18);

        vm.expectEmit(true, true, false, true);
        emit Transfer(address(_lender), address(_pool), 3.321274866808485288 * 1e18);
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(_pool), address(_lender), 10_000 * 1e18);
        vm.expectEmit(true, true, false, true);
        emit Purchase(address(_lender), 3_010.892022197881557845 * 1e18, 10_000 * 1e18, 3.321274866808485288 * 1e18);
        _lender.purchaseQuote(_pool, 10_000 * 1e18, 2550);

        // check balances
        assertEq(_quote.balanceOf(address(_lender)),      160_000 * 1e18);
        assertEq(_collateral.balanceOf(address(_lender)), 96.678725133191514712 * 1e18);

        vm.expectEmit(true, true, false, true);
        emit Transfer(address(_lender), address(_pool), 0.333788124114252769 * 1e18);
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(_pool), address(_lender), 1_000 * 1e18);
        vm.expectEmit(true, true, false, true);
        emit Purchase(address(_lender), 2_995.912459898389633881 * 1e18, 1_000 * 1e18, 0.333788124114252769 * 1e18);
        _lender.purchaseQuote(_pool, 1_000 * 1e18, 2551);

        // check balances
        assertEq(_quote.balanceOf(address(_lender)),      161_000 * 1e18);
        assertEq(_collateral.balanceOf(address(_lender)), 96.344937009077261943 * 1e18);

        assertEq(_quote.balanceOf(address(_pool)),      18_000 * 1e18);
        assertEq(_collateral.balanceOf(address(_pool)), 103.655062990922738057 * 1e18);

        _borrower.repay(_pool, 10_000 * 1e18, address(0), address(0), 1);

        (uint256 lpAccumulator, uint256 availableCollateral) = _pool.buckets(2550);
        assertEq(lpAccumulator,       10_000 * 1e27);
        assertEq(availableCollateral, 3.321274866808485288 * 1e18);

        vm.expectEmit(true, true, false, true);
        emit Transfer(address(_pool), address(_lender), availableCollateral);
        vm.expectEmit(true, true, false, true);
        emit ClaimCollateral(address(_lender), 3_010.892022197881557845 * 1e18, availableCollateral, 10_000 * 1e27);
        _lender.claimCollateral(_pool, availableCollateral, 2550);

        // check balances
        assertEq(_quote.balanceOf(address(_lender)),      161_000 * 1e18);
        assertEq(_collateral.balanceOf(address(_lender)), 99.666211875885747231 * 1e18);

        assertEq(_quote.balanceOf(address(_pool)),      28_000 * 1e18);
        assertEq(_collateral.balanceOf(address(_pool)), 100.333788124114252769 * 1e18);

    }

}
