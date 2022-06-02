// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.11;

import { ERC721Pool }        from "../../ERC721Pool.sol";
import { ERC721PoolFactory } from "../../ERC721PoolFactory.sol";

import { IPool } from "../../interfaces/IPool.sol";

import { DSTestPlus }                                         from "../utils/DSTestPlus.sol";
import { NFTCollateralToken, QuoteToken }                     from "../utils/Tokens.sol";
import { UserWithNFTCollateral, UserWithQuoteTokenInNFTPool } from "../utils/Users.sol";

import { Maths } from "../../libraries/Maths.sol";

contract ERC721PoolTest is DSTestPlus {

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
        _lender.addQuoteToken(_NFTSubsetPool, address(_lender), 10_000 * 1e18, _p3010);
        _lender.addQuoteToken(_NFTSubsetPool, address(_lender), 10_000 * 1e18, _p2503);

        // check iniital pool balance
        assertEq(_NFTSubsetPool.totalQuoteToken(),                      30_000 * 1e18);
        assertEq(_NFTSubsetPool.totalDebt(),                            0);
        assertEq(_NFTSubsetPool.hpb(),                                  _p4000);
        assertEq(_NFTSubsetPool.getPendingPoolInterest(),               0);
        assertEq(_NFTSubsetPool.getPendingBucketInterest(_p4000), 0);

        // add iniitial collateral to pool
        vm.prank((address(_borrower)));
        _NFTSubsetPool.addCollateral(1);
        vm.prank((address(_borrower)));
        _NFTSubsetPool.addCollateral(5);
        vm.prank((address(_borrower)));
        _NFTSubsetPool.addCollateral(50);
        assertEq(_NFTSubsetPool.getCollateralDeposited().length, 3);

        // borrow from pool
        uint256 borrowAmount = 6_000 * 1e18;
        vm.expectEmit(true, true, false, true);
        emit Borrow(address(_borrower), _p4000, borrowAmount);
        _borrower.borrow(_NFTSubsetPool, borrowAmount, _p2503);

        // check bucket balances
        (, , , uint256 deposit, uint256 debt, , , ) = _NFTSubsetPool.bucketAt(_p4000);
        assertEq(deposit, 4_000 * 1e18);
        assertEq(debt, borrowAmount);

        // check borrower balance
        (uint256 borrowerDebt,, uint256[] memory collateralDeposited, uint256 collateralEncumbered,,,) = _NFTSubsetPool.getNFTBorrowerInfo(address(_borrower));
        assertEq(borrowerDebt,        borrowAmount);
        assertEq(collateralDeposited.length, _NFTSubsetPool.getCollateralDeposited().length);
        assertEq(collateralDeposited[0], 1);
        assertEq(collateralDeposited[1], 5);
        assertEq(collateralDeposited[2], 50);
        assertEq(collateralEncumbered, 1.499652201193662919953559493 * 1e27);

        // check pool balances
        assertEq(_NFTSubsetPool.totalQuoteToken(),          24_000 * 1e18);
        assertEq(_NFTSubsetPool.totalDebt(),                borrowAmount);
        assertEq(_NFTSubsetPool.getNFTPoolCollateralization(), 2.000463839290283769 * 1e18);
        assertEq(
            _NFTSubsetPool.getEncumberedCollateral(_NFTSubsetPool.totalDebt()),
            _NFTSubsetPool.getEncumberedCollateral(borrowerDebt)
        );
        assertEq(_quote.balanceOf(address(_borrower)), borrowAmount);
        assertEq(_quote.balanceOf(_NFTSubsetPoolAddress),     24_000 * 1e18);
        assertEq(_NFTSubsetPool.hpb(),                          _p4000);
        assertEq(_NFTSubsetPool.lup(),                          _p4000);

        skip(8200);

        // TODO: check pending debt post skip
        // TODO: check borrower debt has increased following the passage of time
        (uint256 borrowerDebtAfterTime,,,,,,) = _NFTSubsetPool.getNFTBorrowerInfo(address(_borrower));
        assertGt(borrowerDebtAfterTime, borrowerDebt);

        // Attempt, but fail to borrow from pool if it would result in undercollateralization
        vm.prank((address(_borrower)));
        vm.expectRevert("P:B:INSUF_COLLAT");
        _borrower.borrow(_NFTSubsetPool, 5_000 * 1e18, _p3010);

        // add additional collateral
        // TODO: RAISES THE QUESTION -> How to deal with a pool where the universe of possible collateral has been exhausted

        // borrow remaining amount from LUP, and more, forcing reallocation
        vm.expectEmit(true, true, false, true);
        emit Transfer(_NFTSubsetPoolAddress, address(_borrower), 5_000 * 1e18);
        vm.expectEmit(true, true, false, true);
        emit Borrow(address(_borrower), _p4000, 5_000 * 1e18);
        vm.prank((address(_borrower)));
        _borrower.borrow(_NFTSubsetPool, 5_000 * 1e18, _p3010);

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

    function testPurchaseBidNFTSubset() external {
        // add initial quote tokens to pool
        _lender.addQuoteToken(_NFTSubsetPool, address(_lender), 10_000 * 1e18, _p4000);
        _lender.addQuoteToken(_NFTSubsetPool, address(_lender), 3_000 * 1e18, _p3010);

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

        // check initial pool state
        assertEq(_NFTSubsetPool.lup(), _p4000);
        assertEq(_NFTSubsetPool.getNFTPoolCollateralization(), 2.400556607148340522 * 1e18);

        _tokenIds = new uint256[](1);
        _tokenIds[0] = 61;

        // should revert if invalid price
        vm.expectRevert("BM:PTI:OOB");
        _bidder.purchaseBidNFTCollateral(_NFTSubsetPool, _p1, 1_000, _tokenIds);

        // should revert if bidder doesn't have enough collateral
        vm.expectRevert("P:PB:INSUF_COLLAT");
        _bidder.purchaseBidNFTCollateral(_NFTSubsetPool, 2_000_000 * 1e18, _p4000, _tokenIds);

        // should revert if trying to purchase more than on bucket
        vm.expectRevert("B:PB:INSUF_BUCKET_LIQ");
        vm.prank((address(_bidder)));
        _bidder.purchaseBidNFTCollateral(_NFTSubsetPool, 12_000 * 1e18, _p4000, _tokenIds);

        // check 4_000.927678580567537368 bucket balance before purchase bid
        (, , , uint256 deposit, uint256 debt, , , uint256 bucketCollateral) = _NFTSubsetPool.bucketAt(_p4000);
        assertEq(deposit, 5_000 * 1e18);
        assertEq(debt,    5_000 * 1e18);

        // purchase 4000 bid from p4000 bucket
        vm.expectEmit(true, true, false, true);
        emit Purchase(address(_bidder), _p4000, 4_000 * 1e18, Maths.ONE_WAD);
        vm.prank((address(_bidder)));
        _bidder.purchaseBidNFTCollateral(_NFTSubsetPool, 4_000 * 1e18, _p4000, _tokenIds);

        // check 4_000.927678580567537368 bucket balance after purchase bid
        (, , , deposit, debt, , , bucketCollateral) = _NFTSubsetPool.bucketAt(_p4000);
        assertEq(deposit,          1_000 * 1e18);

        // TODO: currently broken here
        assertEq(debt,             9_000 * 1e18);
        assertEq(bucketCollateral, 0.499884067064554307 * 1e18);

    }

    // TODO: FINISH IMPLEMENTING
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

        // should revert if attempting to claim more collateral than is available
        vm.prank((address(_lender)));
        vm.expectRevert("B:CC:AMT_GT_COLLAT");
        _NFTSubsetPool.claimCollateral(address(_lender), 1, _p4000);

        // TODO: finish implementing to enable there to be spare collateral to claim
        // bidder purchases some of the top bucket
        // _bidder.purchaseBidNFTCollateral(_pool, 1_500 * 1e18, priceHigh);

        // pass time to allow interest to accrue
        skip(82000);
        vm.prank((address(_lender)));
        _NFTSubsetPool.claimCollateral(address(_lender), 1, _p4000);

    }

}
