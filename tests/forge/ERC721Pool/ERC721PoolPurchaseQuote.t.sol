// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.14;

import { ERC721HelperContract } from './ERC721DSTestPlus.sol';

import 'src/libraries/helpers/PoolHelper.sol';

contract ERC721PoolPurchaseQuoteTest is ERC721HelperContract {

    address internal _borrower;
    address internal _borrower2;
    address internal _bidder;
    address internal _lender;
    address internal _lender2;

    function setUp() external {
        _borrower  = makeAddr("borrower");
        _borrower2 = makeAddr("borrower2");
        _bidder    = makeAddr("bidder");
        _lender    = makeAddr("lender");
        _lender2   = makeAddr("lender2");

        // deploy subset pool
        uint256[] memory subsetTokenIds = new uint256[](9);
        subsetTokenIds[0] = 1;
        subsetTokenIds[1] = 3;
        subsetTokenIds[2] = 5;
        subsetTokenIds[3] = 51;
        subsetTokenIds[4] = 53;
        subsetTokenIds[5] = 65;
        subsetTokenIds[6] = 70;
        subsetTokenIds[7] = 73;
        subsetTokenIds[8] = 74;
        _pool = _deploySubsetPool(subsetTokenIds);

        _mintAndApproveQuoteTokens(_lender, 200_000 * 1e18);
        _mintAndApproveQuoteTokens(_lender2, 200_000 * 1e18);

        _mintAndApproveCollateralTokens(_borrower, 52);
        _mintAndApproveCollateralTokens(_borrower2, 10);
        _mintAndApproveCollateralTokens(_bidder, 13);
    }

    function testSubsetPurchaseQuote() external tearDown {
        // test setup
        uint256 testIndex = 2550;
        uint256 _priceAtTestIndex = _priceAt(testIndex);
        assertEq(_priceAtTestIndex, 3_010.892022197881557845 * 1e18);

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

        // check pool state
        assertEq(_collateral.balanceOf(_bidder),        13);
        assertEq(_collateral.balanceOf(_lender),        0);
        assertEq(_collateral.balanceOf(address(_pool)), 0);
        assertEq(_quote.balanceOf(address(_pool)),      0);
        assertEq(_quote.balanceOf(_bidder),             0);

        // lender adds initial quote to pool
        _addInitialLiquidity(
            {
                from:   _lender,
                amount: 10_000 * 1e18,
                index:  testIndex
            }
        );

        // check bucket state
        _assertBucket(
            {
                index:        testIndex,
                lpBalance:    10_000 * 1e27,
                collateral:   0,
                deposit:      10_000 * 1e18,
                exchangeRate: 1 * 1e27
            }
        );

        // _bidder deposits collateral into a bucket
        changePrank(_bidder);
        uint256[] memory tokenIdsToAdd = new uint256[](3);
        tokenIdsToAdd[0] = 65;
        tokenIdsToAdd[1] = 70;
        tokenIdsToAdd[2] = 73;

        uint256 lpBalanceChange = _addCollateral(
            {
                from:     _bidder,
                tokenIds: tokenIdsToAdd,
                index:    testIndex,
                lpAward:  9_032.676066593644673535 * 1e27
            }
        );

        // check bucket state
        _assertBucket(
            {
                index:        testIndex,
                lpBalance:    19_032.676066593644673535 * 1e27,
                collateral:   Maths.wad(3),
                deposit:      10_000 * 1e18,
                exchangeRate: 1 * 1e27
            }
        );
        _assertLenderLpBalance(
            {
                lender:      _bidder,
                index:       testIndex,
                lpBalance:   lpBalanceChange,
                depositTime: _startTime
            }
        );

        // check pool state
        assertEq(_collateral.balanceOf(_bidder),        10);
        assertEq(_collateral.balanceOf(_lender),        0);
        assertEq(_collateral.balanceOf(address(_pool)), 3);
        assertEq(_quote.balanceOf(address(_pool)),      10_000 * 1e18);
        assertEq(_quote.balanceOf(_bidder),             0);

        // bidder removes quote token from bucket
        skip(1 days); // skip to avoid penalty
        uint256 qtToRemove = Maths.wmul(_priceAtTestIndex, 3 * 1e18);
        _removeAllLiquidity(
            {
                from:     _bidder,
                amount:   qtToRemove,
                index:    testIndex,
                newLup:   _lup(),
                lpRedeem: 9_032.676066593644673535 * 1e27
            }
        );
        assertEq(_quote.balanceOf(_bidder), qtToRemove);

        _assertBucket(
            {
                index:        testIndex,
                lpBalance:    10_000 * 1e27,
                collateral:   Maths.wad(3),
                deposit:      967.323933406355326465 * 1e18,
                exchangeRate: 1 * 1e27
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

        // lender removes all collateral from bucket
        _removeCollateral(
            {
                from:     _lender,
                amount:   3,
                index:    testIndex,
                lpRedeem: 9_032.676066593644673535 * 1e27
            }
        );

        _assertBucket(
            {
                index:        testIndex,
                lpBalance:    967.323933406355326465 * 1e27,
                collateral:   0,
                deposit:      967.323933406355326465 * 1e18,
                exchangeRate: 1 * 1e27
            }
        );

        // lender removes remaining quote token to empty the bucket
        _removeAllLiquidity(
            {
                from:     _lender,
                amount:   967.323933406355326465 * 1e18,
                index:    testIndex,
                newLup:   _lup(),
                lpRedeem: 967.323933406355326465 * 1e27
            }
        );

        _assertBucket(
            {
                index:        testIndex,
                lpBalance:    0,
                collateral:   0,
                deposit:      0,
                exchangeRate: 1 * 1e27
            }
        );
    }

    /**
     *  @notice 2 lenders, 1 borrower, 1 bidder tests purchasing quote token with collateral.
     *          Reverts:
     *              Attempts to remove more collateral than available in bucket.
     *              Attempts to remove more collateral than available given lp balance.
     *              Attempts to remove collateral not in the bucket.
     */
    function testSubsetPurchaseQuoteWithDebt() external tearDown {
        // lenders add liquidity
        _addInitialLiquidity(
            {
                from:   _lender,
                amount: 20_000 * 1e18,
                index:  2350
            }
        );
        _addInitialLiquidity(
            {
                from:   _lender,
                amount: 10_000 * 1e18,
                index:  2351
            }
        );
        _addInitialLiquidity(
            {
                from:   _lender,
                amount: 10_000 * 1e18,
                index:  2352
            }
        );

        _addInitialLiquidity(
            {
                from:   _lender2,
                amount: 4_000 * 1e18,
                index:  2350
            }
        );
        _addInitialLiquidity(
            {
                from:   _lender2,
                amount: 5_000 * 1e18,
                index:  2352
            }
        );

        skip(3600);

        // borrower draws debt
        uint256[] memory tokenIdsToAdd = new uint256[](4);
        tokenIdsToAdd[0] = 1;
        tokenIdsToAdd[1] = 3;
        tokenIdsToAdd[2] = 5;
        tokenIdsToAdd[3] = 51;
        _pledgeCollateral(
            {
                from:     _borrower,
                borrower: _borrower,
                tokenIds: tokenIdsToAdd
            }
        );
        _borrow(
            {
                from:       _borrower,
                amount:     24_000 * 1e18,
                indexLimit: 2_351,
                newLup:     8_123.467933811934300919 * 1e18
            }
        );
        assertEq(_lup(), _priceAt(2351));
        skip(86400);

        // check bucket state
        _assertBucket(
            {
                index:        2350,
                lpBalance:    24_000 * 1e27,
                collateral:   0,
                deposit:      24_000 * 1e18,
                exchangeRate: 1 * 1e27
            }
        );

        // bidder purchases all quote from the highest bucket
        tokenIdsToAdd = new uint256[](4);
        tokenIdsToAdd[0] = 65;
        tokenIdsToAdd[1] = 70;
        tokenIdsToAdd[2] = 73;
        tokenIdsToAdd[3] = 74;
        uint256 amountToPurchase = 10_100 * 1e18;
        assertGt(_quote.balanceOf(address(_pool)), amountToPurchase);
        uint256 amountWithInterest = 24_002.749104114061152000 * 1e18;

        _addCollateral(
            {
                from:     _bidder,
                tokenIds: tokenIdsToAdd,
                index:    2350,
                lpAward:  32_654.410675370944354984500292928 * 1e27
            }
        );
        skip(25 hours); // remove liquidity after one day to avoid early withdraw penalty
        _removeAllLiquidity(
            {
                from:     _bidder,
                amount:   amountWithInterest,
                index:    2350,
                newLup:   _priceAt(2352),
                lpRedeem: 24_000.766696558404292700773653981 * 1e27
            }
        );

        assertEq(_quote.balanceOf(_bidder), amountWithInterest);

        // check bucket state
        _assertBucket(
            {
                index:        2350,
                lpBalance:    32_653.643978812540062283726638947 * 1e27,
                collateral:   Maths.wad(4),
                deposit:      0,
                exchangeRate: 1.000082597676179283352120528 * 1e27
            }
        );

        // bidder withdraws unused collateral
        (uint256 amount) = _removeCollateral(
            {
                from:     _bidder,
                amount:   1,
                index:    2350,
                lpRedeem: 8_163.410994703135015570931665340 * 1e27
            }
        );

        _assertLenderLpBalance(
            {
                lender:      _bidder,
                index:       2350,
                lpBalance:   490.232984109405046712794973607 * 1e27,
                depositTime: _startTime + 25 hours
            }
        );

        skip(7200);

        changePrank(_lender);
        // lender exchanges their lp for collateral
        (amount) = _removeCollateral(
            {
                from:     _lender,
                amount:   1,
                index:    2350,
                lpRedeem: 8_163.410994703135015570931665340 * 1e27
            }
        );

        _assertLenderLpBalance(
            {
                lender:      _bidder,
                index:       2350,
                lpBalance:   490.232984109405046712794973607 * 1e27,
                depositTime: _startTime + 25 hours
            }
        );

        skip(3600);

        // check bucket state
        _assertBucket(
            {
                index:        2350,
                lpBalance:    16_326.821989406270031141863308267 * 1e27,
                collateral:   Maths.wad(2),
                deposit:      0,
                exchangeRate: 1.000082597676179283352120529 * 1e27
            }
        );

        // should revert if lender2 attempts to remove more collateral than lp is available for
        _assertRemoveCollateralInsufficientLPsRevert(
            {
                from:   _lender2,
                amount: 1,
                index:  2350
            }
        );

        skip(3600);
    }
}
