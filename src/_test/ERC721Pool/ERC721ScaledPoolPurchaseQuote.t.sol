// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.14;

import { ERC721Pool }        from "../../erc721/ERC721Pool.sol";
import { ERC721PoolFactory } from "../../erc721/ERC721PoolFactory.sol";

import { BucketMath } from "../../libraries/BucketMath.sol";
import { Maths }      from "../../libraries/Maths.sol";

import { ERC721HelperContract }           from "./ERC721DSTestPlus.sol";

contract ERC721ScaledBorrowTest is ERC721HelperContract {

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

        // deploy collection pool
        _collectionPool = _deployCollectionPool();

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
        _subsetPool = _deploySubsetPool(subsetTokenIds);

        address[] memory _poolAddresses = _getPoolAddresses();

        _mintAndApproveQuoteTokens(_poolAddresses, _lender, 200_000 * 1e18);
        _mintAndApproveQuoteTokens(_poolAddresses, _lender2, 200_000 * 1e18);

        _mintAndApproveCollateralTokens(_poolAddresses, _borrower, 52);
        _mintAndApproveCollateralTokens(_poolAddresses, _borrower2, 10);
        _mintAndApproveCollateralTokens(_poolAddresses, _bidder, 13);   
    }

    function testSubsetPurchaseQuote() external {
        // test setup
        uint256 testIndex = 2550;
        uint256 priceAtTestIndex = _subsetPool.indexToPrice(testIndex);
        assertEq(priceAtTestIndex, 3_010.892022197881557845 * 1e18);

        // check bucket state
        (uint256 quote, uint256 collateral, uint256 lpb, ) = _subsetPool.bucketAt(2550);
        assertEq(quote,      0);
        assertEq(collateral, 0);
        assertEq(lpb,        0);

        // check pool state
        assertEq(_collateral.balanceOf(_bidder),              13);
        assertEq(_collateral.balanceOf(_lender),              0);
        assertEq(_collateral.balanceOf(address(_subsetPool)), 0);
        assertEq(_quote.balanceOf(address(_subsetPool)),      0);
        assertEq(_quote.balanceOf(_bidder),                   0);

        // lender adds initial quote to pool
        changePrank(_lender);
        _subsetPool.addQuoteToken(10_000 * 1e18, testIndex);

        // check bucket state
        (quote, collateral, lpb, ) = _subsetPool.bucketAt(testIndex);
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
        emit Transfer(_bidder, address(_subsetPool), tokenIdsToAdd[0]);
        vm.expectEmit(true, true, false, true);
        emit AddCollateralNFT(_bidder, priceAtTestIndex, tokenIdsToAdd);
        uint256 lpBalanceChange = _subsetPool.addCollateral(tokenIdsToAdd, testIndex);

        // check bucket state
        (quote, collateral, lpb, ) = _subsetPool.bucketAt(testIndex);
        assertEq(quote,      10_000 * 1e18);
        assertEq(collateral, Maths.wad(3));
        (uint256 lpBalance, ) = _subsetPool.bucketLenders(testIndex, _bidder);
        assertEq(lpBalance, lpBalanceChange);

        // check pool state
        assertEq(_collateral.balanceOf(_bidder),              10);
        assertEq(_collateral.balanceOf(_lender),              0);
        assertEq(_collateral.balanceOf(address(_subsetPool)), 3);
        assertEq(_quote.balanceOf(address(_subsetPool)),      10_000 * 1e18);
        assertEq(_quote.balanceOf(_bidder),                   0);

        // bidder removes quote token from bucket
        uint256 qtToRemove = Maths.wmul(priceAtTestIndex, 3 * 1e18);
        vm.expectEmit(true, true, false, true);
        emit RemoveQuoteToken(_bidder, testIndex, qtToRemove, _subsetPool.lup());
        _subsetPool.removeAllQuoteToken(testIndex);
        assertEq(_quote.balanceOf(_bidder), qtToRemove);
        (lpBalance, ) = _subsetPool.bucketLenders(testIndex, _bidder);
        assertEq(lpBalance, 0);
        (quote, collateral, , ) = _subsetPool.bucketAt(testIndex);
        assertEq(quote,      10_000 * 1e18 - qtToRemove);
        assertEq(collateral, 3 * 1e18);

        // lender removes all collateral from bucket
        changePrank(_lender);
        uint256[] memory tokenIdsToRemove = new uint256[](2);
        tokenIdsToRemove = tokenIdsToAdd;
        vm.expectEmit(true, true, false, true);
        emit RemoveCollateralNFT(_lender, priceAtTestIndex, tokenIdsToRemove);
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(_subsetPool), _lender, tokenIdsToRemove[0]);
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(_subsetPool), _lender, tokenIdsToRemove[1]);
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(_subsetPool), _lender, tokenIdsToRemove[2]);
        _subsetPool.removeCollateral(tokenIdsToRemove, testIndex);
        (quote, collateral, , ) = _subsetPool.bucketAt(testIndex);
        assertEq(quote,      967.323933406355326465 * 1e18);
        assertEq(collateral, 0);

        // lender removes remaining quote token to empty the bucket
        vm.expectEmit(true, true, false, true);
        emit RemoveQuoteToken(_lender, testIndex, quote, _subsetPool.lup());
        _subsetPool.removeAllQuoteToken(testIndex);
        (quote, collateral, lpb, ) = _subsetPool.bucketAt(testIndex);
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
        _subsetPool.addQuoteToken(20_000 * 1e18, 2350);
        _subsetPool.addQuoteToken(10_000 * 1e18, 2351);
        _subsetPool.addQuoteToken(10_000 * 1e18, 2352);

        changePrank(_lender2);
        _subsetPool.addQuoteToken(4_000 * 1e18, 2350);
        _subsetPool.addQuoteToken(5_000 * 1e18, 2352);
        skip(3600);

        // borrower draws debt
        changePrank(_borrower);
        uint256[] memory tokenIdsToAdd = new uint256[](4);
        tokenIdsToAdd[0] = 1;
        tokenIdsToAdd[1] = 3;
        tokenIdsToAdd[2] = 5;
        tokenIdsToAdd[3] = 51;
        _subsetPool.pledgeCollateral(_borrower, tokenIdsToAdd, address(0), address(0));
        _subsetPool.borrow(24_000 * 1e18, 2351, address(0), address(0));
        assertEq(_subsetPool.lup(), _subsetPool.indexToPrice(2351));
        skip(86400);

        // check bucket state
        (uint256 quote, uint256 collateral, uint256 lpb, ) = _subsetPool.bucketAt(2350);
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
        assertGt(_quote.balanceOf(address(_subsetPool)), amountToPurchase);
        uint256 amountWithInterest = 24_001.511204352939432000 * 1e18;
        vm.expectEmit(true, true, true, true);
        emit Transfer(_bidder, address(_subsetPool), tokenIdsToAdd[0]);
        vm.expectEmit(true, true, true, true);
        emit AddCollateralNFT(_bidder, _subsetPool.indexToPrice(2350), tokenIdsToAdd);        
        _subsetPool.addCollateral(tokenIdsToAdd, 2350);
        
        vm.expectEmit(true, true, false, true);
        emit RemoveQuoteToken(_bidder, 2350, amountWithInterest, _subsetPool.indexToPrice(2352));
        _subsetPool.removeAllQuoteToken(2350);
        assertEq(_quote.balanceOf(_bidder), amountWithInterest);

        // check bucket state
        (quote, collateral, lpb, ) = _subsetPool.bucketAt(2350);
        assertEq(quote,      0);
        assertEq(collateral, Maths.wad(4));
        assertEq(lpb,        32_654.284956525291224787239794566 * 1e27);

        // bidder withdraws unused collateral
        uint256[] memory tokenIdsToRemove = new uint256[](1);
        tokenIdsToRemove[0] = 65;
        vm.expectEmit(true, true, true, true);
        emit RemoveCollateralNFT(_bidder, _subsetPool.indexToPrice(2350), tokenIdsToRemove);
        (uint256 amount) = _subsetPool.removeCollateral(tokenIdsToRemove, 2350);
        (uint256 lpBalance, ) = _subsetPool.bucketLenders(2350, _bidder);
        assertEq(lpBalance, 490.713717393968418590429839925 * 1e27);
        skip(7200);

        // should revert if lender attempts to remove more collateral than available in the bucket
        changePrank(_lender);
        tokenIdsToRemove = new uint256[](4);
        tokenIdsToRemove[0] = 1;
        tokenIdsToRemove[1] = 3;
        tokenIdsToRemove[2] = 5;
        tokenIdsToRemove[3] = 51;
        vm.expectRevert("S:RC:INSUF_COL");
        (amount) = _subsetPool.removeCollateral(tokenIdsToRemove, 2350);

        // should revert if lender attempts to remove collateral not available in the bucket
        tokenIdsToRemove = new uint256[](1);
        tokenIdsToRemove[0] = 1;
        vm.expectRevert("S:RC:T_NOT_IN_B");
        (amount) = _subsetPool.removeCollateral(tokenIdsToRemove, 2350);

        // lender exchanges their lp for collateral
        tokenIdsToRemove = new uint256[](1);
        tokenIdsToRemove[0] = 73;
        vm.expectEmit(true, true, true, true);
        emit RemoveCollateralNFT(_lender, _subsetPool.indexToPrice(2350), tokenIdsToRemove);
        (amount) = _subsetPool.removeCollateral(tokenIdsToRemove, 2350);
        (lpBalance, ) = _subsetPool.bucketLenders(2350, _lender);
        assertEq(lpBalance, 11_836.428760868677193803190045359 * 1e27);
        skip(3600);

        // check bucket state
        (quote, collateral, lpb, ) = _subsetPool.bucketAt(2350);
        assertEq(quote,      0);
        assertEq(collateral, Maths.wad(2));
        assertEq(lpb,        16_327.142478262645612393619885284 * 1e27);

        // should revert if lender2 attempts to remove more collateral than lp is available for
        changePrank(_lender2);
        tokenIdsToRemove = new uint256[](1);
        tokenIdsToRemove[0] = 74;
        vm.expectRevert("S:RC:INSUF_LPS");
        (amount) = _subsetPool.removeCollateral(tokenIdsToRemove, 2350);
    }

}
