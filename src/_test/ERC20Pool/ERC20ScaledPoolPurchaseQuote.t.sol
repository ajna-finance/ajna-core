// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.14;

import { ERC20Pool }        from "../../erc20/ERC20Pool.sol";
import { ERC20PoolFactory } from "../../erc20/ERC20PoolFactory.sol";

import { BucketMath } from "../../libraries/BucketMath.sol";

import { DSTestPlus }                             from "../utils/DSTestPlus.sol";
import { CollateralToken, QuoteToken }            from "../utils/Tokens.sol";
import { UserWithCollateral, UserWithQuoteToken } from "../utils/Users.sol";

contract ERC20ScaledPurchaseQuoteTokenTest is DSTestPlus {

    uint256 public constant LARGEST_AMOUNT = type(uint256).max / 10**27;

    address            internal _poolAddress;
    CollateralToken    internal _collateral;
    ERC20Pool          internal _pool;
    QuoteToken         internal _quote;
    UserWithCollateral internal _borrower;
    UserWithCollateral internal _borrower2;
    UserWithQuoteToken internal _lender;
    UserWithQuoteToken internal _lender1;

    function setUp() external {
        _collateral  = new CollateralToken();
        _quote       = new QuoteToken();
        _poolAddress = new ERC20PoolFactory().deployPool(address(_collateral), address(_quote), 0.05 * 10**18);
        _pool        = ERC20Pool(_poolAddress);

        _borrower   = new UserWithCollateral();
        _borrower2  = new UserWithCollateral();
        _lender     = new UserWithQuoteToken();
        _lender1    = new UserWithQuoteToken();

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

        _borrower.addCollateral(_pool, 100 * 1e18, address(0), address(0));
        _borrower.borrow(_pool, 21_000 * 1e18, 3000, address(0), address(0));

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

        _borrower.repay(_pool, 10_000 * 1e18, address(0), address(0));

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

    /**
     *  @notice 1 lender, 1 bidder tests reverts in purchaseQuote.
     *          Reverts:
     *              Attempts to purchase more quote than is available in the bucket.
     *              Attempts to purchase without sufficient collateral.
     */
    function testScaledPoolPurchaseQuoteTokenRequireChecks() external {
        // test setup
        uint256 testIndex = 2550;
        uint256 priceAtTestIndex = _pool.indexToPrice(testIndex);

        // lender adds initial quote to pool
        _lender.addQuoteToken(_pool, 10_000 * 1e18, 2550);

        // should revert if no there is an attempt to purchase more quote than is available in the bucket
        vm.expectRevert("S:P:INSUF_QUOTE");
        _lender1.purchaseQuote(_pool, 20_000 * 1e18, testIndex);

        // should revert if lender has insufficient collateral
        vm.expectRevert("S:P:INSUF_COL");
        _lender1.purchaseQuote(_pool, 10_000 * 1e18, testIndex);

        // mint and approve collateral to allow lender1 to bid
        _collateral.mint(address(_lender1), 100 * 1e18);
        _lender1.approveToken(_collateral, address(_pool), 100 * 1e18);

        // should be able to purchase quote with collateral if properly specified
        uint256 collateralToPurchaseWith = 3.321274866808485288 * 1e18;
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(_lender1), address(_pool), collateralToPurchaseWith);
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(_pool), address(_lender1), 10_000 * 1e18);
        vm.expectEmit(true, true, false, true);
        emit Purchase(address(_lender1), priceAtTestIndex, 10_000 * 1e18, collateralToPurchaseWith);
        _lender1.purchaseQuote(_pool, 10_000 * 1e18, testIndex);
    }


}
