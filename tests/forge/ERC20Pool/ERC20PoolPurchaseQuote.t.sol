// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.14;

import { ERC20HelperContract } from './ERC20DSTestPlus.sol';

import 'src/libraries/helpers/PoolHelper.sol';

contract ERC20PoolPurchaseQuoteTokenTest is ERC20HelperContract {

    address internal _borrower;
    address internal _bidder;
    address internal _lender;
    address internal _lender1;

    function setUp() external {
        _borrower = makeAddr("borrower");
        _bidder   = makeAddr("bidder");
        _lender   = makeAddr("lender");
        _lender1  = makeAddr("lender1");

        _mintCollateralAndApproveTokens(_borrower,   100 * 1e18);
        _mintCollateralAndApproveTokens(_bidder,     100 * 1e18);

        _mintQuoteAndApproveTokens(_lender,   200_000 * 1e18);
        _mintQuoteAndApproveTokens(_lender1,  200_000 * 1e18);
    }

    /**
     *  @notice 1 lender, 1 bidder tests purchasing quote token with collateral.
     */
    function testPurchaseQuote() external tearDown {
        // test setup
        uint256 testIndex = 2550;

        // lender adds initial quote to pool
        _addInitialLiquidity(
            {
                from:   _lender,
                amount: 10_000 * 1e18,
                index:  testIndex
            }
        );

        // bidder deposits collateral into a bucket
        uint256 collateralToPurchaseWith = 4 * 1e18;
        _addCollateral(
            {
                from:    _bidder,
                amount:  collateralToPurchaseWith,
                index:   testIndex,
                lpAward: 12_043.56808879152623138 * 1e27
            }
        );

        // check bucket state and LPs
        _assertBucket(
            {
                index:        testIndex,
                lpBalance:    22_043.56808879152623138 * 1e27,
                collateral:   collateralToPurchaseWith,
                deposit:      10_000 * 1e18,
                exchangeRate: 1 * 1e27
            }
        );
        _assertLenderLpBalance(
            {
                lender:      _lender,
                index:       testIndex,
                lpBalance:   10_000 * 1e27,
                depositTime: _startTime
            }
        );
        _assertLenderLpBalance(
            {
                lender:      _bidder,
                index:       testIndex,
                lpBalance:   12_043.56808879152623138 * 1e27,
                depositTime: _startTime
            }
        );

        uint256 availableCollateral = collateralToPurchaseWith;

        skip(1 days); // skip to avoid penalty
        // bidder uses their LP to purchase all quote token in the bucket
        _removeLiquidity(
            {
                from:     _bidder,
                amount:   10_000 * 1e18,
                index:    testIndex,
                newLup:   _lup(),
                lpRedeem: 10_000 * 1e27
            }
        );
        assertEq(_quote.balanceOf(_bidder), 10_000 * 1e18);

        // check bucket state
        _assertBucket(
            {
                index:        testIndex,
                lpBalance:    12_043.56808879152623138 * 1e27,
                collateral:   collateralToPurchaseWith,
                deposit:      0,
                exchangeRate: 1 * 1e27
            }
        );
        _assertLenderLpBalance(
            {
                lender:      _lender,
                index:       testIndex,
                lpBalance:   10_000 * 1e27,
                depositTime: _startTime
            }
        );
        _assertLenderLpBalance(
            {
                lender:      _bidder,
                index:       testIndex,
                lpBalance:   2_043.56808879152623138 * 1e27,
                depositTime: _startTime
            }
        );

        // check pool state and balances
        assertEq(_collateral.balanceOf(_lender),        0);
        assertEq(_collateral.balanceOf(address(_pool)), collateralToPurchaseWith);
        assertGe(_collateral.balanceOf(address(_pool)), availableCollateral);
        assertEq(_quote.balanceOf(address(_pool)),      0);

        // lender exchanges their LP for collateral
        _removeAllCollateral(
            {
                from: _lender,
                amount: 3.321274866808485288 * 1e18,
                index: testIndex,
                lpRedeem: 10_000 * 1e27
            }
        );

        _assertBucket(
            {
                index:        testIndex,
                lpBalance:    2_043.56808879152623138 * 1e27,
                collateral:   0.678725133191514712 * 1e18,
                deposit:      0,
                exchangeRate: 0.999999999999999999892795209 * 1e27
            }
        );
        _assertLenderLpBalance(
            {
                lender:      _lender,
                index:       testIndex,
                lpBalance:   0,
                depositTime: _startTime
            }
        );
        _assertLenderLpBalance(
            {
                lender:      _bidder,
                index:       testIndex,
                lpBalance:   2_043.56808879152623138 * 1e27,
                depositTime: _startTime
            }
        );

        assertEq(_collateral.balanceOf(_lender), 3.321274866808485288 * 1e18);

        // bidder removes their _collateral
        _removeAllCollateral(
            {
                from: _bidder,
                amount: 0.678725133191514712 * 1e18,
                index: testIndex,
                lpRedeem: 2_043.56808879152623138 * 1e27
            }
        );
        // check pool balances
        assertEq(_collateral.balanceOf(address(_pool)), 0);
        assertEq(_quote.balanceOf(address(_pool)),      0);

        // check bucket state
        _assertBucket(
            {
                index:        testIndex,
                lpBalance:    0,
                collateral:   0,
                deposit:      0,
                exchangeRate: 1 * 1e27
            }
        );
        _assertLenderLpBalance(
            {
                lender:      _lender,
                index:       testIndex,
                lpBalance:   0,
                depositTime: _startTime
            }
        );
        _assertLenderLpBalance(
            {
                lender:      _bidder,
                index:       testIndex,
                lpBalance:   0,
                depositTime: _startTime
            }
        );
    }

    /**
     *  @notice 2 lenders, 1 borrower, 1 bidder tests purchasing quote token with collateral.
     */
    function testPurchaseQuoteWithDebt() external tearDown {
        uint256 p2550 = 3_010.892022197881557845 * 1e18;

        // lenders add liquidity
        // lender 1
        _addInitialLiquidity(
            {
                from:   _lender,
                amount: 6_000 * 1e18,
                index:  2550
            }
        );
        _addInitialLiquidity(
            {
                from:   _lender,
                amount: 10_000 * 1e18,
                index:  2551
            }
        );
        _addInitialLiquidity(
            {
                from:   _lender,
                amount: 5_000 * 1e18,
                index:  2552
            }
        );

        // lender 2
        _addInitialLiquidity(
            {
                from:   _lender1,
                amount: 4_000 * 1e18,
                index:  2550
            }
        );
        _addInitialLiquidity(
            {
                from:   _lender1,
                amount: 5_000 * 1e18,
                index:  2552
            }
        );

        skip(3600);

        // borrower draws debt
        _pledgeCollateral(
            {
                from:     _borrower,
                borrower: _borrower,
                amount:   100 * 1e18
            }
        );
        _borrow(
            {
                from:       _borrower,
                amount:     15_000 * 1e18,
                indexLimit: 3_000,
                newLup:     _priceAt(2551)
            }
        );

        skip(86400);

        // check pool balances
        assertEq(_collateral.balanceOf(address(_pool)), 100 * 1e18);
        assertEq(_quote.balanceOf(address(_pool)),      15_000 * 1e18);

        // bidder purchases all quote from the highest bucket
        uint256 amountToPurchase = 10_100 * 1e18;
        assertGt(_quote.balanceOf(address(_pool)), amountToPurchase);
        uint256 amountWithInterest = 10_001.296261817085520000 * 1e18;
        // adding extra collateral to account for interest accumulation
        uint256 collateralToPurchaseWith = Maths.wmul(Maths.wdiv(amountToPurchase, p2550), 1.01 * 1e18);
        assertEq(collateralToPurchaseWith, 3.388032491631335842 * 1e18);

        // bidder purchases all quote from the highest bucket
        _addCollateral(
            {
                from:    _bidder,
                amount:  collateralToPurchaseWith,
                index:   2550,
                lpAward: 10_200.383861467480875668505869503 * 1e27
            }
        );

        skip(25 hours); // remove liquidity after one day to avoid early withdraw penalty
        _removeAllLiquidity(
            {
                from:     _bidder,
                amount:   amountWithInterest,
                index:    2550,
                newLup:   _priceAt(2552),
                lpRedeem: 10_000.349513872212134187863727799 * 1e27
            }
        );

        // bidder withdraws unused collateral
        uint256 expectedCollateral = 0.066443194797165079 * 1e18;
        _removeAllCollateral(
            {
                from:     _bidder,
                amount:   expectedCollateral,
                index:    2550,
                lpRedeem: 200.034347595268741480642141704 * 1e27
            }
        );
        _assertLenderLpBalance(
            {
                lender:      _bidder,
                index:       2550,
                lpBalance:   0,
                depositTime: _startTime + 3600 + 86400
            }
        );

        skip(7200);

        // lender exchanges their LP for collateral
        expectedCollateral = 1.992953578100502458 * 1e18;
        _removeAllCollateral(
            {
                from:     _lender,
                amount:   expectedCollateral,
                index:    2550,
                lpRedeem: 6_000 * 1e27
            }
        );

        _assertLenderLpBalance(
            {
                lender:      _lender,
                index:       2550,
                lpBalance:   0,
                depositTime: _startTime
            }
        );

        skip(3600);

        // lender1 exchanges their LP for collateral
        expectedCollateral = 1.328635718733668305 * 1e18;
        _removeAllCollateral(
            {
                from:     _lender1,
                amount:   expectedCollateral,
                index:    2550,
                lpRedeem: 4_000 * 1e27
            }
        );

        _assertLenderLpBalance(
            {
                lender:      _lender1,
                index:       2550,
                lpBalance:   0,
                depositTime: _startTime
            }
        );

        // check pool balances
        assertEq(_collateral.balanceOf(address(_pool)), 100 * 1e18);

        // check bucket state
        _assertBucket(
            {
                index:        2550,
                lpBalance:    0,
                collateral:   0,
                deposit:      0,
                exchangeRate: 1 * 1e27
            }
        );
    }
}
