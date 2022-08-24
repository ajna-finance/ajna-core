// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.14;

import { ERC721Pool }        from "../../erc721/ERC721Pool.sol";
import { ERC721PoolFactory } from "../../erc721/ERC721PoolFactory.sol";

import { BucketMath } from "../../libraries/BucketMath.sol";
import { Maths }      from "../../libraries/Maths.sol";

import { ERC721DSTestPlus }               from "./ERC721DSTestPlus.sol";
import { NFTCollateralToken, QuoteToken } from "../utils/Tokens.sol";

contract ERC721ScaledBorrowTest is ERC721DSTestPlus {

    uint256 public constant LARGEST_AMOUNT = type(uint256).max / 10**27;

    address internal _borrower;
    address internal _borrower2;
    address internal _bidder;
    address internal _lender;
    address internal _lender2;

    address internal _collectionPoolAddress;
    address internal _subsetPoolAddress;

    NFTCollateralToken internal _collateral;
    QuoteToken         internal _quote;
    ERC721Pool         internal _collectionPool;
    ERC721Pool         internal _subsetPool;

    function setUp() external {
        // deploy token and user contracts; mint and set balances
        _collateral = new NFTCollateralToken();
        _quote      = new QuoteToken();

        _borrower  = makeAddr("borrower");
        _borrower2 = makeAddr("borrower2");
        _bidder    = makeAddr("bidder");
        _lender    = makeAddr("lender");
        _lender2   = makeAddr("lender2");

        _collateral.mint(address(_borrower),  52);
        _collateral.mint(address(_borrower2), 10);
        _collateral.mint(address(_bidder), 13);

        deal(address(_quote), _lender, 200_000 * 1e18);

        /*******************************/
        /*** Setup NFT Collection State ***/
        /*******************************/

        _collectionPoolAddress = new ERC721PoolFactory().deployPool(address(_collateral), address(_quote), 0.05 * 10**18);
        _collectionPool        = ERC721Pool(_collectionPoolAddress);

        vm.startPrank(_borrower);
        _collateral.setApprovalForAll(address(_collectionPool), true);
        _quote.approve(address(_collectionPool), 200_000 * 1e18);

        changePrank(_borrower2);
        _collateral.setApprovalForAll(address(_collectionPool), true);
        _quote.approve(address(_collectionPool), 200_000 * 1e18);

        changePrank(_bidder);
        _collateral.setApprovalForAll(address(_collectionPool), true);
        _quote.approve(address(_collectionPool), 200_000 * 1e18);

        changePrank(_lender);
        _quote.approve(address(_collectionPool), 200_000 * 1e18);

        /*******************************/
        /*** Setup NFT Subset State ***/
        /*******************************/

        uint256[] memory subsetTokenIds = new uint256[](8);
        subsetTokenIds[0] = 1;
        subsetTokenIds[1] = 3;
        subsetTokenIds[2] = 5;
        subsetTokenIds[3] = 51;
        subsetTokenIds[4] = 53;
        subsetTokenIds[5] = 65;
        subsetTokenIds[6] = 70;
        subsetTokenIds[7] = 73;

        _subsetPoolAddress = new ERC721PoolFactory().deploySubsetPool(address(_collateral), address(_quote), subsetTokenIds, 0.05 * 10**18);
        _subsetPool        = ERC721Pool(_subsetPoolAddress);

        changePrank(_borrower);
        _collateral.setApprovalForAll(address(_subsetPool), true);
        _quote.approve(address(_subsetPool), 200_000 * 1e18);

        changePrank(_borrower2);
        _collateral.setApprovalForAll(address(_subsetPool), true);
        _quote.approve(address(_subsetPool), 200_000 * 1e18);

        changePrank(_bidder);
        _collateral.setApprovalForAll(address(_subsetPool), true);
        _quote.approve(address(_subsetPool), 200_000 * 1e18);

        changePrank(_lender);
        _quote.approve(address(_subsetPool), 200_000 * 1e18);
    }

    // TODO: finish implementing
    function testSubsetAddRemoveCollateral() external {
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
        assertEq(_collateral.balanceOf(address(_bidder)),       13);
        assertEq(_collateral.balanceOf(address(_lender)),       0);
        assertEq(_collateral.balanceOf(address(_subsetPool)),   0);
        assertEq(_quote.balanceOf(address(_subsetPool)),        0);
        assertEq(_quote.balanceOf(address(_bidder)),            0);

        // lender adds initial quote to pool
        changePrank(_lender);
        _subsetPool.addQuoteToken(10_000 * 1e18, testIndex);

        // check bucket state
        (quote, collateral, lpb, ) = _subsetPool.bucketAt(2550);
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
        emit Transfer(address(_bidder), address(_subsetPool), tokenIdsToAdd[0]);
        vm.expectEmit(true, true, false, true);
        emit AddCollateralNFT(address(_bidder), priceAtTestIndex, tokenIdsToAdd);
        uint256 lpBalanceChange = _subsetPool.addCollateral(tokenIdsToAdd, testIndex);

        // FIXME: finish implementing
        // check bucket state
        (quote, collateral, lpb, ) = _subsetPool.bucketAt(2550);
        assertEq(quote,      10_000 * 1e18);
        assertEq(collateral, Maths.wad(3));
        // assertEq(lpb,        0);
        // assertEq(lpb,        lpBalanceChange);

        // check pool state
        assertEq(_collateral.balanceOf(address(_bidder)),       10);
        assertEq(_collateral.balanceOf(address(_lender)),       0);
        assertEq(_collateral.balanceOf(address(_subsetPool)),   3);
        assertEq(_quote.balanceOf(address(_subsetPool)),        10_000 * 1e18);
        assertEq(_quote.balanceOf(address(_bidder)),            0);

        // lender removes some collateral from bucket


        // lender removes all collateral from bucket


    }

}