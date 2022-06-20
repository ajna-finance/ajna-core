// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.14;

import { ERC721Pool }        from "../../ERC721Pool.sol";
import { ERC721PoolFactory } from "../../ERC721PoolFactory.sol";

import { DSTestPlus }                                         from "../utils/DSTestPlus.sol";
import { NFTCollateralToken, QuoteToken }                     from "../utils/Tokens.sol";
import { UserWithNFTCollateral, UserWithQuoteTokenInNFTPool } from "../utils/Users.sol";

import { Maths } from "../../libraries/Maths.sol";

contract ERC721PoolRepayTest is DSTestPlus {

    address                     internal _NFTCollectionPoolAddress;
    address                     internal _NFTSubsetPoolAddress;
    ERC721Pool                  internal _NFTCollectionPool;
    ERC721Pool                  internal _NFTSubsetPool;
    NFTCollateralToken          internal _collateral;
    QuoteToken                  internal _quote;
    UserWithNFTCollateral       internal _borrower;
    UserWithNFTCollateral       internal _borrower2;
    UserWithQuoteTokenInNFTPool internal _lender;
    uint256[]                   internal _tokenIds;

    function setUp() external {
        _collateral  = new NFTCollateralToken();
        _quote       = new QuoteToken();

        _borrower   = new UserWithNFTCollateral();
        _borrower2  = new UserWithNFTCollateral();
        _lender     = new UserWithQuoteTokenInNFTPool();

        _collateral.mint(address(_borrower), 60);
        _collateral.mint(address(_borrower2),   5);
        _quote.mint(address(_lender),        200_000 * 1e18);

        _NFTCollectionPoolAddress = new ERC721PoolFactory().deployNFTCollectionPool(address(_collateral), address(_quote));
        _NFTCollectionPool        = ERC721Pool(_NFTCollectionPoolAddress);

        _tokenIds = new uint256[](6);

        _tokenIds[0] = 1;
        _tokenIds[1] = 5;
        _tokenIds[2] = 10;
        _tokenIds[3] = 50;
        _tokenIds[4] = 61;
        _tokenIds[5] = 63;

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

        _borrower2.approveToken(_collateral, _NFTSubsetPoolAddress, 61);
        _borrower2.approveToken(_collateral, _NFTSubsetPoolAddress, 63);

    }

    /**
     *  @notice 1 lender 2 borrowers deposits quote token, borrows, repays, withdraws collateral
     *          Borrower reverts:
     *              attempts to repay with no debt.
     *              attempts to repay with insufficent balance.
     */
    function testRepayNFTSubsetTwoBorrowers() external {
        uint256 priceHigh = _p5007;
        uint256 priceMid = _p4000;
        uint256 priceLow = _p3010;

        // lender deposits 10000 DAI in 3 buckets each
        _lender.addQuoteToken(_NFTSubsetPool, address(_lender), 10_000 * 1e18, priceHigh);
        _lender.addQuoteToken(_NFTSubsetPool, address(_lender), 10_000 * 1e18, priceMid);
        _lender.addQuoteToken(_NFTSubsetPool, address(_lender), 10_000 * 1e18, priceLow);

        // borrower 1 starts with 10_000 DAI
        _quote.mint(address(_borrower), 10_000 * 1e18);
        _borrower.approveQuoteToken(_quote, _NFTSubsetPoolAddress, 100_000 * 1e18);

        // borrower 1 adds initial collateral to the pool
        _tokenIds = new uint256[](3);
        _tokenIds[0] = 1;
        _tokenIds[1] = 5;
        _tokenIds[2] = 10;
        vm.prank((address(_borrower)));
        vm.expectEmit(true, true, false, true);
        emit AddNFTCollateralMultiple(address(_borrower), _tokenIds);
        _NFTSubsetPool.addCollateralMultiple(_tokenIds);

        // borrower2 starts with 10_000 DAI
        _quote.mint(address(_borrower2), 10_000 * 1e18);
        _borrower2.approveQuoteToken(_quote, _NFTSubsetPoolAddress, 100_000 * 1e18);

        // borrower2 adds initial collateral to the pool
        _tokenIds = new uint256[](2);
        _tokenIds[0] = 61;
        _tokenIds[1] = 63;
        vm.prank((address(_borrower2)));
        vm.expectEmit(true, true, false, true);
        emit AddNFTCollateralMultiple(address(_borrower2), _tokenIds);        
        _NFTSubsetPool.addCollateralMultiple(_tokenIds);

        // check initial pool state after adding tokens
        assertEq(_NFTSubsetPool.hpb(), priceHigh);
        assertEq(_NFTSubsetPool.lup(), 0);

        assertEq(_NFTSubsetPool.totalDebt(),       0);
        assertEq(_NFTSubsetPool.totalQuoteToken(), 30_000 * 1e18);
        assertEq(_NFTSubsetPool.totalCollateral(), 5 * 1e18);
        assertEq(_NFTSubsetPool.pdAccumulator(),   120_194_640.856836005674960000 * 1e18);

        assertEq(_NFTSubsetPool.getPoolCollateralization(), Maths.ONE_WAD);
        assertEq(_NFTSubsetPool.getPoolActualUtilization(), 0);
        assertEq(_NFTSubsetPool.getPendingPoolInterest(),   0);

        assertEq(_NFTSubsetPool.getEncumberedCollateral(_NFTSubsetPool.totalDebt()), 0);

        // check collateral balances
        assertEq(_collateral.balanceOf(address(_borrower)),      57);
        assertEq(_collateral.balanceOf(address(_borrower2)),     3);
        assertEq(_collateral.balanceOf(address(_NFTSubsetPool)), 5);

        // repay should revert if no debt
        vm.expectRevert("P:R:NO_DEBT");
        _borrower.repay(_NFTSubsetPool, 10_000 * 1e18);

        // borrower takes loan of 12_000 DAI from 2 buckets
        vm.expectEmit(true, true, false, true);
        emit Borrow(address(_borrower), priceMid, 12_000 * 1e18);
        _borrower.borrow(_NFTSubsetPool, 12_000 * 1e18, priceMid);
        // borrower2 takes loan of 5_000 DAI from 1 bucket
        vm.expectEmit(true, true, false, true);
        emit Borrow(address(_borrower2), priceMid, 5_000 * 1e18);
        _borrower2.borrow(_NFTSubsetPool, 5_000 * 1e18, priceLow);

        // check pool state after borrowing
        assertEq(_NFTSubsetPool.hpb(), priceHigh);
        assertEq(_NFTSubsetPool.lup(), priceMid);

        assertEq(_NFTSubsetPool.totalDebt(),       17_000.001923076923076924 * 1e18);
        assertEq(_NFTSubsetPool.totalQuoteToken(), 13_000 * 1e18);
        assertEq(_NFTSubsetPool.totalCollateral(), 5 * 1e18);
        assertEq(_NFTSubsetPool.pdAccumulator(),   42_111_703.257720518190554000 * 1e18);

        assertEq(_NFTSubsetPool.getPoolCollateralization(), 1.176743301760879393 * 1e18);
        assertEq(_NFTSubsetPool.getPoolActualUtilization(), 0.617609495024810319 * 1e18);
        assertEq(_NFTSubsetPool.getPendingPoolInterest(),   0);

        assertEq(_NFTSubsetPool.getEncumberedCollateral(_NFTSubsetPool.totalDebt()), 4.249015050706468399375995417 * 1e27);

        // check balances        
        assertEq(_quote.balanceOf(address(_borrower)),      22_000 * 1e18);
        assertEq(_quote.balanceOf(address(_borrower2)),     15_000 * 1e18);
        assertEq(_quote.balanceOf(address(_NFTSubsetPool)), 13_000 * 1e18);

        // check buckets after borrowing
        (, , , uint256 deposit, uint256 debt, , , , ) = _NFTSubsetPool.nftBucketAt(priceHigh);
        assertEq(deposit, 0);
        assertEq(debt,    10_000 * 1e18);

        (, , , deposit, debt, , , , ) = _NFTSubsetPool.nftBucketAt(priceMid);
        assertEq(deposit, 3_000 * 1e18);
        assertEq(debt,    7_000.001923076923076924 * 1e18);

        // check borrower 1 after borrowing
        (   uint256 borrowerDebt,
            uint256 borrowerPendingDebt,
            ,
            uint256 collateralEncumbered,
            uint256 collateralization, , ) = _NFTSubsetPool.getNFTBorrowerInfo(address(_borrower));
        assertEq(borrowerDebt,         12_000.000961538461538462 * 1e18);
        assertEq(borrowerPendingDebt,  12_000.000961538461538462 * 1e18);
        assertEq(collateralEncumbered, 2.999304642716204236327574079 * 1e27);
        assertEq(collateralization,    1.000231839498359873 * 1e18);

        // check borrower2 after borrowing
        (   borrowerDebt,
            borrowerPendingDebt,
            ,
            collateralEncumbered,
            collateralization, , ) = _NFTSubsetPool.getNFTBorrowerInfo(address(_borrower2));
        assertEq(borrowerDebt,         5_000.000961538461538462 * 1e18);
        assertEq(borrowerPendingDebt,  5_000.000961538461538462 * 1e18);
        assertEq(collateralEncumbered, 1.249710407990264163048421338 * 1e27);
        assertEq(collateralization,    1.600370763668618617 * 1e18);

        // repay should revert if amount not available
        vm.expectRevert("P:R:INSUF_BAL");
        _borrower.repay(_NFTSubsetPool, 50_000 * 1e18);

        skip(8200);

        // borrower 1 partially repays 10_000 of debt
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(_borrower), _NFTSubsetPoolAddress, 10_000 * 1e18);
        vm.expectEmit(true, true, false, true);
        emit Repay(address(_borrower), priceHigh, 10_000 * 1e18);
        _borrower.repay(_NFTSubsetPool, 10_000 * 1e18);

        // check pool state after partial repayment
        assertEq(_NFTSubsetPool.hpb(), priceHigh);
        assertEq(_NFTSubsetPool.lup(), priceHigh);

        assertEq(_NFTSubsetPool.totalDebt(),       7_000.222941788607304128 * 1e18);
        assertEq(_NFTSubsetPool.totalQuoteToken(), 23_000 * 1e18);
        assertEq(_NFTSubsetPool.totalCollateral(), 5 * 1e18);
        assertEq(_NFTSubsetPool.pdAccumulator(),   85_141_036.607514635807593881 * 1e18);

        assertEq(_NFTSubsetPool.getPoolCollateralization(), 3.576774930275050868 * 1e18);
        assertEq(_NFTSubsetPool.getPoolActualUtilization(), 0.291646354153320935 * 1e18);
        assertEq(_NFTSubsetPool.getPendingPoolInterest(),   0);

        assertEq(_NFTSubsetPool.getEncumberedCollateral(_NFTSubsetPool.totalDebt()), 1.397907359973445230797122511 * 1e27);

        skip(8200);

        // check balances after partial repayment
        assertEq(_quote.balanceOf(address(_borrower)),      12_000 * 1e18);
        assertEq(_quote.balanceOf(address(_borrower2)),     15_000 * 1e18);
        assertEq(_quote.balanceOf(address(_NFTSubsetPool)), 23_000 * 1e18);

        // check buckets after partial repayment
        (, , , deposit, debt, , , , ) = _NFTSubsetPool.nftBucketAt(priceHigh);
        assertEq(deposit, 2_999.907069203558644887 * 1e18);
        assertEq(debt,    7_000.222941788607304128 * 1e18);

        (, , , deposit, debt, , , , ) = _NFTSubsetPool.nftBucketAt(priceMid);
        assertEq(deposit, 10_000.092930796441355113 * 1e18);
        assertEq(debt,    0);

        (, , , deposit, debt, , , , ) = _NFTSubsetPool.nftBucketAt(priceLow);
        assertEq(deposit, 10_000 * 1e18);
        assertEq(debt,    0);

        // check borrower 1 after partial repayment
        (   borrowerDebt,
            borrowerPendingDebt,
            ,
            collateralEncumbered,
            collateralization, , ) = _NFTSubsetPool.getNFTBorrowerInfo(address(_borrower));
        assertEq(borrowerDebt,         2_000.156974741561734219 * 1e18);
        assertEq(borrowerPendingDebt,  2_000.182978980839113565 * 1e18);
        assertEq(collateralEncumbered, 0.399425922697329090445156664 * 1e27);
        assertEq(collateralization,    7.510779419975939915 * 1e18);

        // borrower attempts to overpay 2500 to cover remaining debt plus accumulated interest
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(_borrower), _NFTSubsetPoolAddress, 2_000.182978980839113565 * 1e18);
        vm.expectEmit(true, true, false, true);
        emit Repay(address(_borrower), priceHigh, 2_000.182978980839113565 * 1e18);
        _borrower.repay(_NFTSubsetPool, 2_500 * 1e18);

        // check pool state after borrower 1 full repayment
        assertEq(_NFTSubsetPool.hpb(), priceHigh);
        assertEq(_NFTSubsetPool.lup(), priceHigh);

        assertEq(_NFTSubsetPool.totalDebt(),       5000.130973400772668082 * 1e18);
        assertEq(_NFTSubsetPool.totalQuoteToken(), 25_000.182978980839113565 * 1e18);
        assertEq(_NFTSubsetPool.totalCollateral(), 5 * 1e18);
        assertEq(_NFTSubsetPool.pdAccumulator(),   95_157_241.670990893406505095 * 1e18);

        assertEq(_NFTSubsetPool.getPoolCollateralization(), 5.007513214698122855 * 1e18);
        assertEq(_NFTSubsetPool.getPoolActualUtilization(), 0.208316856687673908 * 1e18);
        assertEq(_NFTSubsetPool.getPendingPoolInterest(),   0);

        assertEq(_NFTSubsetPool.getEncumberedCollateral(_NFTSubsetPool.totalDebt()), 0.998499611608398763357684582 * 1e27);

        // check balances after borrower 1 full repayment
        assertEq(_quote.balanceOf(address(_borrower)),      9_999.817021019160886435 * 1e18);
        assertEq(_quote.balanceOf(address(_borrower2)),     15_000 * 1e18);
        assertEq(_quote.balanceOf(address(_NFTSubsetPool)), 25_000.182978980839113565 * 1e18);

        // check borrower 1 after full repayment
        (   borrowerDebt,
            borrowerPendingDebt,
            ,
            collateralEncumbered,
            collateralization, , ) = _NFTSubsetPool.getNFTBorrowerInfo(address(_borrower));
        assertEq(borrowerDebt,         0);
        assertEq(borrowerPendingDebt,  0);
        assertEq(collateralEncumbered, 0);
        assertEq(collateralization,    Maths.ONE_WAD);

        // TODO: borrower2 pending debt should == pool pending debt, but it doesn't...
        // check borrower 2 after borrower 1 fully repays
        (   borrowerDebt,
            borrowerPendingDebt,
            ,
            collateralEncumbered,
            collateralization, , ) = _NFTSubsetPool.getNFTBorrowerInfo(address(_borrower2));
        assertEq(borrowerDebt,         5_000.000961538461538462 * 1e18);
        assertEq(borrowerPendingDebt,  5_000.130973400772668081 * 1e18);
        assertEq(collateralEncumbered, 0.998499611608398763357484888 * 1e27);
        assertEq(collateralization,    2.003005285879249142 * 1e18);

        // check pending debt across all buckets
        uint256 bucketPendingDebt = 0;
        (, , , , debt, , , , ) = _NFTSubsetPool.nftBucketAt(priceHigh);
        bucketPendingDebt += debt;
        bucketPendingDebt += _NFTSubsetPool.getPendingBucketInterest(priceHigh);

        (, , , , debt, , , , ) = _NFTSubsetPool.nftBucketAt(priceMid);
        bucketPendingDebt += debt;
        bucketPendingDebt += _NFTSubsetPool.getPendingBucketInterest(priceMid);

        (, , , , debt, , , , ) = _NFTSubsetPool.nftBucketAt(priceLow);
        bucketPendingDebt += debt;
        bucketPendingDebt += _NFTSubsetPool.getPendingBucketInterest(priceLow);

        // first borrower repaid; tie out pending debt second borrower debt to reasonable percentage
        uint256 poolPendingDebt = _NFTSubsetPool.totalDebt() + _NFTSubsetPool.getPendingPoolInterest();
        (, borrowerPendingDebt, , , , , ) = _NFTSubsetPool.getNFTBorrowerInfo(address(_borrower2));

        // TODO: remove this, was for testing
        // assertEq(_NFTSubsetPool.getPendingPoolInterest(), 0);

        // TODO: both are off by one
        assertEq(borrowerPendingDebt, poolPendingDebt);
        // assertEq(borrowerPendingDebt, bucketPendingDebt);
        assertLt(wadPercentDifference(bucketPendingDebt, borrowerPendingDebt), 0.000000000000000001 * 1e18);
        assertLt(wadPercentDifference(bucketPendingDebt, poolPendingDebt),     0.000000000000000001 * 1e18);

        // borrower 2 repays entire debt
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(_borrower2), _NFTSubsetPoolAddress, 5_000.130973400772668081 * 1e18);
        vm.expectEmit(true, true, false, true);
        emit Repay(address(_borrower2), priceHigh, 5_000.130973400772668081 * 1e18);
        _borrower2.repay(_NFTSubsetPool, 5010 * 1e18);

        // check pool state after borrower 2 full repayment of all remaining debt
        assertEq(_NFTSubsetPool.hpb(), priceHigh);

        // TODO: fix lup not tying out
        assertEq(_NFTSubsetPool.lup(), 0);

        // TODO: determine why totalDebt doesn't tie out here
        // TODO: total debt not being 0 is the root of the other issues
        assertEq(_NFTSubsetPool.totalDebt(),       0);

        assertEq(_NFTSubsetPool.totalQuoteToken(), 30_000.313952381611781646 * 1e18);
        assertEq(_NFTSubsetPool.totalCollateral(), 5 * 1e18);
        assertEq(_NFTSubsetPool.pdAccumulator(),   120_196_119.463731601951263150 * 1e18);

        // TODO: figure out why pool collateralization is also fucked up... returning a RAY as opposed to a WAD...
        assertEq(_NFTSubsetPool.getPoolCollateralization(), Maths.ONE_WAD);

        assertEq(_NFTSubsetPool.getPoolActualUtilization(), 0);
        assertEq(_NFTSubsetPool.getPendingPoolInterest(),   0);

        // TODO: fix encumberance check as well...
        assertEq(_NFTSubsetPool.getEncumberedCollateral(_NFTSubsetPool.totalDebt()), 0);

        // check balances after borrower 2 full repayment
        assertEq(_quote.balanceOf(address(_borrower)),      9_999.817021019160886435 * 1e18);
        assertEq(_quote.balanceOf(address(_borrower2)),     9_999.869026599227331919 * 1e18);
        assertEq(_quote.balanceOf(address(_NFTSubsetPool)), 30_000.313952381611781646 * 1e18);

        // check buckets
        (, , , deposit, debt, , , , ) = _NFTSubsetPool.nftBucketAt(priceHigh);
        assertEq(deposit, 10_000.221021585170426533 * 1e18);
        assertEq(debt,    1);

        assertEq(_NFTSubsetPool.getPendingBucketInterest(priceHigh), 0);

        (, , , deposit, debt, , , , ) = _NFTSubsetPool.nftBucketAt(priceMid);
        assertEq(deposit, 10_000.092930796441355113 * 1e18);
        assertEq(debt,    0);

        assertEq(_NFTSubsetPool.getPendingBucketInterest(priceMid), 0);

        (, , , deposit, debt, , , , ) = _NFTSubsetPool.nftBucketAt(priceLow);
        assertEq(deposit, 10_000 * 1e18);
        assertEq(debt,    0);

        assertEq(_NFTSubsetPool.getPendingBucketInterest(priceLow), 0);

        // check borrower 2 after full repayment
        (   borrowerDebt,
            borrowerPendingDebt,
            ,
            collateralEncumbered,
            collateralization, , ) = _NFTSubsetPool.getNFTBorrowerInfo(address(_borrower2));
        assertEq(borrowerDebt,         0);
        assertEq(borrowerPendingDebt,  0);
        assertEq(collateralEncumbered, 0);
        assertEq(collateralization,    Maths.ONE_WAD);

        // remove remaining collateral

    }
}
