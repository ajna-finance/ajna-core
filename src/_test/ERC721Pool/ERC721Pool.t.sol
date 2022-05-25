// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.11;

import { ERC721Pool }        from "../../ERC721Pool.sol";
import { ERC721PoolFactory } from "../../ERC721PoolFactory.sol";

import { IPool } from "../../interfaces/IPool.sol";

import { DSTestPlus }                                         from "../utils/DSTestPlus.sol";
import { NFTCollateralToken, QuoteToken }                     from "../utils/Tokens.sol";
import { UserWithNFTCollateral, UserWithQuoteTokenInNFTPool } from "../utils/Users.sol";

contract ERC721PoolTest is DSTestPlus {

    address                     internal _NFTCollectionPoolAddress;
    address                     internal _NFTSubsetPoolAddress;
    ERC721Pool                  internal _NFTCollectionPool;
    ERC721Pool                  internal _NFTSubsetPool;
    NFTCollateralToken          internal _collateral;
    QuoteToken                  internal _quote;
    UserWithNFTCollateral       internal _borrower;
    UserWithQuoteTokenInNFTPool internal _lender;
    uint256[]                   internal _tokenIds;

    function setUp() external {
        _collateral  = new NFTCollateralToken();
        _quote       = new QuoteToken();

        _lender     = new UserWithQuoteTokenInNFTPool();
        _borrower   = new UserWithNFTCollateral();

        _quote.mint(address(_lender), 200_000 * 1e18);
        _collateral.mint(address(_borrower), 200);

        _NFTCollectionPoolAddress = new ERC721PoolFactory().deployNFTCollectionPool(address(_collateral), address(_quote));
        _NFTCollectionPool        = ERC721Pool(_NFTCollectionPoolAddress);

        _tokenIds = new uint256[](3);

        _tokenIds[0] = 1;
        _tokenIds[1] = 5;
        _tokenIds[2] = 50;

        _NFTSubsetPoolAddress = new ERC721PoolFactory().deployNFTSubsetPool(address(_collateral), address(_quote), _tokenIds);
        _NFTSubsetPool        = ERC721Pool(_NFTSubsetPoolAddress);

        _lender.approveToken(_quote, _NFTCollectionPoolAddress, 200_000 * 1e18);
        _borrower.approveToken(_collateral, _NFTCollectionPoolAddress, 1);

        _lender.approveToken(_quote, _NFTSubsetPoolAddress, 200_000 * 1e18);
        _borrower.approveToken(_collateral, _NFTSubsetPoolAddress, 1);
        _borrower.approveToken(_collateral, _NFTSubsetPoolAddress, 5);
        _borrower.approveToken(_collateral, _NFTSubsetPoolAddress, 50);

        // _collateral.setApprovalForAll(_NFTSubsetPoolAddress, true);
    }

    // @notice:Tests pool factory inputs match the pool created
    function testDeployNFTCollectionPool() external {
        assertEq(address(_collateral), address(_NFTCollectionPool.collateral()));
        assertEq(address(_quote),      address(_NFTCollectionPool.quoteToken()));

        assert(_NFTCollectionPoolAddress != _NFTSubsetPoolAddress);
    }

    function testDeployNFTSubsetPool() external {
        assertEq(address(_collateral), address(_NFTSubsetPool.collateral()));
        assertEq(address(_quote),      address(_NFTSubsetPool.quoteToken()));

        assert(_NFTCollectionPoolAddress != _NFTSubsetPoolAddress);
    }

    function testEmptyBucketNFTCollectionPool() external {
        (
            ,
            ,
            ,
            uint256 deposit,
            uint256 debt,
            uint256 bucketInflator,
            uint256 lpOutstanding,
            uint256 bucketCollateral
        ) = _NFTCollectionPool.bucketAt(_p1004);

        assertEq(deposit,          0);
        assertEq(debt,             0);
        assertEq(bucketInflator,   0);
        assertEq(lpOutstanding,    0);
        assertEq(bucketCollateral, 0);

        (, , , deposit, debt, bucketInflator, lpOutstanding, bucketCollateral) = _NFTCollectionPool.bucketAt(_p2793);

        assertEq(deposit,          0);
        assertEq(debt,             0);
        assertEq(bucketInflator,   0);
        assertEq(lpOutstanding,    0);
        assertEq(bucketCollateral, 0);
    }

    function testEmptyBucketNFTSubsetPool() external {
        (
            ,
            ,
            ,
            uint256 deposit,
            uint256 debt,
            uint256 bucketInflator,
            uint256 lpOutstanding,
            uint256 bucketCollateral
        ) = _NFTSubsetPool.bucketAt(_p1004);

        assertEq(deposit,          0);
        assertEq(debt,             0);
        assertEq(bucketInflator,   0);
        assertEq(lpOutstanding,    0);
        assertEq(bucketCollateral, 0);

        (, , , deposit, debt, bucketInflator, lpOutstanding, bucketCollateral) = _NFTSubsetPool.bucketAt(_p2793);

        assertEq(deposit,          0);
        assertEq(debt,             0);
        assertEq(bucketInflator,   0);
        assertEq(lpOutstanding,    0);
        assertEq(bucketCollateral, 0);

        // check subset tokenIds are successfully initialized
        assertEq(_tokenIds[0], _NFTSubsetPool.getTokenIdsAllowed()[0]);
        assertEq(_tokenIds[1], _NFTSubsetPool.getTokenIdsAllowed()[1]);
        assertEq(_tokenIds[2], _NFTSubsetPool.getTokenIdsAllowed()[2]);
        assertEq(50, _NFTSubsetPool.getTokenIdsAllowed()[2]);
        assert(2 != _NFTSubsetPool.getTokenIdsAllowed()[1]);
    }

    // TODO: move and expand this test case in separate file
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

    function testBorrowNFTSubset() external {
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

        // TODO: check pool debt levels
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

}
