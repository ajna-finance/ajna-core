// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.14;

import { ERC20Pool }        from "../../erc20/ERC20Pool.sol";
import { ERC20PoolFactory } from "../../erc20/ERC20PoolFactory.sol";

import { BucketMath } from "../../libraries/BucketMath.sol";
import { Maths }      from "../../libraries/Maths.sol";


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
    UserWithQuoteToken internal _lender;
    UserWithQuoteToken internal _lender1;
    UserWithCollateral internal _bidder;

    function setUp() external {
        _collateral  = new CollateralToken();
        _quote       = new QuoteToken();
        _poolAddress = new ERC20PoolFactory().deployPool(address(_collateral), address(_quote), 0.05 * 10**18);
        _pool        = ERC20Pool(_poolAddress);

        _borrower   = new UserWithCollateral();
        _bidder     = new UserWithCollateral();
        _lender     = new UserWithQuoteToken();
        _lender1    = new UserWithQuoteToken();

        _collateral.mint(address(_bidder), 100 * 1e18);
        _collateral.mint(address(_borrower), 100 * 1e18);

        _quote.mint(address(_lender), 200_000 * 1e18);
        _quote.mint(address(_lender1), 200_000 * 1e18);

        _borrower.approveToken(_collateral, address(_pool), 100 * 1e18);
        _borrower.approveToken(_quote,      address(_pool), 200_000 * 1e18);

        _bidder.approveToken(_quote,  address(_pool), 200_000 * 1e18);
        _bidder.approveToken(_collateral, address(_pool), 100 * 1e18);

        _lender.approveToken(_quote,  address(_pool), 200_000 * 1e18);
        _lender.approveToken(_collateral, address(_pool), 100 * 1e18);
        _lender1.approveToken(_quote, address(_pool), 200_000 * 1e18);
    }

    /**
     *  @notice 1 lender, 1 bidder tests purchasing quote token with collateral.
     */
    function testPurchaseQuote() external {
        // test setup
        uint256 testIndex = 2550;
        uint256 priceAtTestIndex = _pool.indexToPrice(testIndex);
        assertEq(priceAtTestIndex, 3_010.892022197881557845 * 1e18);

        // lender adds initial quote to pool
        _lender.addQuoteToken(_pool, 10_000 * 1e18, testIndex);

        // bidder deposits collateral into a bucket
        uint256 collateralToPurchaseWith = 4 * 1e18;
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(_bidder), address(_pool), collateralToPurchaseWith);
        vm.expectEmit(true, true, false, true);
        emit AddCollateral(address(_bidder), priceAtTestIndex, collateralToPurchaseWith);
        _bidder.addCollateral(_pool, collateralToPurchaseWith, testIndex);

        // check bucket state
        (uint256 lpAccumulator, uint256 availableCollateral) = _pool.buckets(testIndex);
        assertEq(availableCollateral, collateralToPurchaseWith);
        assertEq(_pool.lpBalance(testIndex, address(_lender)), 10_000 * 1e27);
        assertEq(_pool.lpBalance(testIndex, address(_bidder)), 12_043.56808879152623138 * 1e27);

        // bidder uses their LP to purchase all quote token in the bucket
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(_pool), address(_bidder), 10_000 * 1e18);
        vm.expectEmit(true, true, false, true);
        emit RemoveQuoteToken(address(_bidder), priceAtTestIndex, 10_000 * 1e18, _pool.lup());
        _bidder.removeQuoteToken(_pool, 10_000 * 1e18, testIndex);
        assertEq(_quote.balanceOf(address(_bidder)), 10_000 * 1e18);

        // check bucket state
        (lpAccumulator, availableCollateral) = _pool.buckets(testIndex);
        assertEq(availableCollateral, collateralToPurchaseWith);
        assertGt(availableCollateral, 0);
        assertEq(_pool.lpBalance(testIndex, address(_lender)), 10_000 * 1e27);
        assertEq(_pool.lpBalance(testIndex, address(_bidder)), 2_043.56808879152623138 * 1e27);

        // check pool state and balances
        assertEq(_collateral.balanceOf(address(_lender)), 0);
        assertEq(_collateral.balanceOf(address(_pool)),   collateralToPurchaseWith);
        assertGe(_collateral.balanceOf(address(_pool)), availableCollateral);
        assertEq(_quote.balanceOf(address(_pool)),        0);

        // lender exchanges their LP for collateral
        uint256 lpBalance = _pool.lpBalance(testIndex, address(_lender));
        uint256 lpValueInCollateral = 3.321274866808485288 * 1e18;
        vm.expectEmit(true, true, true, true);
        emit Transfer(address(_pool), address(_lender), lpValueInCollateral);
        vm.expectEmit(true, true, true, true);
        emit RemoveCollateral(address(_lender), priceAtTestIndex, lpValueInCollateral, lpBalance);
        _lender.removeCollateral(_pool, availableCollateral, testIndex);
        assertEq(_collateral.balanceOf(address(_lender)), lpValueInCollateral);
        assertEq(_pool.lpBalance(testIndex, address(_lender)), 0);

        // bidder removes their _collateral
        vm.expectEmit(true, true, true, true);
        emit Transfer(address(_pool), address(_bidder), 0.678725133191514712 * 1e18);
        vm.expectEmit(true, true, true, true);
        emit RemoveCollateral(
            address(_bidder),
            priceAtTestIndex,
            0.678725133191514712 * 1e18,
            2_043.568088791526231380000000000 * 1e27
        );
        _bidder.removeCollateral(_pool, collateralToPurchaseWith, testIndex);
        assertEq(_pool.lpBalance(testIndex, address(_bidder)), 0);

        // check pool balances
        assertEq(_collateral.balanceOf(address(_pool)), 0);
        assertEq(_quote.balanceOf(address(_pool)),      0);

        // check bucket state
        (lpAccumulator, availableCollateral) = _pool.buckets(testIndex);
        assertEq(lpAccumulator,        0);
        assertEq(availableCollateral,  0);
        assertEq(_pool.get(testIndex), 0);
    }

    /**
     *  @notice 2 lenders, 1 borrower, 1 bidder tests purchasing quote token with collateral.
     */
    function testPurchaseQuoteWithDebt() external {
        uint256 p2550 = _pool.indexToPrice(2550);
        assertEq(p2550, 3_010.892022197881557845 * 1e18);

        // lenders add liquidity
        _lender.addQuoteToken(_pool, 6_000 * 1e18, 2550);
        _lender1.addQuoteToken(_pool, 4_000 * 1e18, 2550);
        _lender.addQuoteToken(_pool, 10_000 * 1e18, 2551);
        _lender.addQuoteToken(_pool, 5_000 * 1e18, 2552);
        _lender1.addQuoteToken(_pool, 5_000 * 1e18, 2552);
        skip(3600);

        // borrower draws debt
        _borrower.pledgeCollateral(_pool, 100 * 1e18, address(0), address(0));
        _borrower.borrow(_pool, 15_000 * 1e18, 3000, address(0), address(0));
        assertEq(_pool.lup(), _pool.indexToPrice(2551));
        skip(86400);

        // check pool balances
        assertEq(_collateral.balanceOf(address(_pool)), 100 * 1e18);
        assertEq(_quote.balanceOf(address(_pool)),      15_000 * 1e18);

        // bidder purchases most of the quote from the highest bucket
        uint256 amountToPurchase = 10_100 * 1e18;
        assertGt(_quote.balanceOf(address(_pool)), amountToPurchase);
        uint256 amountWithInterest = 10_000.642786573656600000 * 1e18;
        // adding extra collateral to account for interest accumulation
        uint256 collateralToPurchaseWith = Maths.wmul(Maths.wdiv(amountToPurchase, p2550), 1.01 * 1e18);
        _bidder.addCollateral(_pool, collateralToPurchaseWith, 2550);
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(_pool), address(_bidder), amountWithInterest);
        vm.expectEmit(true, true, false, true);
        emit RemoveQuoteToken(address(_bidder), p2550, amountWithInterest, _pool.indexToPrice(2552));
        _bidder.removeQuoteToken(_pool, amountToPurchase, 2550);
        assertEq(_quote.balanceOf(address(_bidder)), amountWithInterest);
        // bidder withdraws excess collateral
        _bidder.removeCollateral(_pool, collateralToPurchaseWith, 2550);
        assertEq(_pool.lpBalance(p2550, address(_lender)), 0);
        skip(7200);

        // lender exchanges their LP for collateral
        uint256 lpBalance = _pool.lpBalance(2550, address(_lender));
        vm.expectEmit(true, true, true, true);
        emit Transfer(address(_pool), address(_lender), 1.992631704391065311 * 1e18);
        vm.expectEmit(true, true, true, true);
        emit RemoveCollateral(address(_lender), p2550, 1.992631704391065311 * 1e18, lpBalance);
        _lender.removeCollateral(_pool, 4 * 1e18, 2550);
        assertEq(_pool.lpBalance(p2550, address(_lender)), 0);
        skip(3600);

        // lender1 exchanges their LP for collateral
        lpBalance = _pool.lpBalance(2550, address(_lender1));
        vm.expectEmit(true, true, true, true);
        emit Transfer(address(_pool), address(_lender1), 1.328154785003044376 * 1e18);
        vm.expectEmit(true, true, true, true);
        emit RemoveCollateral(address(_lender1), p2550, 1.328154785003044376 * 1e18, lpBalance);
        _lender1.removeCollateral(_pool, 4 * 1e18, 2550);
        assertEq(_pool.lpBalance(p2550, address(_lender1)), 0);

        // check pool balances
        // FIXME: pool should only have collateral pledged by borrower
//        assertEq(_collateral.balanceOf(address(_pool)), 100 * 1e18);

        // check bucket state
        (uint256 lpAccumulator, uint256 availableCollateral) = _pool.buckets(2550);
//        assertEq(availableCollateral,  0);    // FIXME: extra collateral was left in bucket
        assertEq(lpAccumulator,        0);
        assertEq(_pool.get(2550), 0);
    }
}
