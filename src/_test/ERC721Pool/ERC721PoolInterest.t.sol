// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.14;

import { ERC721HelperContract } from './ERC721DSTestPlus.sol';

import '../../erc721/ERC721Pool.sol';
import '../../erc721/ERC721PoolFactory.sol';

import '../../base/interfaces/IPool.sol';

import '../../libraries/BucketMath.sol';
import '../../libraries/Maths.sol';
import '../../libraries/PoolUtils.sol';

abstract contract ERC721PoolInterestTest is ERC721HelperContract {
    address internal _borrower;
    address internal _borrower2;
    address internal _borrower3;
    address internal _lender;
    address internal _lender2;

    // Called by setUp method to set the _pool which tests will use
    function createPool() external virtual returns (ERC721Pool);

    function setUp() external {
        _borrower  = makeAddr("borrower");
        _borrower2 = makeAddr("borrower2");
        _borrower3 = makeAddr("borrower3");
        _lender    = makeAddr("lender");
        _lender2   = makeAddr("lender2");

        _pool = this.createPool();
        _mintAndApproveQuoteTokens(_lender, 200_000 * 1e18);

        _mintAndApproveCollateralTokens(_borrower, 52);
        _mintAndApproveCollateralTokens(_borrower2, 10);
        _mintAndApproveCollateralTokens(_borrower3, 13);

        // TODO: figure out how to generally approve quote tokens for the borrowers to handle repays
        // TODO: potentially use _approveQuoteMultipleUserMultiplePool()
        vm.prank(_borrower);
        _quote.approve(address(_pool), 200_000 * 1e18);
    }
}

