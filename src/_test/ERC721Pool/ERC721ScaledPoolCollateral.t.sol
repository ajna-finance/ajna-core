// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.14;

import { ERC721Pool }        from "../../erc721/ERC721Pool.sol";
import { ERC721PoolFactory } from "../../erc721/ERC721PoolFactory.sol";

import { BucketMath } from "../../libraries/BucketMath.sol";
import { Maths }      from "../../libraries/Maths.sol";

import { ERC721DSTestPlus }               from "./ERC721DSTestPlus.sol";
import { NFTCollateralToken, QuoteToken } from "../utils/Tokens.sol";

// TODO: pass different pool type to enable collection + subset test simplification
contract ERC721ScaledCollateralTest is ERC721DSTestPlus {

    uint256 public constant LARGEST_AMOUNT = type(uint256).max / 10**27;

    address internal _borrower;
    address internal _borrower2;
    address internal _bidder;
    address internal _lender;
    address internal _lender2;

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
        _collateral.mint(address(_bidder), 10);

        deal(address(_quote), _lender, 200_000 * 1e18);


        /*******************************/
        /*** Setup NFT Collection State ***/
        /*******************************/

        _collectionPool = ERC721Pool(new ERC721PoolFactory().deployPool(address(_collateral), address(_quote), 0.05 * 10**18));

        vm.startPrank(_borrower);
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

        uint256[] memory subsetTokenIds = new uint256[](5);
        subsetTokenIds[0] = 1;
        subsetTokenIds[1] = 3;
        subsetTokenIds[2] = 5;
        subsetTokenIds[3] = 51;
        subsetTokenIds[4] = 53;

        _subsetPool = ERC721Pool(new ERC721PoolFactory().deploySubsetPool(address(_collateral), address(_quote), subsetTokenIds, 0.05 * 10**18));

        changePrank(_borrower);
        _collateral.setApprovalForAll(address(_subsetPool), true);
        _quote.approve(address(_subsetPool), 200_000 * 1e18);

        changePrank(_bidder);
        _collateral.setApprovalForAll(address(_subsetPool), true);
        _quote.approve(address(_subsetPool), 200_000 * 1e18);

        changePrank(_lender);
        _quote.approve(address(_subsetPool), 200_000 * 1e18);
    }

    /*******************************/
    /*** ERC721 Collection Tests ***/
    /*******************************/

    /***************************/
    /*** ERC721 Subset Tests ***/
    /***************************/

    function testPledgeCollateralSubset() external {
        // check initial token balances
        assertEq(_subsetPool.pledgedCollateral(), 0);
        assertEq(_collateral.balanceOf(address(_borrower)), 52);
        assertEq(_collateral.balanceOf(address(_subsetPool)), 0);

        uint256[] memory tokenIdsToAdd = new uint256[](3);
        tokenIdsToAdd[0] = 1;
        tokenIdsToAdd[1] = 3;
        tokenIdsToAdd[2] = 5;

        // borrower deposits three NFTs into the subset pool
        changePrank(_borrower);
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(_borrower), address(_subsetPool), 1);
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(_borrower), address(_subsetPool), 3);
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(_borrower), address(_subsetPool), 5);
        vm.expectEmit(true, true, false, true);
        emit PledgeCollateralNFT(address(_borrower), tokenIdsToAdd);
        _subsetPool.pledgeCollateral(tokenIdsToAdd, address(0), address(0));

        // check token balances after add
        assertEq(_subsetPool.pledgedCollateral(), Maths.wad(3));
        assertEq(_collateral.balanceOf(address(_borrower)), 49);
        assertEq(_collateral.balanceOf(address(_subsetPool)), 3);
    }

    function testPledgeCollateralNotInSubset() external {
        uint256[] memory tokenIdsToAdd = new uint256[](3);
        tokenIdsToAdd[0] = 2;
        tokenIdsToAdd[1] = 4;
        tokenIdsToAdd[2] = 6;

        // should revert if borrower attempts to add tokens not in the pool subset
        changePrank(_borrower);
        vm.expectRevert("P:ONLY_SUBSET");
        _subsetPool.pledgeCollateral(tokenIdsToAdd, address(0), address(0));
    }

    function testPullCollateral() external {
        // check initial token balances
        assertEq(_subsetPool.pledgedCollateral(), 0);
        assertEq(_collateral.balanceOf(address(_borrower)), 52);
        assertEq(_collateral.balanceOf(address(_subsetPool)), 0);

        uint256[] memory tokenIdsToAdd = new uint256[](3);
        tokenIdsToAdd[0] = 1;
        tokenIdsToAdd[1] = 3;
        tokenIdsToAdd[2] = 5;

        // borrower deposits three NFTs into the subset pool
        changePrank(_borrower);
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(_borrower), address(_subsetPool), 1);
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(_borrower), address(_subsetPool), 3);
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(_borrower), address(_subsetPool), 5);
        vm.expectEmit(true, true, false, true);
        emit PledgeCollateralNFT(address(_borrower), tokenIdsToAdd);
        _subsetPool.pledgeCollateral(tokenIdsToAdd, address(0), address(0));

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
        emit PullCollateralNFT(address(_borrower), tokenIdsToRemove);
        _subsetPool.pullCollateral(tokenIdsToRemove, address(0), address(0));

        // check token balances after remove
        assertEq(_subsetPool.pledgedCollateral(), Maths.wad(1));
        assertEq(_collateral.balanceOf(address(_borrower)), 51);
        assertEq(_collateral.balanceOf(address(_subsetPool)), 1);
    }

    // TODO: finish implementing
    function testPullCollateralNotInPool() external {
        uint256[] memory tokenIdsToAdd = new uint256[](3);
        tokenIdsToAdd[0] = 1;
        tokenIdsToAdd[1] = 3;
        tokenIdsToAdd[2] = 5;

        changePrank(_borrower);
        _subsetPool.pledgeCollateral(tokenIdsToAdd, address(0), address(0));

        // should revert if borrower attempts to remove collateral not in pool
        uint256[] memory tokenIdsToRemove = new uint256[](1);
        tokenIdsToRemove[0] = 51;
        vm.expectRevert("P:T_NOT_IN_P");
        _subsetPool.pullCollateral(tokenIdsToRemove, address(0), address(0));

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
        emit PullCollateralNFT(address(_borrower), tokenIdsToRemove);
        _subsetPool.pullCollateral(tokenIdsToRemove, address(0), address(0));
    }

    function testPullCollateralPartiallyEncumbered() external {
        // lender deposits 10000 Quote into 3 buckets
        _subsetPool.addQuoteToken(10_000 * 1e18, 2550);
        _subsetPool.addQuoteToken(10_000 * 1e18, 2551);
        _subsetPool.addQuoteToken(10_000 * 1e18, 2552);

        // check initial token balances
        assertEq(_subsetPool.pledgedCollateral(), 0);
        assertEq(_collateral.balanceOf(address(_borrower)), 52);
        assertEq(_collateral.balanceOf(address(_subsetPool)), 0);

        assertEq(_quote.balanceOf(address(_subsetPool)),   30_000 * 1e18);
        assertEq(_quote.balanceOf(address(_borrower)), 0);

        // check pool state
        assertEq(_subsetPool.htp(), 0);
        assertEq(_subsetPool.lup(), BucketMath.MAX_PRICE);

        assertEq(_subsetPool.poolSize(),         30_000 * 1e18);
        assertEq(_subsetPool.exchangeRate(2550), 1 * 1e27);

        uint256[] memory tokenIdsToAdd = new uint256[](3);
        tokenIdsToAdd[0] = 1;
        tokenIdsToAdd[1] = 3;
        tokenIdsToAdd[2] = 5;

        // borrower deposits three NFTs into the subset pool
        changePrank(_borrower);
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(_borrower), address(_subsetPool), 1);
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(_borrower), address(_subsetPool), 3);
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(_borrower), address(_subsetPool), 5);
        vm.expectEmit(true, true, false, true);
        emit PledgeCollateralNFT(address(_borrower), tokenIdsToAdd);
        _subsetPool.pledgeCollateral(tokenIdsToAdd, address(0), address(0));

        // TODO: determine how to handle checking both token types of Transfer
        // emit Transfer(address(_borrower), address(_subsetPool), 5);
        vm.expectEmit(true, true, false, true);
        emit Borrow(address(_borrower), _subsetPool.indexToPrice(2550), 3_000 * 1e18);
        _subsetPool.borrow(3_000 * 1e18, 2551, address(0), address(0));

        // check token balances after borrow
        assertEq(_subsetPool.pledgedCollateral(), Maths.wad(3));
        assertEq(_collateral.balanceOf(address(_borrower)), 49);
        assertEq(_collateral.balanceOf(address(_subsetPool)), 3);

        assertEq(_quote.balanceOf(address(_subsetPool)),   27_000 * 1e18);
        assertEq(_quote.balanceOf(address(_borrower)), 3_000 * 1e18);

        // check pool state
        assertEq(_subsetPool.htp(), 1000.961538461538462000 * 1e18);
        assertEq(_subsetPool.lup(), _subsetPool.indexToPrice(2550));

        assertEq(_subsetPool.poolSize(),         30_000 * 1e18);
        assertEq(_subsetPool.exchangeRate(2550), 1 * 1e27);

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
        emit PullCollateralNFT(address(_borrower), tokenIdsToRemove);
        _subsetPool.pullCollateral(tokenIdsToRemove, address(0), address(0));

        // check token balances after remove
        assertEq(_subsetPool.pledgedCollateral(), Maths.wad(1));
        assertEq(_collateral.balanceOf(address(_borrower)), 51);
        assertEq(_collateral.balanceOf(address(_subsetPool)), 1);

        assertEq(_quote.balanceOf(address(_subsetPool)),   27_000 * 1e18);
        assertEq(_quote.balanceOf(address(_borrower)), 3_000 * 1e18);

        // check pool state
        assertEq(_subsetPool.htp(), 3002.884615384615386000 * 1e18);
        assertEq(_subsetPool.lup(), _subsetPool.indexToPrice(2550));

        assertEq(_subsetPool.poolSize(),         30_000 * 1e18);
        assertEq(_subsetPool.exchangeRate(2550), 1 * 1e27);

    }

    function testPullCollateralOverlyEncumbered() external {
        // lender deposits 10000 Quote into 3 buckets
        _subsetPool.addQuoteToken(10_000 * 1e18, 2550);
        _subsetPool.addQuoteToken(10_000 * 1e18, 2551);
        _subsetPool.addQuoteToken(10_000 * 1e18, 2552);

        uint256[] memory tokenIdsToAdd = new uint256[](3);
        tokenIdsToAdd[0] = 1;
        tokenIdsToAdd[1] = 3;
        tokenIdsToAdd[2] = 5;

        // borrower deposits three NFTs into the subset pool
        changePrank(_borrower);
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(_borrower), address(_subsetPool), 1);
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(_borrower), address(_subsetPool), 3);
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(_borrower), address(_subsetPool), 5);
        vm.expectEmit(true, true, false, true);
        emit PledgeCollateralNFT(address(_borrower), tokenIdsToAdd);
        _subsetPool.pledgeCollateral(tokenIdsToAdd, address(0), address(0));

        // check collateralization after pledge
        assertEq(_subsetPool.encumberedCollateral(_subsetPool.borrowerDebt(), _subsetPool.lup()), 0);

        // borrower borrows some quote
        vm.expectEmit(true, true, false, true);
        emit Borrow(address(_borrower), _subsetPool.indexToPrice(2550), 9_000 * 1e18);
        _subsetPool.borrow(9_000 * 1e18, 2551, address(0), address(0));

        // check collateralization after borrow
        assertEq(_subsetPool.encumberedCollateral(_subsetPool.borrowerDebt(), _subsetPool.lup()), 2.992021560300836411 * 1e18);

        // should revert if borrower attempts to pull more collateral than is unencumbered
        uint256[] memory tokenIdsToRemove = new uint256[](2);
        tokenIdsToRemove[0] = 3;
        tokenIdsToRemove[1] = 5;

        vm.expectRevert("S:PC:NOT_ENOUGH_COLLATERAL");
        _subsetPool.pullCollateral(tokenIdsToRemove, address(0), address(0));


    }

}
