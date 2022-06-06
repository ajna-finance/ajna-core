// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.11;

import { ERC721Pool }        from "../../ERC721Pool.sol";
import { ERC721PoolFactory } from "../../ERC721PoolFactory.sol";

import { IPool } from "../../interfaces/IPool.sol";

import { DSTestPlus }                                         from "../utils/DSTestPlus.sol";
import { NFTCollateralToken, QuoteToken }                     from "../utils/Tokens.sol";
import { UserWithNFTCollateral, UserWithQuoteTokenInNFTPool } from "../utils/Users.sol";

import { Maths } from "../../libraries/Maths.sol";

contract ERC721PoolCollateralTest is DSTestPlus {

    address                     internal _NFTCollectionPoolAddress;
    address                     internal _NFTSubsetPoolAddress;
    ERC721Pool                  internal _NFTCollectionPool;
    ERC721Pool                  internal _NFTSubsetPool;
    NFTCollateralToken          internal _collateral;
    QuoteToken                  internal _quote;
    UserWithNFTCollateral       internal _bidder;
    UserWithNFTCollateral       internal _borrower;
    UserWithQuoteTokenInNFTPool internal _lender;
    uint256[]                   internal _tokenIds;

    function setUp() external {
        _collateral  = new NFTCollateralToken();
        _quote       = new QuoteToken();

        _lender     = new UserWithQuoteTokenInNFTPool();
        _bidder   = new UserWithNFTCollateral();
        _borrower   = new UserWithNFTCollateral();

        _quote.mint(address(_lender), 200_000 * 1e18);
        _collateral.mint(address(_borrower), 60);
        _collateral.mint(address(_bidder), 5);

        _NFTCollectionPoolAddress = new ERC721PoolFactory().deployNFTCollectionPool(address(_collateral), address(_quote));
        _NFTCollectionPool        = ERC721Pool(_NFTCollectionPoolAddress);

        _tokenIds = new uint256[](4);

        _tokenIds[0] = 1;
        _tokenIds[1] = 5;
        _tokenIds[2] = 50;
        _tokenIds[3] = 61;

        _NFTSubsetPoolAddress = new ERC721PoolFactory().deployNFTSubsetPool(address(_collateral), address(_quote), _tokenIds);
        _NFTSubsetPool        = ERC721Pool(_NFTSubsetPoolAddress);

        // run token approvals for NFT Collection Pool
        _lender.approveToken(_quote, _NFTCollectionPoolAddress, 200_000 * 1e18);
        _borrower.approveToken(_collateral, _NFTCollectionPoolAddress, 1);

        // run token approvals for NFT Subset Pool
        _lender.approveToken(_quote, _NFTSubsetPoolAddress, 200_000 * 1e18);

        _borrower.approveToken(_collateral, _NFTSubsetPoolAddress, 1);
        _borrower.approveToken(_collateral, _NFTSubsetPoolAddress, 5);
        _borrower.approveToken(_collateral, _NFTSubsetPoolAddress, 50);

        _bidder.approveToken(_collateral, _NFTSubsetPoolAddress, 61);

        // _collateral.setApprovalForAll(_NFTSubsetPoolAddress, true);
    }

    function testAddCollateralNFTSubset() external {

        // should revert if attempt to add collateral from a tokenId outside of allowed subset
        vm.prank((address(_borrower)));
        vm.expectRevert("P:ONLY_SUBSET");
        _NFTSubsetPool.addCollateral(2);

        assertEq(_NFTSubsetPool.getCollateralDeposited().length, 0);

        // should allow adding collateral from approved subset
        vm.prank((address(_borrower)));
        _NFTSubsetPool.addCollateral(1);
        assertEq(_NFTSubsetPool.getCollateralDeposited().length, 1);
    }

    function testRemoveCollateralNFTSubset() external {
        // should revert if trying to remove collateral when none are available
        vm.expectRevert("P:RC:AMT_GT_AVAIL_COLLAT");
        _borrower.removeCollateral(_NFTSubsetPool, 1);

        // add initial quote tokens to pool
        _lender.addQuoteToken(_NFTSubsetPool, address(_lender), 10_000 * 1e18, _p4000);

        // add iniitial collateral to pool
        vm.prank((address(_borrower)));
        _NFTSubsetPool.addCollateral(1);
        vm.prank((address(_borrower)));
        _NFTSubsetPool.addCollateral(5);
        vm.prank((address(_borrower)));
        _NFTSubsetPool.addCollateral(50);
        assertEq(_NFTSubsetPool.getCollateralDeposited().length, 3);
  
        // borrow from pool
        vm.expectEmit(true, true, false, true);
        emit Borrow(address(_borrower), _p4000, 5_000 * 1e18);
        _borrower.borrow(_NFTSubsetPool, 5_000 * 1e18, _p2503);

        // remove collateral
        vm.prank((address(_borrower)));
        _NFTSubsetPool.removeCollateral(1);
        assertEq(_NFTSubsetPool.getCollateralDeposited().length, 2);

        // should fail to remove collateral that would result in undercollateralization of the pool
        vm.prank((address(_borrower)));
        vm.expectRevert("P:RC:AMT_GT_AVAIL_COLLAT");
        _NFTSubsetPool.removeCollateral(5);
    }

    function testClaimCollateralNFTSubset() external {
        // add initial quote tokens to pool
        _lender.addQuoteToken(_NFTSubsetPool, address(_lender), 10_000 * 1e18, _p4000);

        // add iniitial collateral to pool
        vm.prank((address(_borrower)));
        _NFTSubsetPool.addCollateral(1);
        vm.prank((address(_borrower)));
        _NFTSubsetPool.addCollateral(5);
        vm.prank((address(_borrower)));
        _NFTSubsetPool.addCollateral(50);
        assertEq(_NFTSubsetPool.getCollateralDeposited().length, 3);
  
        // borrow from pool
        vm.expectEmit(true, true, false, true);
        emit Borrow(address(_borrower), _p4000, 5_000 * 1e18);
        _borrower.borrow(_NFTSubsetPool, 5_000 * 1e18, _p2503);

        // pass time to allow interest to accrue
        skip(82000);

        // should fail if invalid price
        vm.expectRevert("P:CC:INVALID_PRICE");
        _lender.claimCollateral(_NFTSubsetPool, address(_lender), 10_000 * 1e18, 4_000 * 1e18);

        // should revert if no lp tokens in bucket
        vm.expectRevert("P:CC:NO_CLAIM_TO_BUCKET");
        _lender.claimCollateral(_NFTSubsetPool, address(_lender), 1 * 1e18, _p2503);

        // should revert if attempting to claim more collateral than is available
        vm.prank((address(_lender)));
        vm.expectRevert("B:CC:AMT_GT_COLLAT");
        _NFTSubsetPool.claimCollateral(address(_lender), 1, _p4000);

        // bidder purchases some of the top bucket
        _tokenIds = new uint256[](1);
        _tokenIds[0] = 61;
        vm.expectEmit(true, true, false, true);
        emit Purchase(address(_bidder), _p4000, 4_000 * 1e18, Maths.ONE_WAD);
        vm.prank((address(_bidder)));
        _bidder.purchaseBidNFTCollateral(_NFTSubsetPool, 4_000 * 1e18, _p4000, _tokenIds);

        // check balances after purchase bid
        assertEq(_collateral.balanceOf(address(_lender)),     0);
        assertEq(_NFTSubsetPool.lpBalance(address(_lender), _p4000), 10_000 * 1e27);
        assertEq(_collateral.balanceOf(address(_bidder)),     4);
        assertEq(_collateral.balanceOf(address(_NFTSubsetPool)),       4);
        assertEq(_quote.balanceOf(address(_lender)),          190_000 * 1e18);
        assertEq(_quote.balanceOf(address(_NFTSubsetPool)),            1_000 * 1e18);
        assertEq(_NFTSubsetPool.totalCollateral(),                     4);

        // check bucket state after purchase bid
        (, , , uint256 deposit, uint256 debt, , , uint256 bucketCollateral) = _NFTSubsetPool.bucketAt(_p4000);
        assertEq(deposit, 1_000 * 1e18);
        assertEq(debt,    5_000.651054657058420273 * 1e18);
        assertEq(bucketCollateral, Maths.ONE_WAD);

        // TODO: implement this check
        // should revert if claiming larger amount of collateral than LP balance allows
        // vm.expectRevert("B:CC:INSUF_LP_BAL");
        // _lender.claimCollateral(_NFTSubsetPool, address(_lender), 1, _p4000);

        // pass time to allow additional interest to accrue
        skip(8200);

        // claim collateral from p4000 bucket
        vm.prank((address(_lender)));
        _NFTSubsetPool.claimCollateral(address(_lender), 1, _p4000);

        // check balances
        assertEq(_collateral.balanceOf(address(_lender)),     1);
        // TODO: check lp balance here
        assertEq(_NFTSubsetPool.lpBalance(address(_lender), _p4000), 5_999.703861466857367095480566984 * 1e27);
        assertEq(_collateral.balanceOf(address(_bidder)),     4);
        assertEq(_collateral.balanceOf(address(_NFTSubsetPool)),       3);
        assertEq(_quote.balanceOf(address(_lender)),          190_000 * 1e18);
        assertEq(_quote.balanceOf(address(_NFTSubsetPool)),            1_000 * 1e18);
        assertEq(_NFTSubsetPool.totalCollateral(),                     3);

        // check bucket state after claim
        (, , , deposit, debt, , , bucketCollateral) = _NFTSubsetPool.bucketAt(_p4000);
        assertEq(deposit, 1_000 * 1e18);
        assertEq(debt,    5_000.651054657058420273 * 1e18);
        assertEq(bucketCollateral, 0);
    }

    // TODO: use addCollateralMultiple and claimCollateralMultiple here
    function testClaimMultipleCollateralNFTSubset() external {}

}
