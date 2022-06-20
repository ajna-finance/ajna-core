// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.14;

import { ERC721Pool }        from "../../ERC721Pool.sol";
import { ERC721PoolFactory } from "../../ERC721PoolFactory.sol";

import { IPool } from "../../interfaces/IPool.sol";

import { DSTestPlus }                                         from "../utils/DSTestPlus.sol";
import { NFTCollateralToken, QuoteToken }                     from "../utils/Tokens.sol";
import { UserWithNFTCollateral, UserWithQuoteTokenInNFTPool } from "../utils/Users.sol";

import { Maths } from "../../libraries/Maths.sol";

contract ERC721PoolBidTest is DSTestPlus {

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
        _bidder     = new UserWithNFTCollateral();
        _borrower   = new UserWithNFTCollateral();

        _quote.mint(address(_lender), 200_000 * 1e18);
        _collateral.mint(address(_borrower), 60);
        _collateral.mint(address(_bidder), 5);

        _NFTCollectionPoolAddress = new ERC721PoolFactory().deployNFTCollectionPool(address(_collateral), address(_quote), 0.05 * 10**18);
        _NFTCollectionPool        = ERC721Pool(_NFTCollectionPoolAddress);

        _tokenIds = new uint256[](4);

        _tokenIds[0] = 1;
        _tokenIds[1] = 5;
        _tokenIds[2] = 50;
        _tokenIds[3] = 61;

        _NFTSubsetPoolAddress = new ERC721PoolFactory().deployNFTSubsetPool(address(_collateral), address(_quote), _tokenIds, 0.05 * 10**18);
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

    /**
     *  @notice Lender deposits 13000 quote accross 2 buckets and borrower borrows 5000.
     *          Bidder successfully purchases 4000 quote in 1 purchase for 1 NFT.
     */
    function testPurchaseBidNFTSubset() external {
        // add initial quote tokens to pool
        _lender.addQuoteToken(_NFTSubsetPool, address(_lender), 10_000 * 1e18, _p4000);
        _lender.addQuoteToken(_NFTSubsetPool, address(_lender), 3_000 * 1e18, _p3010);

        // add iniitial collateral to pool
        vm.prank((address(_borrower)));
        uint[] memory tokens = new uint[](1);
        tokens[0] = 1;
        _NFTSubsetPool.addCollateral(tokens);
        vm.prank((address(_borrower)));
        tokens = new uint[](1);
        tokens[0] = 5;
        _NFTSubsetPool.addCollateral(tokens);
        vm.prank((address(_borrower)));
        tokens = new uint[](1);
        tokens[0] = 50;
        _NFTSubsetPool.addCollateral(tokens);
        assertEq(_NFTSubsetPool.getCollateralDeposited().length, 3);

        // borrow from pool
        vm.expectEmit(true, true, false, true);
        emit Borrow(address(_borrower), _p4000, 5_000 * 1e18);
        _borrower.borrow(_NFTSubsetPool, 5_000 * 1e18, _p2503);

        // check initial pool state after borrow and before bid
        assertEq(_NFTSubsetPool.lup(),                          _p4000);
        assertEq(_collateral.balanceOf(address(_bidder)),        5);
        assertEq(_quote.balanceOf(address(_bidder)),             0);
        assertEq(_collateral.balanceOf(address(_NFTSubsetPool)), 3);
        assertEq(_quote.balanceOf(address(_NFTSubsetPool)),      8_000 * 1e18);
        assertEq(_NFTSubsetPool.totalQuoteToken(),               8_000 * 1e18);
        assertEq(_NFTSubsetPool.totalCollateral(),               3 * 1e18);
        assertEq(_NFTSubsetPool.totalDebt(),                     5_000.000961538461538462 * 1e18);
        assertEq(_NFTSubsetPool.getPoolCollateralization(),      2.400556145502927926 * 1e18);
        assertEq(_NFTSubsetPool.getPoolActualUtilization(),      0.407908729305961901 * 1e18);

        _tokenIds = new uint256[](1);
        _tokenIds[0] = 61;

        // should revert if invalid price
        vm.expectRevert("BM:PTI:OOB");
        _bidder.purchaseBid(_NFTSubsetPool, _p1, 1_000, _tokenIds);

        // should revert if trying to use collateral not in the allowed subset
        uint256[] memory _invalidTokenIds = new uint256[](2);
        _invalidTokenIds[0] = 61;
        _invalidTokenIds[1] = 62;
        vm.expectRevert("P:ONLY_SUBSET");
        _bidder.purchaseBid(_NFTSubsetPool, 5_100 * 1e18, _p8002, _invalidTokenIds);

        // should revert if bidder doesn't have enough collateral
        vm.expectRevert("P:PB:INSUF_COLLAT");
        _bidder.purchaseBid(_NFTSubsetPool, 2_000_000 * 1e18, _p4000, _tokenIds);

        // should revert if trying to purchase more than on bucket
        vm.expectRevert("B:PB:INSUF_BUCKET_LIQ");
        vm.prank((address(_bidder)));
        _bidder.purchaseBid(_NFTSubsetPool, 5_100 * 1e18, _p8002, _tokenIds);

        // check 4_000.927678580567537368 bucket balance before purchase bid
        (, , , uint256 deposit, uint256 debt, , , uint256 bucketCollateral) = _NFTSubsetPool.bucketAt(_p4000);
        assertEq(deposit,          5_000 * 1e18);
        assertEq(debt,             5_000.000961538461538462 * 1e18);
        assertEq(bucketCollateral, 0);

        // purchase 4000 bid from p4000 bucket
        vm.expectEmit(true, true, false, true);
        emit Transfer(_NFTSubsetPoolAddress, address(_bidder), 4_000 * 1e18);
        vm.expectEmit(true, true, false, true);
        emit PurchaseWithNFTs(address(_bidder), _p4000, 4_000 * 1e18, _tokenIds);
        vm.prank((address(_bidder)));
        _bidder.purchaseBid(_NFTSubsetPool, 4_000 * 1e18, _p4000, _tokenIds);

        // check 4_000.927678580567537368 bucket balance after purchase bid
        (, , , deposit, debt, , , bucketCollateral) = _NFTSubsetPool.bucketAt(_p4000);
        assertEq(deposit,          1_000 * 1e18);
        assertEq(debt,             5_000.000961538461538462 * 1e18);
        assertEq(bucketCollateral, Maths.WAD);

        // check  3_010.892022197881557845 bucket balance after purchase bid
        (, , , deposit, debt, , , bucketCollateral) = _NFTSubsetPool.bucketAt(_p3010);
        assertEq(deposit,          3_000 * 1e18);
        assertEq(debt,             0);
        assertEq(bucketCollateral, 0);

        // check bidder and pool balances
        assertEq(_NFTSubsetPool.lup(),                          _p4000);
        assertEq(_NFTSubsetPool.getPoolCollateralization(),      3.200741527337237234 * 1e18);
        assertEq(_NFTSubsetPool.getPoolActualUtilization(),      0.605499524670794045 * 1e18);
        assertEq(_collateral.balanceOf(address(_bidder)),        4);
        assertEq(_quote.balanceOf(address(_bidder)),             4_000 * 1e18);
        assertEq(_collateral.balanceOf(address(_NFTSubsetPool)), 4);
        assertEq(_quote.balanceOf(address(_NFTSubsetPool)),      4_000 * 1e18);
        assertEq(_NFTSubsetPool.totalQuoteToken(),               4_000 * 1e18);
        assertEq(_NFTSubsetPool.totalCollateral(),               4 * 1e18);
        assertEq(_NFTSubsetPool.totalDebt(),                     5_000.000961538461538462 * 1e18);
    }

}
