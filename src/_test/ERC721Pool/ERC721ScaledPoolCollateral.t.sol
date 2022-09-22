// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.14;

import { ERC721Pool }        from "../../erc721/ERC721Pool.sol";
import { ERC721PoolFactory } from "../../erc721/ERC721PoolFactory.sol";

import { IERC721Pool } from "../../erc721/interfaces/IERC721Pool.sol";
import { IScaledPool } from "../../base/interfaces/IScaledPool.sol";

import { BucketMath } from "../../libraries/BucketMath.sol";
import { Maths }      from "../../libraries/Maths.sol";

import { ERC721HelperContract } from "./ERC721DSTestPlus.sol";

// TODO: pass different pool type to enable collection + subset test simplification
contract ERC721ScaledCollateralTest is ERC721HelperContract {

    address internal _borrower;
    address internal _borrower2;
    address internal _lender;
    address internal _lender2;

    function setUp() external {
        _borrower  = makeAddr("borrower");
        _borrower2 = makeAddr("borrower2");
        _lender    = makeAddr("lender");
        _lender2   = makeAddr("lender2");

        // deploy collection pool
        ERC721Pool collectionPool = _deployCollectionPool();

        // deploy subset pool
        uint256[] memory subsetTokenIds = new uint256[](5);
        subsetTokenIds[0] = 1;
        subsetTokenIds[1] = 3;
        subsetTokenIds[2] = 5;
        subsetTokenIds[3] = 51;
        subsetTokenIds[4] = 53;
        _pool = _deploySubsetPool(subsetTokenIds);

        _mintAndApproveQuoteTokens(_lender, 200_000 * 1e18);

        _mintAndApproveCollateralTokens(_borrower,  52);
        _mintAndApproveCollateralTokens(_borrower2, 53);
    }

    /*******************************/
    /*** ERC721 Collection Tests ***/
    /*******************************/

    /***************************/
    /*** ERC721 Subset Tests ***/
    /***************************/

    function testPledgeCollateralSubset() external {
        // check initial token balances
        assertEq(_pool.pledgedCollateral(),             0);
        assertEq(_collateral.balanceOf(_borrower),            52);
        assertEq(_collateral.balanceOf(address(_pool)), 0);

        uint256[] memory tokenIdsToAdd = new uint256[](3);
        tokenIdsToAdd[0] = 1;
        tokenIdsToAdd[1] = 3;
        tokenIdsToAdd[2] = 5;

        // borrower deposits three NFTs into the subset pool
        changePrank(_borrower);
        vm.expectEmit(true, true, false, true);
        emit PledgeCollateralNFT(_borrower, tokenIdsToAdd);
        vm.expectEmit(true, true, false, true);
        emit Transfer(_borrower, address(_pool), 1);
        vm.expectEmit(true, true, false, true);
        emit Transfer(_borrower, address(_pool), 3);
        vm.expectEmit(true, true, false, true);
        emit Transfer(_borrower, address(_pool), 5);
        _pool.pledgeCollateral(_borrower, tokenIdsToAdd);

        // check token balances after add
        assertEq(_pool.pledgedCollateral(),             Maths.wad(3));
        assertEq(_collateral.balanceOf(_borrower),            49);
        assertEq(_collateral.balanceOf(address(_pool)), 3);
    }

    function testPledgeCollateralNotInSubset() external {
        uint256[] memory tokenIdsToAdd = new uint256[](3);
        tokenIdsToAdd[0] = 2;
        tokenIdsToAdd[1] = 4;
        tokenIdsToAdd[2] = 6;

        // should revert if borrower attempts to add tokens not in the pool subset
        changePrank(_borrower);
        vm.expectRevert(IERC721Pool.OnlySubset.selector);
        _pool.pledgeCollateral(_borrower, tokenIdsToAdd);
    }

    function testPledgeCollateralInSubsetFromDifferentActor() external {
        // check initial token balances
        assertEq(_pool.pledgedCollateral(),             0);
        assertEq(_collateral.balanceOf(_borrower),            52);
        assertEq(_collateral.balanceOf(_borrower2),           53);
        assertEq(_collateral.balanceOf(address(_pool)), 0);

        (, , uint256 col, , ) = _pool.borrowerInfo(_borrower);
        assertEq(col,  0);
        (, , col, , ) = _pool.borrowerInfo(_borrower2);
        assertEq(col,  0);

        uint256[] memory tokenIdsToAdd = new uint256[](1);
        tokenIdsToAdd[0] = 53;

        // borrower deposits three NFTs into the subset pool
        changePrank(_borrower2);
        _collateral.setApprovalForAll(address(_pool), true);
        vm.expectEmit(true, true, false, true);
        emit PledgeCollateralNFT(_borrower, tokenIdsToAdd);
        vm.expectEmit(true, true, false, true);
        emit Transfer(_borrower2, address(_pool), 53);
        _pool.pledgeCollateral(_borrower, tokenIdsToAdd);

        // check token balances after add
        assertEq(_pool.pledgedCollateral(),             Maths.wad(1));
        assertEq(_collateral.balanceOf(_borrower),            52);
        assertEq(_collateral.balanceOf(_borrower2),           52);
        assertEq(_collateral.balanceOf(address(_pool)), 1);

        (, , col, , ) = _pool.borrowerInfo(_borrower);
        assertEq(col,  1 * 1e18);
        (, , col, , ) = _pool.borrowerInfo(_borrower2);
        assertEq(col,  0);
    }

    function testPullCollateral() external {
        // check initial token balances
        assertEq(_pool.pledgedCollateral(),             0);
        assertEq(_collateral.balanceOf(_borrower),            52);
        assertEq(_collateral.balanceOf(_borrower2),           53);
        assertEq(_collateral.balanceOf(address(_pool)), 0);

        uint256[] memory tokenIdsToAdd = new uint256[](3);
        tokenIdsToAdd[0] = 1;
        tokenIdsToAdd[1] = 3;
        tokenIdsToAdd[2] = 5;

        // borrower deposits three NFTs into the subset pool
        changePrank(_borrower);
        vm.expectEmit(true, true, false, true);
        emit PledgeCollateralNFT(_borrower, tokenIdsToAdd);
        vm.expectEmit(true, true, false, true);
        emit Transfer(_borrower, address(_pool), 1);
        vm.expectEmit(true, true, false, true);
        emit Transfer(_borrower, address(_pool), 3);
        vm.expectEmit(true, true, false, true);
        emit Transfer(_borrower, address(_pool), 5);
        _pool.pledgeCollateral(_borrower, tokenIdsToAdd);

        // check token balances after add
        assertEq(_pool.pledgedCollateral(),             Maths.wad(3));
        assertEq(_collateral.balanceOf(_borrower),            49);
        assertEq(_collateral.balanceOf(_borrower2),           53);
        assertEq(_collateral.balanceOf(address(_pool)), 3);

        uint256[] memory tokenIdsToRemove = new uint256[](1);
        tokenIdsToRemove[0] = 3;

        // should fail if trying to pull collateral by an address without pledged collateral
        changePrank(_lender);
        vm.expectRevert(IScaledPool.RemoveCollateralInsufficientCollateral.selector);
        _pool.pullCollateral(tokenIdsToRemove);

        changePrank(_borrower2);
        tokenIdsToAdd = new uint256[](1);
        tokenIdsToAdd[0] = 53;
        _pool.pledgeCollateral(_borrower2, tokenIdsToAdd);

        // check token balances after add
        assertEq(_pool.pledgedCollateral(),             Maths.wad(4));
        assertEq(_collateral.balanceOf(_borrower),            49);
        assertEq(_collateral.balanceOf(_borrower2),           52);
        assertEq(_collateral.balanceOf(address(_pool)), 4);

        // should fail if trying to pull collateral by an address that pledged different collateral
        vm.expectRevert(IERC721Pool.RemoveTokenFailed.selector);
        _pool.pullCollateral(tokenIdsToRemove);

        tokenIdsToRemove = new uint256[](2);
        tokenIdsToRemove[0] = 3;
        tokenIdsToRemove[1] = 5;

        // borrower removes some of their deposted NFTS from the pool
        changePrank(_borrower);
        vm.expectEmit(true, true, false, true);
        emit PullCollateralNFT(_borrower, tokenIdsToRemove);
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(_pool), _borrower, 3);
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(_pool), _borrower, 5);
        _pool.pullCollateral(tokenIdsToRemove);

        // check token balances after remove
        assertEq(_pool.pledgedCollateral(),             Maths.wad(2));
        assertEq(_collateral.balanceOf(_borrower),            51);
        assertEq(_collateral.balanceOf(address(_pool)), 2);

        // should fail if borrower tries to pull again same NFTs
        vm.expectRevert(IScaledPool.RemoveCollateralInsufficientCollateral.selector);
        _pool.pullCollateral(tokenIdsToRemove);
    }

    // TODO: finish implementing
    function testPullCollateralNotInPool() external {
        uint256[] memory tokenIdsToAdd = new uint256[](3);
        tokenIdsToAdd[0] = 1;
        tokenIdsToAdd[1] = 3;
        tokenIdsToAdd[2] = 5;

        changePrank(_borrower);
        _pool.pledgeCollateral(_borrower, tokenIdsToAdd);

        // should revert if borrower attempts to remove collateral not in pool
        uint256[] memory tokenIdsToRemove = new uint256[](1);
        tokenIdsToRemove[0] = 51;

        vm.expectRevert(IERC721Pool.TokenNotDeposited.selector);
        _pool.pullCollateral(tokenIdsToRemove);

        // borrower should be able to remove collateral in the pool
        tokenIdsToRemove = new uint256[](3);
        tokenIdsToRemove[0] = 1;
        tokenIdsToRemove[1] = 3;
        tokenIdsToRemove[2] = 5;

        vm.expectEmit(true, true, false, true);
        vm.expectEmit(true, true, false, true);
        emit PullCollateralNFT(_borrower, tokenIdsToRemove);
        emit Transfer(address(_pool), _borrower, 1);
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(_pool), _borrower, 3);
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(_pool), _borrower, 5);
        _pool.pullCollateral(tokenIdsToRemove);
    }

    function testPullCollateralPartiallyEncumbered() external {
        vm.startPrank(_lender);
        // lender deposits 10000 Quote into 3 buckets
        _pool.addQuoteToken(10_000 * 1e18, 2550);
        _pool.addQuoteToken(10_000 * 1e18, 2551);
        _pool.addQuoteToken(10_000 * 1e18, 2552);

        // check initial token balances
        assertEq(_pool.pledgedCollateral(),             0);
        assertEq(_collateral.balanceOf(_borrower),            52);
        assertEq(_collateral.balanceOf(address(_pool)), 0);

        assertEq(_quote.balanceOf(address(_pool)), 30_000 * 1e18);
        assertEq(_quote.balanceOf(_borrower),            0);

        // check pool state
        assertEq(_htp(), 0);
        assertEq(_lup(), BucketMath.MAX_PRICE);

        assertEq(_poolSize(),         30_000 * 1e18);
        assertEq(_exchangeRate(2550), 1 * 1e27);

        uint256[] memory tokenIdsToAdd = new uint256[](3);
        tokenIdsToAdd[0] = 1;
        tokenIdsToAdd[1] = 3;
        tokenIdsToAdd[2] = 5;

        // borrower deposits three NFTs into the subset pool
        changePrank(_borrower);
        vm.expectEmit(true, true, false, true);
        emit PledgeCollateralNFT(_borrower, tokenIdsToAdd);
        vm.expectEmit(true, true, false, true);
        emit Transfer(_borrower, address(_pool), 1);
        vm.expectEmit(true, true, false, true);
        emit Transfer(_borrower, address(_pool), 3);
        vm.expectEmit(true, true, false, true);
        emit Transfer(_borrower, address(_pool), 5);
        _pool.pledgeCollateral(_borrower, tokenIdsToAdd);

        // TODO: determine how to handle checking both token types of Transfer
        // emit Transfer(_borrower, address(_subsetPool), 5);
        vm.expectEmit(true, true, false, true);
        emit Borrow(_borrower, _indexToPrice(2550), 3_000 * 1e18);
        _pool.borrow(3_000 * 1e18, 2551);

        // check token balances after borrow
        assertEq(_pool.pledgedCollateral(),             Maths.wad(3));
        assertEq(_collateral.balanceOf(_borrower),            49);
        assertEq(_collateral.balanceOf(address(_pool)), 3);

        assertEq(_quote.balanceOf(address(_pool)), 27_000 * 1e18);
        assertEq(_quote.balanceOf(_borrower),            3_000 * 1e18);

        // check pool state
        assertEq(_htp(), 1000.961538461538462000 * 1e18);
        assertEq(_lup(), _indexToPrice(2550));

        assertEq(_poolSize(),         30_000 * 1e18);
        assertEq(_exchangeRate(2550), 1 * 1e27);

        // remove some unencumbered collateral
        uint256[] memory tokenIdsToRemove = new uint256[](2);
        tokenIdsToRemove[0] = 3;
        tokenIdsToRemove[1] = 5;

        // borrower removes some of their deposted NFTS from the pool
        vm.expectEmit(true, true, false, true);
        emit PullCollateralNFT(_borrower, tokenIdsToRemove);
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(_pool), _borrower, 3);
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(_pool), _borrower, 5);
        _pool.pullCollateral(tokenIdsToRemove);

        // check token balances after remove
        assertEq(_pool.pledgedCollateral(),             Maths.wad(1));
        assertEq(_collateral.balanceOf(_borrower),            51);
        assertEq(_collateral.balanceOf(address(_pool)), 1);

        assertEq(_quote.balanceOf(address(_pool)), 27_000 * 1e18);
        assertEq(_quote.balanceOf(_borrower),            3_000 * 1e18);

        // check pool state
        assertEq(_htp(), 3002.884615384615386000 * 1e18);
        assertEq(_lup(), _indexToPrice(2550));

        assertEq(_poolSize(),         30_000 * 1e18);
        assertEq(_exchangeRate(2550), 1 * 1e27);

    }

    function testPullCollateralOverlyEncumbered() external {
        vm.startPrank(_lender);
        // lender deposits 10000 Quote into 3 buckets
        _pool.addQuoteToken(10_000 * 1e18, 2550);
        _pool.addQuoteToken(10_000 * 1e18, 2551);
        _pool.addQuoteToken(10_000 * 1e18, 2552);

        uint256[] memory tokenIdsToAdd = new uint256[](3);
        tokenIdsToAdd[0] = 1;
        tokenIdsToAdd[1] = 3;
        tokenIdsToAdd[2] = 5;

        // borrower deposits three NFTs into the subset pool
        changePrank(_borrower);
        vm.expectEmit(true, true, false, true);
        emit PledgeCollateralNFT(_borrower, tokenIdsToAdd);
        vm.expectEmit(true, true, false, true);
        emit Transfer(_borrower, address(_pool), 1);
        vm.expectEmit(true, true, false, true);
        emit Transfer(_borrower, address(_pool), 3);
        vm.expectEmit(true, true, false, true);
        emit Transfer(_borrower, address(_pool), 5);
        _pool.pledgeCollateral(_borrower, tokenIdsToAdd);

        // check collateralization after pledge
        assertEq(_pool.encumberedCollateral(_pool.borrowerDebt(), _lup()), 0);

        // borrower borrows some quote
        vm.expectEmit(true, true, false, true);
        emit Borrow(_borrower, _indexToPrice(2550), 9_000 * 1e18);
        _pool.borrow(9_000 * 1e18, 2551);

        // check collateralization after borrow
        assertEq(_pool.encumberedCollateral(_pool.borrowerDebt(), _lup()), 2.992021560300836411 * 1e18);

        // should revert if borrower attempts to pull more collateral than is unencumbered
        uint256[] memory tokenIdsToRemove = new uint256[](2);
        tokenIdsToRemove[0] = 3;
        tokenIdsToRemove[1] = 5;

        vm.expectRevert(IScaledPool.RemoveCollateralInsufficientCollateral.selector);
        _pool.pullCollateral(tokenIdsToRemove);
    }

    function testAddRemoveCollateral() external {
        vm.startPrank(_lender);
        // lender adds some liquidity
        _pool.addQuoteToken(10_000 * 1e18, 1530);
        _pool.addQuoteToken(10_000 * 1e18, 1692);

        uint256[] memory tokenIds = new uint256[](2);
        tokenIds[0] = 1;
        tokenIds[1] = 5;

        // add three tokens to a single bucket
        changePrank(_borrower);
        vm.expectEmit(true, true, false, true);
        emit AddCollateralNFT(_borrower, 1530, tokenIds);
        _pool.addCollateral(tokenIds, 1530);

        // should revert if the actor does not have any LP to remove a token
        changePrank(_borrower2);
        tokenIds = new uint256[](1);
        tokenIds[0] = 1;
        vm.expectRevert(IScaledPool.RemoveCollateralInsufficientLP.selector);
        _pool.removeCollateral(tokenIds, 1530);

        // should revert if we try to remove a token from a bucket with no collateral
        changePrank(_borrower);
        tokenIds[0] = 1;
        vm.expectRevert(IScaledPool.RemoveCollateralInsufficientCollateral.selector);
        _pool.removeCollateral(tokenIds, 1692);

        // remove one token
        tokenIds[0] = 5;
        emit RemoveCollateralNFT(_borrower, _indexToPrice(1530), tokenIds);
        _pool.removeCollateral(tokenIds, 1530);
        (, , uint256 collateral, , , , ) = _pool.bucketAt(1530);
        assertEq(collateral, 1 * 1e18);

        // remove another token
        tokenIds[0] = 1;
        emit RemoveCollateralNFT(_borrower, _indexToPrice(1530), tokenIds);
        _pool.removeCollateral(tokenIds, 1530);
        (, , collateral, , , , ) = _pool.bucketAt(1530);
        assertEq(collateral, 0);
        (uint256 lpb, ) = _pool.lenders(1530, _borrower);
        assertEq(lpb, 0);

        // lender removes quote token
        changePrank(_lender);
        _pool.removeAllQuoteToken(1530);
        (, , collateral, lpb, , , ) = _pool.bucketAt(1530);
        assertEq(collateral, 0);
        assertEq(lpb, 0);
    }
}
