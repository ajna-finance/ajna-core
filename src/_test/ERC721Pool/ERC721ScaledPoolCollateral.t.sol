// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.14;

import { ERC721Pool }        from "../../erc721/ERC721Pool.sol";
import { ERC721PoolFactory } from "../../erc721/ERC721PoolFactory.sol";

import { BucketMath } from "../../libraries/BucketMath.sol";
import { Maths }      from "../../libraries/Maths.sol";

import { ERC721DSTestPlus }                             from "./ERC721DSTestPlus.sol";
import { NFTCollateralToken, QuoteToken }            from "../utils/Tokens.sol";
import { UserWithNFTCollateral, UserWithQuoteTokenInNFTPool } from "../utils/Users.sol";

// TODO: pass different pool type to enable collection + subset test simplification
contract ERC721ScaledCollateralTest is ERC721DSTestPlus {

    uint256 public constant LARGEST_AMOUNT = type(uint256).max / 10**27;

    address                     internal _collectionPoolAddress;
    address                     internal _subsetPoolAddress;
    NFTCollateralToken          internal _collateral;
    ERC721Pool                  internal _collectionPool;
    ERC721Pool                  internal _subsetPool;
    QuoteToken                  internal _quote;
    UserWithNFTCollateral       internal _borrower;
    UserWithNFTCollateral       internal _borrower2;
    UserWithNFTCollateral       internal _bidder;
    UserWithQuoteTokenInNFTPool internal _lender;
    UserWithQuoteTokenInNFTPool internal _lender2;

    function setUp() external {
        // deploy token and user contracts; mint tokens
        _collateral  = new NFTCollateralToken();
        _quote       = new QuoteToken();

        _borrower   = new UserWithNFTCollateral();
        _borrower2  = new UserWithNFTCollateral();
        _bidder     = new UserWithNFTCollateral();
        _lender     = new UserWithQuoteTokenInNFTPool();
        _lender2    = new UserWithQuoteTokenInNFTPool();

        _collateral.mint(address(_borrower), 52);
        _collateral.mint(address(_bidder), 10);
        _quote.mint(address(_lender), 200_000 * 1e18);

        /*******************************/
        /*** Setup NFT Collection State ***/
        /*******************************/

        _collectionPoolAddress = new ERC721PoolFactory().deployPool(address(_collateral), address(_quote), 0.05 * 10**18);
        _collectionPool        = ERC721Pool(_collectionPoolAddress);

        _borrower.approveCollection(_collateral, address(_collectionPool));
        _bidder.approveCollection(_collateral, address(_collectionPool));

        _borrower.approveQuoteToken(_quote, address(_collectionPool), 200_000 * 1e18);
        _bidder.approveQuoteToken(_quote,   address(_collectionPool), 200_000 * 1e18);
        _lender.approveToken(_quote,   address(_collectionPool), 200_000 * 1e18);

        /*******************************/
        /*** Setup NFT Subset State ***/
        /*******************************/

        uint256[] memory subsetTokenIds = new uint256[](5);
        subsetTokenIds[0] = 1;
        subsetTokenIds[1] = 3;
        subsetTokenIds[2] = 5;
        subsetTokenIds[3] = 51;
        subsetTokenIds[4] = 53;

        _subsetPoolAddress = new ERC721PoolFactory().deploySubsetPool(address(_collateral), address(_quote), subsetTokenIds, 0.05 * 10**18);
        _subsetPool        = ERC721Pool(_subsetPoolAddress);

        _borrower.approveCollection(_collateral, address(_subsetPool));
        _bidder.approveCollection(_collateral, address(_subsetPool));

        _borrower.approveQuoteToken(_quote, address(_subsetPool), 200_000 * 1e18);
        _bidder.approveQuoteToken(_quote,   address(_subsetPool), 200_000 * 1e18);
        _lender.approveToken(_quote,   address(_subsetPool), 200_000 * 1e18);
    }

    /*******************************/
    /*** ERC721 Collection Tests ***/
    /*******************************/

    /**************************************/
    /*** ERC721 Subset Tests ***/
    /**************************************/

    function testAddCollateralSubset() external {
        // check initial token balances
        assertEq(_subsetPool.pledgedCollateral(), 0);
        assertEq(_collateral.balanceOf(address(_borrower)), 52);
        assertEq(_collateral.balanceOf(address(_subsetPool)), 0);

        uint256[] memory tokenIdsToAdd = new uint256[](3);
        tokenIdsToAdd[0] = 1;
        tokenIdsToAdd[1] = 3;
        tokenIdsToAdd[2] = 5;

        // borrower deposits three NFTs into the subset pool
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(_borrower), address(_subsetPool), 1);
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(_borrower), address(_subsetPool), 3);
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(_borrower), address(_subsetPool), 5);
        vm.expectEmit(true, true, false, true);
        emit AddCollateralNFT(address(_borrower), tokenIdsToAdd);
        _borrower.addCollateral(_subsetPool, tokenIdsToAdd, address(0), address(0));

        // check token balances after add
        assertEq(_subsetPool.pledgedCollateral(), Maths.wad(3));
        assertEq(_collateral.balanceOf(address(_borrower)), 49);
        assertEq(_collateral.balanceOf(address(_subsetPool)), 3);
    }

    function testAddCollateralNotInSubset() external {
        uint256[] memory tokenIdsToAdd = new uint256[](3);
        tokenIdsToAdd[0] = 2;
        tokenIdsToAdd[1] = 4;
        tokenIdsToAdd[2] = 6;

        // should revert if borrower attempts to add tokens not in the pool subset
        vm.expectRevert("P:ONLY_SUBSET");
        _borrower.addCollateral(_subsetPool, tokenIdsToAdd, address(0), address(0));
    }

    function testRemoveCollateral() external {
        // check initial token balances
        assertEq(_subsetPool.pledgedCollateral(), 0);
        assertEq(_collateral.balanceOf(address(_borrower)), 52);
        assertEq(_collateral.balanceOf(address(_subsetPool)), 0);

        uint256[] memory tokenIdsToAdd = new uint256[](3);
        tokenIdsToAdd[0] = 1;
        tokenIdsToAdd[1] = 3;
        tokenIdsToAdd[2] = 5;

        // borrower deposits three NFTs into the subset pool
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(_borrower), address(_subsetPool), 1);
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(_borrower), address(_subsetPool), 3);
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(_borrower), address(_subsetPool), 5);
        vm.expectEmit(true, true, false, true);
        emit AddCollateralNFT(address(_borrower), tokenIdsToAdd);
        _borrower.addCollateral(_subsetPool, tokenIdsToAdd, address(0), address(0));

        // check token balances after add
        assertEq(_subsetPool.pledgedCollateral(), Maths.wad(3));
        assertEq(_collateral.balanceOf(address(_borrower)), 49);
        assertEq(_collateral.balanceOf(address(_subsetPool)), 3);

        uint256[] memory tokenIdsToRemove = new uint256[](2);
        tokenIdsToRemove[0] = 3;
        tokenIdsToRemove[1] = 5;

        // borrower removes some of their deposted NFTS from the pool
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(_subsetPool), address(_borrower), 3);
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(_subsetPool), address(_borrower), 5);
        vm.expectEmit(true, true, false, true);
        emit RemoveCollateralNFT(address(_borrower), tokenIdsToRemove);
        _borrower.removeCollateral(_subsetPool, tokenIdsToRemove, address(0), address(0));

        // check token balances after remove
        assertEq(_subsetPool.pledgedCollateral(), Maths.wad(1));
        assertEq(_collateral.balanceOf(address(_borrower)), 51);
        assertEq(_collateral.balanceOf(address(_subsetPool)), 1);
    }

    // TODO: finish implementing
    function testRemoveCollateralNotInPool() external {
        uint256[] memory tokenIdsToAdd = new uint256[](3);
        tokenIdsToAdd[0] = 1;
        tokenIdsToAdd[1] = 3;
        tokenIdsToAdd[2] = 5;
        _borrower.addCollateral(_subsetPool, tokenIdsToAdd, address(0), address(0));

        // should revert if borrower attempts to remove collateral not in pool
        uint256[] memory tokenIdsToRemove = new uint256[](1);
        tokenIdsToRemove[0] = 51;
        vm.expectRevert("P:T_NOT_IN_P");
        _borrower.removeCollateral(_subsetPool, tokenIdsToRemove, address(0), address(0));

        // borrower should be able to remove collateral in the pool
        tokenIdsToRemove = new uint256[](3);
        tokenIdsToRemove[0] = 1;
        tokenIdsToRemove[1] = 3;
        tokenIdsToRemove[2] = 5;

        vm.expectEmit(true, true, false, true);
        emit Transfer(address(_subsetPool), address(_borrower), 1);
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(_subsetPool), address(_borrower), 3);
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(_subsetPool), address(_borrower), 5);
        vm.expectEmit(true, true, false, true);
        emit RemoveCollateralNFT(address(_borrower), tokenIdsToRemove);
        _borrower.removeCollateral(_subsetPool, tokenIdsToRemove, address(0), address(0));
    }

    function testRemoveCollateralPartiallyEncumbered() external {
        // lender deposits 10000 Quote into 3 buckets
        _lender.addQuoteToken(_subsetPool, 10_000 * 1e18, 2550);
        _lender.addQuoteToken(_subsetPool, 10_000 * 1e18, 2551);
        _lender.addQuoteToken(_subsetPool, 10_000 * 1e18, 2552);

        // check initial token balances
        assertEq(_subsetPool.pledgedCollateral(), 0);
        assertEq(_collateral.balanceOf(address(_borrower)), 52);
        assertEq(_collateral.balanceOf(address(_subsetPool)), 0);

        assertEq(_quote.balanceOf(address(_subsetPool)),   30_000 * 1e18);
        assertEq(_quote.balanceOf(address(_borrower)), 0);

        // check pool state
        assertEq(_subsetPool.htp(), 0);
        assertEq(_subsetPool.lup(), BucketMath.MAX_PRICE);

        assertEq(_subsetPool.treeSum(),                         30_000 * 1e18);
        assertEq(_subsetPool.exchangeRate(2550),                     1 * 1e27);

        uint256[] memory tokenIdsToAdd = new uint256[](3);
        tokenIdsToAdd[0] = 1;
        tokenIdsToAdd[1] = 3;
        tokenIdsToAdd[2] = 5;

        // borrower deposits three NFTs into the subset pool
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(_borrower), address(_subsetPool), 1);
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(_borrower), address(_subsetPool), 3);
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(_borrower), address(_subsetPool), 5);
        vm.expectEmit(true, true, false, true);
        emit AddCollateralNFT(address(_borrower), tokenIdsToAdd);
        _borrower.addCollateral(_subsetPool, tokenIdsToAdd, address(0), address(0));

        // TODO: determine how to handle checking both token types of Transfer
        // emit Transfer(address(_borrower), address(_subsetPool), 5);
        // vm.expectEmit(true, true, false, true);
        uint256 borrowAmount = 3_000 * 1e18;
        emit Borrow(address(_borrower), _subsetPool.indexToPrice(2550), 3_000 * 1e18);
        _borrower.borrow(_subsetPool, 3_000 * 1e18, 2551, address(0), address(0));

        // check token balances after borrow
        assertEq(_subsetPool.pledgedCollateral(), Maths.wad(3));
        assertEq(_collateral.balanceOf(address(_borrower)), 49);
        assertEq(_collateral.balanceOf(address(_subsetPool)), 3);

        assertEq(_quote.balanceOf(address(_subsetPool)),   27_000 * 1e18);
        assertEq(_quote.balanceOf(address(_borrower)), 3_000 * 1e18);

        // check pool state
        assertEq(_subsetPool.htp(), 1000.961538461538462000 * 1e18);
        assertEq(_subsetPool.lup(), _subsetPool.indexToPrice(2550));

        assertEq(_subsetPool.treeSum(),                         30_000 * 1e18);
        assertEq(_subsetPool.exchangeRate(2550),                     1 * 1e27);

        // remove some unencumbered collateral
        uint256[] memory tokenIdsToRemove = new uint256[](2);
        tokenIdsToRemove[0] = 3;
        tokenIdsToRemove[1] = 5;

        // borrower removes some of their deposted NFTS from the pool
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(_subsetPool), address(_borrower), 3);
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(_subsetPool), address(_borrower), 5);
        vm.expectEmit(true, true, false, true);
        emit RemoveCollateralNFT(address(_borrower), tokenIdsToRemove);
        _borrower.removeCollateral(_subsetPool, tokenIdsToRemove, address(0), address(0));

        // check token balances after remove
        assertEq(_subsetPool.pledgedCollateral(), Maths.wad(1));
        assertEq(_collateral.balanceOf(address(_borrower)), 51);
        assertEq(_collateral.balanceOf(address(_subsetPool)), 1);

        assertEq(_quote.balanceOf(address(_subsetPool)),   27_000 * 1e18);
        assertEq(_quote.balanceOf(address(_borrower)), 3_000 * 1e18);

        // check pool state
        assertEq(_subsetPool.htp(), 3002.884615384615386000 * 1e18);
        assertEq(_subsetPool.lup(), _subsetPool.indexToPrice(2550));

        assertEq(_subsetPool.treeSum(),                         30_000 * 1e18);
        assertEq(_subsetPool.exchangeRate(2550),                     1 * 1e27);

    }

    // TODO: finish implementing: check revert not enough collateral
    function testRemoveOverlyEncumbered() external {

    }

}
