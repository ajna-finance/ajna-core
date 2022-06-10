// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.11;

import { ERC721Pool }        from "../../ERC721Pool.sol";
import { ERC721PoolFactory } from "../../ERC721PoolFactory.sol";

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
        _bidder     = new UserWithNFTCollateral();
        _borrower   = new UserWithNFTCollateral();

        _quote.mint(address(_lender), 200_000 * 1e18);
        _collateral.mint(address(_borrower), 60);
        _collateral.mint(address(_bidder), 5);

        _NFTCollectionPoolAddress = new ERC721PoolFactory().deployNFTCollectionPool(address(_collateral), address(_quote));
        _NFTCollectionPool        = ERC721Pool(_NFTCollectionPoolAddress);

        _tokenIds = new uint256[](5);

        _tokenIds[0] = 1;
        _tokenIds[1] = 5;
        _tokenIds[2] = 10;
        _tokenIds[3] = 50;
        _tokenIds[4] = 61;

        _NFTSubsetPoolAddress = new ERC721PoolFactory().deployNFTSubsetPool(address(_collateral), address(_quote), _tokenIds);
        _NFTSubsetPool        = ERC721Pool(_NFTSubsetPoolAddress);

        // run token approvals for NFT Collection Pool
        _lender.approveToken(_quote, _NFTCollectionPoolAddress, 200_000 * 1e18);
        _borrower.approveToken(_collateral, _NFTCollectionPoolAddress, 1);

        // run token approvals for NFT Subset Pool
        _lender.approveToken(_quote, _NFTSubsetPoolAddress, 200_000 * 1e18);

        _borrower.approveToken(_collateral, _NFTSubsetPoolAddress, 1);
        _borrower.approveToken(_collateral, _NFTSubsetPoolAddress, 5);
        _borrower.approveToken(_collateral, _NFTSubsetPoolAddress, 10);
        _borrower.approveToken(_collateral, _NFTSubsetPoolAddress, 50);

        _bidder.approveToken(_collateral, _NFTSubsetPoolAddress, 61);

        // _collateral.setApprovalForAll(_NFTSubsetPoolAddress, true);
    }

    /**
     *  @notice With 1 lender and 1 borrower test adding collateral, repay and removeCollateral in an NFT subset type pool
     *          Borrower reverts from attempting to add collateral outside of the approved subset
     *          Borrower reverts from attempting to withdraw collateral when no collateral is available
     */
    function testAddRemoveCollateralNFTSubset() external {
        // should revert if attempt to add collateral from a tokenId outside of allowed subset
        vm.prank((address(_borrower)));
        vm.expectRevert("P:ONLY_SUBSET");
        _NFTSubsetPool.addCollateral(2);

        // should revert if attempting to remove collateral that is not in the pool
        vm.prank((address(_borrower)));
        vm.expectRevert("P:T_NOT_IN_P");
        _NFTSubsetPool.removeCollateral(10);

        // add initial quote tokens to pool
        _lender.addQuoteToken(_NFTSubsetPool, address(_lender), 10_000 * 1e18, _p4000);

        uint256 poolEncumbered    = _NFTSubsetPool.getEncumberedCollateral(_NFTSubsetPool.totalDebt());
        uint256 collateralization = _NFTSubsetPool.getPoolCollateralization();
        uint256 targetUtilization = _NFTSubsetPool.getPoolTargetUtilization();
        uint256 actualUtilization = _NFTSubsetPool.getPoolActualUtilization();
        assertEq(poolEncumbered,    0);
        assertEq(collateralization, Maths.ONE_WAD);
        assertEq(_NFTSubsetPool.getCollateralDeposited().length, 0);

        // check collateral balances
        assertEq(_collateral.balanceOf(address(_borrower)),      60);
        assertEq(_collateral.balanceOf(address(_NFTSubsetPool)), 0);

        // add iniitial collateral to pool
        vm.prank((address(_borrower)));
        _NFTSubsetPool.addCollateral(1);
        vm.prank((address(_borrower)));
        _NFTSubsetPool.addCollateral(5);

        vm.prank((address(_borrower)));
        // vm.expectEmit(true, true, false, true);
        // emit Transfer(address(_borrower), address(_NFTSubsetPool), 50);
        vm.expectEmit(true, true, false, true);
        emit AddNFTCollateral(address(_borrower), 50);
        _NFTSubsetPool.addCollateral(50);

        // check collateral balances
        assertEq(_collateral.balanceOf(address(_borrower)),      57);
        assertEq(_collateral.balanceOf(address(_NFTSubsetPool)), 3);
        assertEq(_NFTSubsetPool.getCollateralDeposited().length, 3);

        // check borrower state before borrowing
        (,, uint256[] memory collateralDeposited, uint256 borrowerEncumbered, uint256 borrowerCollateralization,,) = _NFTSubsetPool.getNFTBorrowerInfo(address(_borrower));
        assertEq(collateralDeposited.length, 3);
        assertEq(collateralDeposited[0],     1);
        assertEq(collateralDeposited[1],     5);
        assertEq(collateralDeposited[2],     50);
        assertEq(borrowerEncumbered,         0);
        assertEq(borrowerCollateralization,  Maths.ONE_WAD);
        assertEq(_NFTSubsetPool.getPoolCollateralization(), borrowerCollateralization);

        // borrow from pool
        vm.expectEmit(true, true, false, true);
        emit Borrow(address(_borrower), _p4000, 5_000 * 1e18);
        _borrower.borrow(_NFTSubsetPool, 5_000 * 1e18, _p2503);

        // check borrower state after borrowing
        (,, collateralDeposited, borrowerEncumbered, borrowerCollateralization,,) = _NFTSubsetPool.getNFTBorrowerInfo(address(_borrower));
        assertEq(collateralDeposited.length, 3);
        assertEq(collateralDeposited[0],     1);
        assertEq(collateralDeposited[1],     5);
        assertEq(collateralDeposited[2],     50);
        assertEq(borrowerEncumbered,         1.249710407990264163048421338 * 1e27);
        assertEq(borrowerCollateralization,  2.400556145502927926 * 1e18);
        assertEq(_NFTSubsetPool.getPoolCollateralization(), borrowerCollateralization);

        // check pool state after borrowing
        poolEncumbered    = _NFTSubsetPool.getEncumberedCollateral(_NFTSubsetPool.totalDebt());
        targetUtilization = _NFTSubsetPool.getPoolTargetUtilization();
        actualUtilization = _NFTSubsetPool.getPoolActualUtilization();
        assertEq(poolEncumbered,    borrowerEncumbered);
        assertGt(actualUtilization, targetUtilization);

        // remove collateral
        vm.prank((address(_borrower)));
        vm.expectEmit(true, true, false, true);
        emit RemoveNFTCollateral(address(_borrower), 1);
        _NFTSubsetPool.removeCollateral(1);
        assertEq(_NFTSubsetPool.getCollateralDeposited().length, 2);
        assertEq(actualUtilization,                              _NFTSubsetPool.getPoolActualUtilization());
        assertLt(targetUtilization,                              _NFTSubsetPool.getPoolTargetUtilization());

        // should fail to remove collateral that would result in undercollateralization of the pool
        vm.prank((address(_borrower)));
        vm.expectRevert("P:RC:AMT_GT_AVAIL_COLLAT");
        _NFTSubsetPool.removeCollateral(5);

        // TODO: add tests for repayment followed by removal once repay() is implemented
    }

    /**
     *  @notice With 1 lender, and 1 borrower adding quote token, adding multiple collateral, borrowing, and removing multiple collateral.
     *          addCollateralMultiple() is called, then borrowed against, and subsequently removed, readded, and removed again.
     *          Lender1 reverts:
     *              attempts to add NFTs outside the subset.
     *              attempts to remove NFTs that weren't deposited into the pool.
     *              attempts to remove from bucket with insufficient unencumbered collateral.
     */
    function testAddRemoveMultipleCollateralNFTSubset() external {
        // should revert if attempt to add collateral from a tokenId outside of allowed subset
        uint256[] memory invalidTokenIds = new uint256[](3);
        invalidTokenIds[0] = 1;
        invalidTokenIds[1] = 2;
        invalidTokenIds[2] = 3;
        vm.prank((address(_borrower)));
        vm.expectRevert("P:ONLY_SUBSET");
        _NFTSubsetPool.addCollateralMultiple(invalidTokenIds);

        // should revert if attempting to remove collateral that is not in the pool
        uint256[] memory tokenIdsToRemove = new uint256[](2);
        tokenIdsToRemove[0] = 1;
        tokenIdsToRemove[1] = 5;
        vm.prank((address(_borrower)));
        vm.expectRevert("P:T_NOT_IN_P");
        _NFTSubsetPool.removeCollateralMultiple(tokenIdsToRemove);

        // add initial quote tokens to pool
        _lender.addQuoteToken(_NFTSubsetPool, address(_lender), 10_000 * 1e18, _p2503);

        // check pool and borrower state before adding collateral
        assertEq(_collateral.balanceOf(address(_borrower)),      60);
        assertEq(_collateral.balanceOf(address(_NFTSubsetPool)), 0);
        assertEq(_NFTSubsetPool.getCollateralDeposited().length, 0);
        assertEq(_NFTSubsetPool.totalCollateral(),               0);

        // add initial collateral to pool
        _tokenIds = new uint256[](3);
        _tokenIds[0] = 1;
        _tokenIds[1] = 5;
        _tokenIds[2] = 10;
        vm.prank((address(_borrower)));
        vm.expectEmit(true, true, false, true);
        emit AddNFTCollateralMultiple(address(_borrower), _tokenIds);
        _NFTSubsetPool.addCollateralMultiple(_tokenIds);

        // check pool and borrower state after adding collateral
        assertEq(_collateral.balanceOf(address(_borrower)),      57);
        assertEq(_collateral.balanceOf(address(_NFTSubsetPool)), 3);
        assertEq(_NFTSubsetPool.getCollateralDeposited().length, 3);
        assertEq(_NFTSubsetPool.totalCollateral(),               Maths.wad(3));
        assertEq(_collateral.ownerOf(1),                         _NFTSubsetPoolAddress);

        // TODO: fix... broken here
        // remove some of the collateral from the pool
        vm.prank((address(_borrower)));
        vm.expectEmit(true, true, false, true);
        emit RemoveNFTCollateralMultiple(address(_borrower), tokenIdsToRemove);
        _NFTSubsetPool.removeCollateralMultiple(tokenIdsToRemove);

        // check pool and borrower state after removing collateral
        assertEq(_collateral.balanceOf(address(_borrower)),      59);
        assertEq(_collateral.balanceOf(address(_NFTSubsetPool)), 1);
        assertEq(_NFTSubsetPool.getCollateralDeposited().length, 1);
        assertEq(_NFTSubsetPool.totalCollateral(),               Maths.wad(1));
        assertEq(_collateral.ownerOf(1),                         address(_borrower));

        // reapprove removed tokens
        _borrower.approveToken(_collateral, _NFTSubsetPoolAddress, 1);
        _borrower.approveToken(_collateral, _NFTSubsetPoolAddress, 5);

        // readd collateral
        uint256[] memory tokenIdsReadd = new uint256[](2);
        tokenIdsReadd[0] = 1;
        tokenIdsReadd[1] = 5;
        vm.prank((address(_borrower)));
        vm.expectEmit(true, true, false, true);
        emit AddNFTCollateralMultiple(address(_borrower), tokenIdsReadd);
        _NFTSubsetPool.addCollateralMultiple(tokenIdsReadd);

        // check pool and borrower state after readding collateral
        assertEq(_collateral.balanceOf(address(_borrower)),      57);
        assertEq(_collateral.balanceOf(address(_NFTSubsetPool)), 3);
        assertEq(_NFTSubsetPool.getCollateralDeposited().length, 3);
        assertEq(_NFTSubsetPool.totalCollateral(),               Maths.wad(3));
        assertEq(_collateral.ownerOf(1),                         _NFTSubsetPoolAddress);

        (uint256 borrowerDebt,, uint256[] memory collateralDeposited, uint256 borrowerEncumbered, uint256 borrowerCollateralization,,) = _NFTSubsetPool.getNFTBorrowerInfo(address(_borrower));
        assertEq(borrowerDebt,               0);
        assertEq(collateralDeposited.length, _NFTSubsetPool.getCollateralDeposited().length);
        assertEq(collateralDeposited[0],     10);
        assertEq(collateralDeposited[1],     1);
        assertEq(collateralDeposited[2],     5);
        assertEq(borrowerEncumbered,         0);
        assertEq(borrowerCollateralization,  Maths.ONE_WAD);
        assertEq(_NFTSubsetPool.getPoolCollateralization(), borrowerCollateralization);

        // borrow against collateral
        uint256 borrowAmount = 2_000 * 1e18;
        vm.expectEmit(true, true, false, true);
        emit Borrow(address(_borrower), _p2503, borrowAmount);
        _borrower.borrow(_NFTSubsetPool, borrowAmount, _p2503);

        // check pool and borrower state after borrowing
        (borrowerDebt,, collateralDeposited, borrowerEncumbered, borrowerCollateralization,,) = _NFTSubsetPool.getNFTBorrowerInfo(address(_borrower));
        assertEq(borrowerDebt,               2000.000961538461538462 * 1e18);
        assertEq(collateralDeposited.length, _NFTSubsetPool.getCollateralDeposited().length);
        assertEq(collateralDeposited[0],     10);
        assertEq(collateralDeposited[1],     1);
        assertEq(collateralDeposited[2],     5);
        assertEq(borrowerEncumbered,         0.798875879164494288582167879 * 1e27);
        assertEq(borrowerCollateralization,  3.755276731020537454 * 1e18);
        assertEq(_NFTSubsetPool.getPoolCollateralization(), borrowerCollateralization);

        // should revert if attempt to remove collateral that would result in under-collateralization
        vm.prank((address(_borrower)));
        vm.expectRevert("P:RC:AMT_GT_AVAIL_COLLAT");
        _NFTSubsetPool.removeCollateralMultiple(_tokenIds);

        // remove multiple collateral post borrow
        vm.prank((address(_borrower)));
        vm.expectEmit(true, true, false, true);
        emit RemoveNFTCollateral(address(_borrower), 5);
        _NFTSubsetPool.removeCollateral(5);

        // check pool and borrower state after removal
        assertEq(_collateral.balanceOf(address(_borrower)),      58);
        assertEq(_collateral.balanceOf(address(_NFTSubsetPool)), 2);
        assertEq(_NFTSubsetPool.getCollateralDeposited().length, 2);
        assertEq(_NFTSubsetPool.totalCollateral(),               Maths.wad(2));
        assertEq(_collateral.ownerOf(1),                         _NFTSubsetPoolAddress);

        (borrowerDebt,, collateralDeposited, borrowerEncumbered, borrowerCollateralization,,) = _NFTSubsetPool.getNFTBorrowerInfo(address(_borrower));
        assertEq(borrowerDebt,               2000.000961538461538462 * 1e18);
        assertEq(collateralDeposited.length, _NFTSubsetPool.getCollateralDeposited().length);
        assertEq(collateralDeposited[0],     10);
        assertEq(collateralDeposited[1],     1);
        assertEq(borrowerEncumbered,         0.798875879164494288582167879 * 1e27);
        assertEq(borrowerCollateralization,  2.503517820680358303 * 1e18);
        assertEq(_NFTSubsetPool.getPoolCollateralization(), borrowerCollateralization);
    }

    /**
     *  @notice With 1 lender, 1 borrower and 1 bidder test adding quote token, adding collateral, and borrowing.
     *          PurchaseBid is made then collateral is claimed and quote token is removed.
     *          Lender1 reverts:
     *              attempts to claim from invalidPrice.
     *              attempts to claim more than LP balance allows.
     *              attempts to claim from bucket with no claimable collateral.
     */
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
        _lender.claimCollateral(_NFTSubsetPool, address(_lender), 1, 4_000 * 1e18);

        // should revert if no lp tokens in bucket
        vm.expectRevert("P:CC:NO_CLAIM_TO_BUCKET");
        _lender.claimCollateral(_NFTSubsetPool, address(_lender), 1, _p2503);

        // should revert if attempting to claim more collateral than is available
        vm.prank((address(_lender)));
        vm.expectRevert("B:CC:AMT_GT_COLLAT");
        _NFTSubsetPool.claimCollateral(address(_lender), 1, _p4000);

        // bidder purchases some of the top bucket
        _tokenIds = new uint256[](1);
        _tokenIds[0] = 61;
        vm.expectEmit(true, true, false, true);
        emit PurchaseWithNFTs(address(_bidder), _p4000, 4_000 * 1e18, _tokenIds);
        vm.prank((address(_bidder)));
        _bidder.purchaseBidNFTCollateral(_NFTSubsetPool, 4_000 * 1e18, _p4000, _tokenIds);

        // check balances after purchase bid
        assertEq(_collateral.balanceOf(address(_lender)),            0);
        assertEq(_NFTSubsetPool.lpBalance(address(_lender), _p4000), 10_000 * 1e27);
        assertEq(_collateral.balanceOf(address(_bidder)),            4);
        assertEq(_collateral.balanceOf(address(_NFTSubsetPool)),     4);
        assertEq(_quote.balanceOf(address(_lender)),                 190_000 * 1e18);
        assertEq(_quote.balanceOf(address(_NFTSubsetPool)),          1_000 * 1e18);
        assertEq(_NFTSubsetPool.totalCollateral(),                   4 * 1e18);

        // check bucket state after purchase bid
        (, , , uint256 deposit, uint256 debt, , , uint256 bucketCollateral) = _NFTSubsetPool.bucketAt(_p4000);
        assertEq(deposit,          1_000 * 1e18);
        assertEq(debt,             5_000.651054657058420273 * 1e18);
        assertEq(bucketCollateral, Maths.ONE_WAD);

        // TODO: implement this check -> may require claimCollateralMultiple
        // should revert if claiming larger amount of collateral than LP balance allows
        // vm.expectRevert("B:CC:INSUF_LP_BAL");
        // _lender.claimCollateral(_NFTSubsetPool, address(_lender), 1, _p4000);

        // pass time to allow additional interest to accrue
        skip(8200);

        // claim collateral from p4000 bucket
        vm.prank((address(_lender)));
        vm.expectEmit(true, true, false, true);
        emit ClaimNFTCollateral(address(_lender), _p4000, 1, 4000.296138533142632904519433016 * 1e27);
        _NFTSubsetPool.claimCollateral(address(_lender), 1, _p4000);

        // check balances
        assertEq(_collateral.balanceOf(address(_lender)),            1);
        assertEq(_NFTSubsetPool.lpBalance(address(_lender), _p4000), 5_999.703861466857367095480566984 * 1e27);
        assertEq(_collateral.balanceOf(address(_bidder)),            4);
        assertEq(_collateral.balanceOf(address(_NFTSubsetPool)),     3);
        assertEq(_quote.balanceOf(address(_lender)),                 190_000 * 1e18);
        assertEq(_quote.balanceOf(address(_NFTSubsetPool)),          1_000 * 1e18);
        assertEq(_NFTSubsetPool.totalCollateral(),                   3 * 1e18);

        // check bucket state after claim
        (, , , deposit, debt, , , bucketCollateral) = _NFTSubsetPool.bucketAt(_p4000);
        assertEq(deposit,          1_000 * 1e18);
        assertEq(debt,             5_000.651054657058420273 * 1e18);
        assertEq(bucketCollateral, 0);
    }

    // TODO: use multiple lenders, borrowers, and bidders
    function testClaimMultipleCollateralNFTSubset() external {

    }


}