contract ERC721PoolSubsetInterestTest is ERC721PoolInterestTest {
    function createPool() external override returns (ERC721Pool) {
        // deploy subset pool
        uint256[] memory subsetTokenIds = new uint256[](6);
        subsetTokenIds[0] = 1;
        subsetTokenIds[1] = 3;
        subsetTokenIds[2] = 5;
        subsetTokenIds[3] = 51;
        subsetTokenIds[4] = 53;
        subsetTokenIds[5] = 73;
        return _deploySubsetPool(subsetTokenIds);
    }

    // TODO: skip block number ahead as well
    function testBorrowerInterestAccumulation() external {
        changePrank(_lender);
        _pool.addQuoteToken(10_000 * 1e18, 2550);
        _pool.addQuoteToken(10_000 * 1e18, 2551);
        _pool.addQuoteToken(10_000 * 1e18, 2552);
        _pool.addQuoteToken(10_000 * 1e18, 2553);
        _pool.addQuoteToken(10_000 * 1e18, 2554);

        skip(864000);

        // borrower adds collateral and borrows initial amount
        changePrank(_borrower);
        uint256[] memory tokenIdsToAdd = new uint256[](3);
        tokenIdsToAdd[0] = 1;
        tokenIdsToAdd[1] = 3;
        tokenIdsToAdd[2] = 5;
        _pool.pledgeCollateral(_borrower, tokenIdsToAdd);
        _pool.borrow(5_000 * 1e18, 2551);

        assertEq(_pool.borrowerDebt(), 5_004.807692307692310000 * 1e18);
        (uint256 debt, uint256 pendingDebt, uint256 col, uint256 mompFactor, uint256 inflator) = _poolUtils.borrowerInfo(address(_pool), _borrower);
        assertEq(debt,        5_004.807692307692310000 * 1e18);
        assertEq(pendingDebt, 5_012.354868151222773335 * 1e18);
        assertEq(col       ,  3 * 1e18);
        assertEq(mompFactor,  3_010.892022197881557845 * 1e18);
        assertEq(inflator,    1 * 1e18);

        // borrower pledge additional collateral after some time has passed
        skip(864000);
        tokenIdsToAdd = new uint256[](1);
        tokenIdsToAdd[0] = 51;
        _pool.pledgeCollateral(_borrower, tokenIdsToAdd);
        assertEq(_pool.borrowerDebt(), 5_019.913425024098425550 * 1e18);
        (debt, pendingDebt, col, mompFactor, inflator) = _poolUtils.borrowerInfo(address(_pool), _borrower);
        assertEq(debt,        5_019.913425024098425550 * 1e18);
        assertEq(pendingDebt, 5_019.913425024098425550 * 1e18);
        assertEq(col,         4 * 1e18);
        assertEq(mompFactor,  3_001.831760341859136562 * 1e18);
        assertEq(inflator,    1.003018244385218513 * 1e18);

        // borrower pulls some of their collateral after some time has passed
        skip(864000);
        uint256[] memory tokenIdsToRemove = new uint256[](1);
        tokenIdsToRemove[0] = 1;
        _pool.pullCollateral(tokenIdsToRemove);
        assertEq(_pool.borrowerDebt(), 5_028.241003157279922662 * 1e18);
        (debt, pendingDebt, col, mompFactor, inflator) = _poolUtils.borrowerInfo(address(_pool), _borrower);
        assertEq(debt,        5_028.241003157279922662 * 1e18);
        assertEq(pendingDebt, 5_028.241003157279922662 * 1e18);
        assertEq(col,         3 * 1e18);
        assertEq(mompFactor,  2_996.860242765192441905 * 1e18);
        assertEq(inflator,    1.004682160092905114 * 1e18);

        // borrower borrows some additional quote after some time has passed
        skip(864000);
        _pool.borrow(1_000 * 1e18, 3000);
        assertEq(_pool.borrowerDebt(), 6_038.697103647272763112 * 1e18);
        (debt, pendingDebt, col, mompFactor, inflator) = _poolUtils.borrowerInfo(address(_pool), _borrower);
        assertEq(debt,        6_038.697103647272763112 * 1e18);
        assertEq(pendingDebt, 6_038.697103647272763112 * 1e18);
        assertEq(col       ,  3 * 1e18);
        assertEq(mompFactor,  2_991.401082754081650235 * 1e18);
        assertEq(inflator,    1.006515655675920014 * 1e18);

        // mint additional quote to borrower to enable repayment
        deal(address(_quote), _borrower, 20_000 * 1e18);

        // borrower repays their loan after some additional time
        skip(864000);
        (debt, pendingDebt, col, mompFactor, inflator) = _poolUtils.borrowerInfo(address(_pool), _borrower);
        _pool.repay(_borrower, pendingDebt);
        assertEq(_pool.borrowerDebt(), 0);
        (debt, pendingDebt, col, mompFactor, inflator) = _poolUtils.borrowerInfo(address(_pool), _borrower);
        assertEq(debt,        0);
        assertEq(pendingDebt, 0);
        assertEq(mompFactor,  0 * 1e18);
        assertEq(col       ,  3 * 1e18);
        assertEq(inflator,    1.008536365727696620 * 1e18);

    }

    function testMultipleBorrowerInterestAccumulation() external {
        // lender deposits 10000 Quote into 3 buckets
        changePrank(_lender);
        assertEq(_indexToPrice(2550), 3_010.892022197881557845 * 1e18);
        _pool.addQuoteToken(10_000 * 1e18, 2550);
        assertEq(_indexToPrice(2551), 2_995.912459898389633881 * 1e18);
        _pool.addQuoteToken(10_000 * 1e18, 2551);
        _pool.addQuoteToken(10_000 * 1e18, 2552);
        skip(2 hours);

        // borrower pledges three NFTs and takes out a loan with TP around 2666
        changePrank(_borrower);
        uint256[] memory tokenIdsToAdd = new uint256[](3);
        tokenIdsToAdd[0] = 1;
        tokenIdsToAdd[1] = 3;
        tokenIdsToAdd[2] = 5;
        _pool.pledgeCollateral(_borrower, tokenIdsToAdd);
        uint256 borrowAmount = 8_000 * 1e18;
        vm.expectEmit(true, true, false, true);
        emit Borrow(_borrower, _indexToPrice(2550), borrowAmount);
        _pool.borrow(borrowAmount, 2551);
        skip(4 hours);

        // borrower 2 pledges one NFT and takes out a loan with TP around 2750
        changePrank(_borrower2);
        tokenIdsToAdd = new uint256[](1);
        tokenIdsToAdd[0] = 53;
        _pool.pledgeCollateral(_borrower2, tokenIdsToAdd);
        borrowAmount = 2_750 * 1e18;
        vm.expectEmit(true, true, false, true);
        emit Borrow(_borrower2, _indexToPrice(2551), borrowAmount);
        _pool.borrow(borrowAmount, 3000);
        skip(4 hours);

        // borrower 3 pledges one NFT and takes out a loan with TP around 2500
        changePrank(_borrower3);
        tokenIdsToAdd = new uint256[](1);
        tokenIdsToAdd[0] = 73;
        _pool.pledgeCollateral(_borrower3, tokenIdsToAdd);
        borrowAmount = 2_500 * 1e18;
        vm.expectEmit(true, true, false, true);
        emit Borrow(_borrower3, _indexToPrice(2551), borrowAmount);
        _pool.borrow(borrowAmount, 3000);
        skip(4 hours);

        // trigger an interest accumulation
        changePrank(_lender);
        _pool.addQuoteToken(1 * 1e18, 2550);

        // check pool and borrower debt to confirm interest has accumulated
        assertEq(_pool.borrowerDebt(), 13_263.563121817930264782 * 1e18);
        (uint256 debt, uint256 pendingDebt, , , ) = _poolUtils.borrowerInfo(address(_pool), _borrower);
        assertEq(debt,        8_007.692307692307696000 * 1e18);
        assertEq(pendingDebt, 8_007.692307692307696000 * 1e18);
        (debt, pendingDebt, , , ) = _poolUtils.borrowerInfo(address(_pool), _borrower2);
        assertEq(debt,        2_752.644230769230770500 * 1e18);
        assertEq(pendingDebt, 2_752.644230769230770500 * 1e18);
        (debt, pendingDebt, , , ) = _poolUtils.borrowerInfo(address(_pool), _borrower3);
        assertEq(debt,        2_502.403846153846155000 * 1e18);
        assertEq(pendingDebt, 2_502.403846153846155000 * 1e18);
    }
}

contract ERC721PoolCollectionInterestTest is ERC721PoolInterestTest {

    function createPool() external override returns (ERC721Pool) {
        return _deployCollectionPool();
    }

    function testLenderInterestMargin() external {
        // check empty pool
        assertEq(_poolUtils.lenderInterestMargin(address(_pool)), 0.85 * 1e18);

        // test lender interest margin for various amounts of utilization
        assertEq(PoolUtils.lenderInterestMargin(0.01 * 1e18), 0.850501675988110546 * 1e18);
        assertEq(PoolUtils.lenderInterestMargin(0.23 * 1e18), 0.862515153185046657 * 1e18);
        assertEq(PoolUtils.lenderInterestMargin(0.67 * 1e18), 0.896343651549832236 * 1e18);
        assertEq(PoolUtils.lenderInterestMargin(0.88 * 1e18), 0.926013637770085897 * 1e18);
        assertEq(PoolUtils.lenderInterestMargin(1 * 1e18),    1e18);
        assertEq(PoolUtils.lenderInterestMargin(1.03 * 1e18), 1e18);
    }
}