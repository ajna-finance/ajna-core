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

contract ERC721PoolBorrowTest is ERC721HelperContract {

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
        uint256 priceAtTestIndex = _indexToPrice(testIndex);
        assertEq(priceAtTestIndex, 3_010.892022197881557845 * 1e18);

        // check bucket state
        ( , uint256 quote, uint256 collateral, uint256 lpb, , ) = _poolUtils.bucketInfo(address(_pool), 2550);
        assertEq(quote,      0);
        assertEq(collateral, 0);
        assertEq(lpb,        0);

        // check pool state
        assertEq(_collateral.balanceOf(_bidder),              13);
        assertEq(_collateral.balanceOf(_lender),              0);
        assertEq(_collateral.balanceOf(address(_pool)), 0);
        assertEq(_quote.balanceOf(address(_pool)),      0);
        assertEq(_quote.balanceOf(_bidder),                   0);

        // lender adds initial quote to pool
        changePrank(_lender);
        _pool.addQuoteToken(10_000 * 1e18, testIndex);

        // check bucket state
        (, quote, collateral, lpb, , ) = _poolUtils.bucketInfo(address(_pool), testIndex);
        assertEq(quote,      10_000 * 1e18);
        assertEq(collateral, 0);
        assertEq(lpb,        10_000 * 1e27);

        // _bidder deposits collateral into a bucket
        changePrank(_bidder);
        uint256[] memory tokenIdsToAdd = new uint256[](3);
        tokenIdsToAdd[0] = 65;
        tokenIdsToAdd[1] = 70;
        tokenIdsToAdd[2] = 73;
        vm.expectEmit(true, true, false, true);
        emit AddCollateralNFT(_bidder, testIndex, tokenIdsToAdd);
        vm.expectEmit(true, true, false, true);
        emit Transfer(_bidder, address(_pool), tokenIdsToAdd[0]);
        uint256 lpBalanceChange = _pool.addCollateral(tokenIdsToAdd, testIndex);

        // check bucket state
        (, quote, collateral, lpb, , ) = _poolUtils.bucketInfo(address(_pool), testIndex);
        assertEq(quote,      10_000 * 1e18);
        assertEq(collateral, Maths.wad(3));
        (uint256 lpBalance, ) = _pool.lenders(testIndex, _bidder);
        assertEq(lpBalance, lpBalanceChange);

        // check pool state
        assertEq(_collateral.balanceOf(_bidder),              10);
        assertEq(_collateral.balanceOf(_lender),              0);
        assertEq(_collateral.balanceOf(address(_pool)), 3);
        assertEq(_quote.balanceOf(address(_pool)),      10_000 * 1e18);
        assertEq(_quote.balanceOf(_bidder),                   0);

        // bidder removes quote token from bucket
        uint256 qtToRemove = Maths.wmul(priceAtTestIndex, 3 * 1e18);
        vm.expectEmit(true, true, false, true);
        emit RemoveQuoteToken(_bidder, testIndex, qtToRemove, _lup());
        _pool.removeAllQuoteToken(testIndex);
        assertEq(_quote.balanceOf(_bidder), qtToRemove);
        (lpBalance, ) = _pool.lenders(testIndex, _bidder);
        assertEq(lpBalance, 0);
        (, quote, collateral, lpb, , ) = _poolUtils.bucketInfo(address(_pool), testIndex);
        assertEq(quote,      10_000 * 1e18 - qtToRemove);
        assertEq(collateral, 3 * 1e18);

        // lender removes all collateral from bucket
        changePrank(_lender);
        uint256[] memory tokenIdsToRemove = new uint256[](2);
        tokenIdsToRemove = tokenIdsToAdd;
        vm.expectEmit(true, true, false, true);
        emit RemoveCollateralNFT(_lender, testIndex, tokenIdsToRemove);
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(_pool), _lender, tokenIdsToRemove[0]);
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(_pool), _lender, tokenIdsToRemove[1]);
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(_pool), _lender, tokenIdsToRemove[2]);
        _pool.removeCollateral(tokenIdsToRemove, testIndex);
        (, quote, collateral, lpb, , ) = _poolUtils.bucketInfo(address(_pool), testIndex);
        assertEq(quote,      967.323933406355326465 * 1e18);
        assertEq(collateral, 0);

        // lender removes remaining quote token to empty the bucket
        vm.expectEmit(true, true, false, true);
        emit RemoveQuoteToken(_lender, testIndex, quote, _lup());
        _pool.removeAllQuoteToken(testIndex);
        (, quote, collateral, lpb, , ) = _poolUtils.bucketInfo(address(_pool), testIndex);
        assertEq(quote,      0);
        assertEq(collateral, 0);
        assertEq(lpb,        0);
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
        changePrank(_lender);
        _pool.addQuoteToken(20_000 * 1e18, 2350);
        _pool.addQuoteToken(10_000 * 1e18, 2351);
        _pool.addQuoteToken(10_000 * 1e18, 2352);

        changePrank(_lender2);
        _pool.addQuoteToken(4_000 * 1e18, 2350);
        _pool.addQuoteToken(5_000 * 1e18, 2352);
        skip(3600);

        // borrower draws debt
        changePrank(_borrower);
        uint256[] memory tokenIdsToAdd = new uint256[](4);
        tokenIdsToAdd[0] = 1;
        tokenIdsToAdd[1] = 3;
        tokenIdsToAdd[2] = 5;
        tokenIdsToAdd[3] = 51;
        _pool.pledgeCollateral(_borrower, tokenIdsToAdd);
        _pool.borrow(24_000 * 1e18, 2351);
        assertEq(_lup(), _indexToPrice(2351));
        skip(86400);

        // check bucket state
        ( , uint256 quote, uint256 collateral, uint256 lpb, , ) = _poolUtils.bucketInfo(address(_pool), 2350);
        assertEq(quote,      24_000 * 1e18);
        assertEq(collateral, 0);
        assertEq(lpb,        24_000 * 1e27);

        // bidder purchases all quote from the highest bucket
        changePrank(_bidder);
        tokenIdsToAdd = new uint256[](4);
        tokenIdsToAdd[0] = 65;
        tokenIdsToAdd[1] = 70;
        tokenIdsToAdd[2] = 73;
        tokenIdsToAdd[3] = 74;
        uint256 amountToPurchase = 10_100 * 1e18;
        assertGt(_quote.balanceOf(address(_pool)), amountToPurchase);
        uint256 amountWithInterest = 24_001.477919844844176000 * 1e18;
        vm.expectEmit(true, true, true, true);
        emit AddCollateralNFT(_bidder, 2350, tokenIdsToAdd);
        vm.expectEmit(true, true, true, true);
        emit Transfer(_bidder, address(_pool), tokenIdsToAdd[0]);
        _pool.addCollateral(tokenIdsToAdd, 2350);
        
        vm.expectEmit(true, true, false, true);
        emit RemoveQuoteToken(_bidder, 2350, amountWithInterest, _indexToPrice(2352));
        _pool.removeAllQuoteToken(2350);
        assertEq(_quote.balanceOf(_bidder), amountWithInterest);

        // check bucket state
        ( , quote, collateral, lpb, , ) = _poolUtils.bucketInfo(address(_pool), 2350);
        assertEq(quote,      0);
        assertEq(collateral, Maths.wad(4));
        assertEq(lpb,        32_654.330240478871500328243823671 * 1e27);

        // bidder withdraws unused collateral
        uint256[] memory tokenIdsToRemove = new uint256[](1);
        tokenIdsToRemove[0] = 65;
        vm.expectEmit(true, true, true, true);
        emit RemoveCollateralNFT(_bidder, 2350, tokenIdsToRemove);
        (uint256 amount) = _pool.removeCollateral(tokenIdsToRemove, 2350);
        (uint256 lpBalance, ) = _pool.lenders(2350, _bidder);
        assertEq(lpBalance, 490.747680359153625246182861754 * 1e27);
        skip(7200);

        // should revert if lender attempts to remove more collateral than available in the bucket
        changePrank(_lender);
        tokenIdsToRemove = new uint256[](4);
        tokenIdsToRemove[0] = 1;
        tokenIdsToRemove[1] = 3;
        tokenIdsToRemove[2] = 5;
        tokenIdsToRemove[3] = 51;
        vm.expectRevert(IPoolErrors.PullCollateralInsufficientCollateral.selector);
        (amount) = _pool.removeCollateral(tokenIdsToRemove, 2350);

        // should revert if lender attempts to remove collateral not available in the bucket
        tokenIdsToRemove = new uint256[](1);
        tokenIdsToRemove[0] = 1;
        vm.expectRevert(IERC721PoolErrors.TokenNotDeposited.selector);
        (amount) = _pool.removeCollateral(tokenIdsToRemove, 2350);

        // lender exchanges their lp for collateral
        tokenIdsToRemove = new uint256[](1);
        tokenIdsToRemove[0] = 73;
        vm.expectEmit(true, true, true, true);
        emit RemoveCollateralNFT(_lender, 2350, tokenIdsToRemove);
        (amount) = _pool.removeCollateral(tokenIdsToRemove, 2350);
        (lpBalance, ) = _pool.lenders(2350, _lender);
        assertEq(lpBalance, 11_836.417439880282124917939038083 * 1e27);
        skip(3600);

        // check bucket state
        ( , quote, collateral, lpb, , ) = _poolUtils.bucketInfo(address(_pool), 2350);
        assertEq(quote,      0);
        assertEq(collateral, Maths.wad(2));
        assertEq(lpb,        16_327.165120239435750164121899837 * 1e27);

        // should revert if lender2 attempts to remove more collateral than lp is available for
        changePrank(_lender2);
        tokenIdsToRemove = new uint256[](1);
        tokenIdsToRemove[0] = 74;
        vm.expectRevert(IPoolErrors.RemoveCollateralInsufficientLP.selector);
        (amount) = _pool.removeCollateral(tokenIdsToRemove, 2350);
    }

}
