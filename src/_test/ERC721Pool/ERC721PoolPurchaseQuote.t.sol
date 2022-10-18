// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity 0.8.14;

import { ERC721HelperContract } from './ERC721DSTestPlus.sol';

import '../../erc721/ERC721Pool.sol';
import '../../erc721/ERC721PoolFactory.sol';

import '../../erc721/interfaces/IERC721Pool.sol';
import '../../erc721/interfaces/pool/IERC721PoolErrors.sol';
import '../../base/interfaces/IPool.sol';
import '../../base/interfaces/pool/IPoolErrors.sol';

import '../../libraries/BucketMath.sol';
import '../../libraries/Maths.sol';

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

    function testSubsetPurchaseQuote() external {
        // test setup
        uint256 testIndex = 2550;
        uint256 priceAtTestIndex = PoolUtils.indexToPrice(testIndex);
        assertEq(priceAtTestIndex, 3_010.892022197881557845 * 1e18);

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
        _addLiquidity(
            {
                from:   _lender,
                amount: 10_000 * 1e18,
                index:  testIndex,
                newLup: BucketMath.MAX_PRICE
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
                index:    testIndex
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
        uint256 qtToRemove = Maths.wmul(priceAtTestIndex, 3 * 1e18);
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
        uint256[] memory tokenIdsToRemove = new uint256[](2);
        tokenIdsToRemove = tokenIdsToAdd;
        _removeCollateral(
            {
                from:     _lender,
                tokenIds: tokenIdsToRemove,
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
    function testSubsetPurchaseQuoteWithDebt() external {
        // lenders add liquidity
        _addLiquidity(
            {
                from:   _lender,
                amount: 20_000 * 1e18,
                index:  2350,
                newLup: BucketMath.MAX_PRICE
            }
        );
        _addLiquidity(
            {
                from:   _lender,
                amount: 10_000 * 1e18,
                index:  2351,
                newLup: BucketMath.MAX_PRICE
            }
        );
        _addLiquidity(
            {
                from:   _lender,
                amount: 10_000 * 1e18,
                index:  2352,
                newLup: BucketMath.MAX_PRICE
            }
        );

        _addLiquidity(
            {
                from:   _lender2,
                amount: 4_000 * 1e18,
                index:  2350,
                newLup: BucketMath.MAX_PRICE
            }
        );
        _addLiquidity(
            {
                from:   _lender2,
                amount: 5_000 * 1e18,
                index:  2352,
                newLup: BucketMath.MAX_PRICE
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
                newLup:     8_164.085273480993906521 * 1e18
            }
        );
        assertEq(_lup(), PoolUtils.indexToPrice(2351));
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
        uint256 amountWithInterest = 24_002.808232738534440000 * 1e18;

        _addCollateral(
            {
                from:     _bidder,
                tokenIds: tokenIdsToAdd,
                index:    2350
            }
        );
        skip(25 hours); // remove liquidity after one day to avoid early withdraw penalty
        _removeAllLiquidity(
            {
                from:     _bidder,
                amount:   amountWithInterest,
                index:    2350,
                newLup:   PoolUtils.indexToPrice(2352),
                lpRedeem: 24_000.766698354457765204510601361 * 1e27
            }
        );

        assertEq(_quote.balanceOf(_bidder), amountWithInterest);

        // check bucket state
        _assertBucket(
            {
                index:        2350,
                lpBalance:    32_653.563542124413735123733246309 * 1e27,
                collateral:   Maths.wad(4),
                deposit:      0,
                exchangeRate: 1.000085061215324285728665849 * 1e27
            }
        );

        // bidder withdraws unused collateral
        uint256[] memory tokenIdsToRemove = new uint256[](1);
        tokenIdsToRemove[0] = 65;
        (uint256 amount) = _removeCollateral(
            {
                from:     _bidder,
                tokenIds: tokenIdsToRemove,
                index:    2350,
                lpRedeem: 8_163.390885531103433780933317567 * 1e27
            }
        );

        _assertLenderLpBalance(
            {
                lender:      _bidder,
                index:       2350,
                lpBalance:   490.172656593310301342799928742 * 1e27,
                depositTime: _startTime + 25 hours
            }
        );

        skip(7200);

        changePrank(_lender);
        tokenIdsToRemove = new uint256[](4);
        tokenIdsToRemove[0] = 1;
        tokenIdsToRemove[1] = 3;
        tokenIdsToRemove[2] = 5;
        tokenIdsToRemove[3] = 51;

        // should revert if lender attempts to remove more collateral than available in the bucket
        _assertRemoveInsufficientCollateralRevert(
            {
                from:     _lender,
                tokenIds: tokenIdsToRemove,
                index:    2350
            }
        );

        // should revert if lender attempts to remove collateral not available in the bucket
        tokenIdsToRemove = new uint256[](1);
        tokenIdsToRemove[0] = 1;
        _assertRemoveNotDepositedTokenRevert(
            {
                from:     _lender,
                tokenIds: tokenIdsToRemove,
                index:    2350
            }
        );

        // lender exchanges their lp for collateral
        tokenIdsToRemove = new uint256[](1);
        tokenIdsToRemove[0] = 73;
        (amount) = _removeCollateral(
            {
                from:     _lender,
                tokenIds: tokenIdsToRemove,
                index:    2350,
                lpRedeem: 8_163.390885531103433780933317567 * 1e27
            }
        );

        _assertLenderLpBalance(
            {
                lender:      _bidder,
                index:       2350,
                lpBalance:   490.172656593310301342799928742 * 1e27,
                depositTime: _startTime + 25 hours
            }
        );

        skip(3600);

        // check bucket state
        _assertBucket(
            {
                index:        2350,
                lpBalance:    16_326.781771062206867561866611175 * 1e27,
                collateral:   Maths.wad(2),
                deposit:      0,
                exchangeRate: 1.000085061215324285728665850 * 1e27
            }
        );

        // should revert if lender2 attempts to remove more collateral than lp is available for
        tokenIdsToRemove = new uint256[](1);
        tokenIdsToRemove[0] = 74;
        _assertRemoveCollateralInsufficientLPsRevert(
            {
                from:     _lender2,
                tokenIds: tokenIdsToRemove,
                index:    2350
            }
        );
    }

}
