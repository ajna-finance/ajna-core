// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.14;

import { ERC20Pool }        from "../../erc20/ERC20Pool.sol";
import { ERC20PoolFactory } from "../../erc20/ERC20PoolFactory.sol";

import { BucketMath } from "../../libraries/BucketMath.sol";
import { Maths }      from "../../libraries/Maths.sol";

import { ERC20DSTestPlus }             from "./ERC20DSTestPlus.sol";
import { CollateralToken, QuoteToken } from "../utils/Tokens.sol";

contract ERC20ScaledPurchaseQuoteTokenTest is ERC20DSTestPlus {

    uint256 public constant LARGEST_AMOUNT = type(uint256).max / 10**27;

    address internal _borrower;
    address internal _bidder;
    address internal _lender;
    address internal _lender1;

    CollateralToken internal _collateral;
    QuoteToken      internal _quote;
    ERC20Pool       internal _pool;

    function setUp() external {
        _collateral = new CollateralToken();
        _quote      = new QuoteToken();
        _pool       = ERC20Pool(new ERC20PoolFactory().deployPool(address(_collateral), address(_quote), 0.05 * 10**18));

        _borrower = makeAddr("borrower");
        _bidder   = makeAddr("bidder");
        _lender   = makeAddr("lender");
        _lender1  = makeAddr("lender1");

        deal(address(_collateral), _borrower,  100 * 1e18);
        deal(address(_collateral), _bidder, 100 * 1e18);

        deal(address(_quote), _lender,  200_000 * 1e18);
        deal(address(_quote), _lender1, 200_000 * 1e18);

        vm.startPrank(_borrower);
        _collateral.approve(address(_pool), 100 * 1e18);
        _quote.approve(address(_pool), 200_000 * 1e18);

        changePrank(_bidder);
        _collateral.approve(address(_pool), 100 * 1e18);
        _quote.approve(address(_pool), 200_000 * 1e18);

        changePrank(_lender);
        _quote.approve(address(_pool), 200_000 * 1e18);

        changePrank(_lender1);
        _quote.approve(address(_pool), 200_000 * 1e18);
        _collateral.approve(address(_pool), 100 * 1e18);
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
        changePrank(_lender);
        _pool.addQuoteToken(10_000 * 1e18, testIndex);

        // bidder deposits collateral into a bucket
        changePrank(_bidder);
        uint256 collateralToPurchaseWith = 4 * 1e18;
        vm.expectEmit(true, true, false, true);
        emit AddCollateral(_bidder, priceAtTestIndex, collateralToPurchaseWith);
        vm.expectEmit(true, true, false, true);
        emit Transfer(_bidder, address(_pool), collateralToPurchaseWith);
        _pool.addCollateral(collateralToPurchaseWith, testIndex);

        // check bucket state
        (uint256 lpAccumulator, uint256 availableCollateral) = _pool.buckets(testIndex);
        assertEq(availableCollateral, collateralToPurchaseWith);
        (uint256 lpBalance, ) = _pool.bucketLenders(testIndex, _lender);
        assertEq(lpBalance, 10_000 * 1e27);
        (lpBalance, ) = _pool.bucketLenders(testIndex, _bidder);
        assertEq(lpBalance, 12_043.56808879152623138 * 1e27);

        // bidder uses their LP to purchase all quote token in the bucket
        vm.expectEmit(true, true, false, true);
        emit RemoveQuoteToken(_bidder, priceAtTestIndex, 10_000 * 1e18, _pool.lup());
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(_pool), _bidder, 10_000 * 1e18);
        _pool.removeQuoteToken(10_000 * 1e18, testIndex);
        assertEq(_quote.balanceOf(_bidder), 10_000 * 1e18);

        // check bucket state
        (lpAccumulator, availableCollateral) = _pool.buckets(testIndex);
        assertEq(availableCollateral, collateralToPurchaseWith);
        assertGt(availableCollateral, 0);
        (lpBalance, ) = _pool.bucketLenders(testIndex, _lender);
        assertEq(lpBalance, 10_000 * 1e27);
        (lpBalance, ) = _pool.bucketLenders(testIndex, _bidder);
        assertEq(lpBalance, 2_043.56808879152623138 * 1e27);

        // check pool state and balances
        assertEq(_collateral.balanceOf(_lender), 0);
        assertEq(_collateral.balanceOf(address(_pool)),   collateralToPurchaseWith);
        assertGe(_collateral.balanceOf(address(_pool)), availableCollateral);
        assertEq(_quote.balanceOf(address(_pool)),        0);

        // lender exchanges their LP for collateral
        changePrank(_lender);
        uint256 lpValueInCollateral = 3.321274866808485288 * 1e18;
        vm.expectEmit(true, true, true, true);
        emit RemoveCollateral(_lender, priceAtTestIndex, lpValueInCollateral);
        vm.expectEmit(true, true, true, true);
        emit Transfer(address(_pool), _lender, lpValueInCollateral);
        _pool.removeAllCollateral(testIndex);
        assertEq(_collateral.balanceOf(_lender), lpValueInCollateral);
        (lpBalance, ) = _pool.bucketLenders(testIndex, _lender);
        assertEq(lpBalance, 0);

        // bidder removes their _collateral
        changePrank(_bidder);
        vm.expectEmit(true, true, true, true);
        emit RemoveCollateral(_bidder, priceAtTestIndex, 0.678725133191514712 * 1e18);
        vm.expectEmit(true, true, true, true);
        emit Transfer(address(_pool), _bidder, 0.678725133191514712 * 1e18);
        _pool.removeAllCollateral(testIndex);
        (lpBalance, ) = _pool.bucketLenders(testIndex, _bidder);
        assertEq(lpBalance, 0);

        // check pool balances
        assertEq(_collateral.balanceOf(address(_pool)), 0);
        assertEq(_quote.balanceOf(address(_pool)),      0);

        // check bucket state
        (lpAccumulator, availableCollateral) = _pool.buckets(testIndex);
        assertEq(lpAccumulator,              0);
        assertEq(availableCollateral,        0);
        assertEq(_pool.depositAt(testIndex), 0);
    }

    /**
     *  @notice 2 lenders, 1 borrower, 1 bidder tests purchasing quote token with collateral.
     */
    function testPurchaseQuoteWithDebt() external {
        uint256 p2550 = _pool.indexToPrice(2550);
        assertEq(p2550, 3_010.892022197881557845 * 1e18);

        // lenders add liquidity
        changePrank(_lender);
        _pool.addQuoteToken(6_000 * 1e18, 2550);
        _pool.addQuoteToken(10_000 * 1e18, 2551);
        _pool.addQuoteToken(5_000 * 1e18, 2552);

        changePrank(_lender1);
        _pool.addQuoteToken(4_000 * 1e18, 2550);
        _pool.addQuoteToken(5_000 * 1e18, 2552);
        skip(3600);

        // borrower draws debt
        changePrank(_borrower);
        _pool.pledgeCollateral(_borrower, 100 * 1e18, address(0), address(0));
        _pool.borrow(15_000 * 1e18, 3000, address(0), address(0));
        assertEq(_pool.lup(), _pool.indexToPrice(2551));
        skip(86400);

        // check pool balances
        assertEq(_collateral.balanceOf(address(_pool)), 100 * 1e18);
        assertEq(_quote.balanceOf(address(_pool)),      15_000 * 1e18);

        // bidder purchases all quote from the highest bucket
        changePrank(_bidder);
        uint256 amountToPurchase = 10_100 * 1e18;
        assertGt(_quote.balanceOf(address(_pool)), amountToPurchase);
        uint256 amountWithInterest = 10_000.642786573732910000 * 1e18;
        // adding extra collateral to account for interest accumulation
        uint256 collateralToPurchaseWith = Maths.wmul(Maths.wdiv(amountToPurchase, p2550), 1.01 * 1e18);
        assertEq(collateralToPurchaseWith, 3.388032491631335842 * 1e18);
        _pool.addCollateral(collateralToPurchaseWith, 2550);
        vm.expectEmit(true, true, false, true);
        emit RemoveQuoteToken(_bidder, p2550, amountWithInterest, _pool.indexToPrice(2552));
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(_pool), _bidder, amountWithInterest);
        _pool.removeAllQuoteToken(2550);
        assertEq(_quote.balanceOf(_bidder), amountWithInterest);
        // bidder withdraws unused collateral
        uint256 collateralRemoved = 0;
        uint256 expectedCollateral = 0.066544137733644449 * 1e18;
        vm.expectEmit(true, true, true, true);
        emit RemoveCollateral(_bidder, p2550, expectedCollateral);
        (uint256 amount, ) = _pool.removeAllCollateral(2550);
        assertEq(amount, expectedCollateral);
        collateralRemoved += expectedCollateral;
        (uint256 lpBalance, ) = _pool.bucketLenders(2550, _bidder);
        assertEq(lpBalance, 0);
        skip(7200);

        // lender exchanges their LP for collateral
        changePrank(_lender);
        expectedCollateral = 1.992893012338614836 * 1e18;
        vm.expectEmit(true, true, true, true);
        emit RemoveCollateral(_lender, p2550, expectedCollateral);
        (amount, ) = _pool.removeAllCollateral(2550);
        assertEq(amount, expectedCollateral);
        collateralRemoved += expectedCollateral;
        (lpBalance, ) = _pool.bucketLenders(2550, _lender);
        assertEq(lpBalance, 0);
        skip(3600);

        // lender1 exchanges their LP for collateral
        changePrank(_lender1);
        expectedCollateral = 1.328595341559076557 * 1e18;
        vm.expectEmit(true, true, true, true);
        emit RemoveCollateral(_lender1, p2550, expectedCollateral);
        (amount, ) = _pool.removeAllCollateral(2550);
        assertEq(amount, expectedCollateral);
        collateralRemoved += expectedCollateral;
        (lpBalance, ) = _pool.bucketLenders(2550, _lender1);
        assertEq(lpBalance, 0);
        assertEq(collateralRemoved, collateralToPurchaseWith);

        // check pool balances
        assertEq(_collateral.balanceOf(address(_pool)), 100 * 1e18);

        // check bucket state
        (uint256 lpAccumulator, uint256 availableCollateral) = _pool.buckets(2550);
        assertEq(availableCollateral,   0);
        assertEq(lpAccumulator,         0);
        assertEq(_pool.depositAt(2550), 0);
    }
}
