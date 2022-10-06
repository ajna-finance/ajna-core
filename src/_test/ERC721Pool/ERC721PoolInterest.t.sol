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
        _addLiquidity(
            {
                from:   _lender,
                amount: 10_000 * 1e18,
                index:  2550,
                newLup: BucketMath.MAX_PRICE
            }
        );
        _addLiquidity(
            {
                from:   _lender,
                amount: 10_000 * 1e18,
                index:  2551,
                newLup: BucketMath.MAX_PRICE
            }
        );
        _addLiquidity(
            {
                from:   _lender,
                amount: 10_000 * 1e18,
                index:  2552,
                newLup: BucketMath.MAX_PRICE
            }
        );
        _addLiquidity(
            {
                from:   _lender,
                amount: 10_000 * 1e18,
                index:  2553,
                newLup: BucketMath.MAX_PRICE
            }
        );
        _addLiquidity(
            {
                from:   _lender,
                amount: 10_000 * 1e18,
                index:  2554,
                newLup: BucketMath.MAX_PRICE
            }
        );

        skip(10 days);

        // borrower adds collateral and borrows initial amount
        uint256[] memory tokenIdsToAdd = new uint256[](3);
        tokenIdsToAdd[0] = 1;
        tokenIdsToAdd[1] = 3;
        tokenIdsToAdd[2] = 5;
        _pledgeCollateral(
            {
                from:     _borrower,
                borrower: _borrower,
                tokenIds: tokenIdsToAdd
            }
        );
        _borrow(
            {
                from:       _borrower,
                amount:     5_000 * 1e18,
                indexLimit: 2_551,
                newLup:     3_010.892022197881557845 * 1e18
            }
        );

        assertEq(_pool.borrowerDebt(), 5_004.807692307692310000 * 1e18);

        _assertBorrower(
            {
                borrower:                  _borrower,
                borrowerDebt:              5_012.354868151222773335 * 1e18,
                borrowerCollateral:        3 * 1e18,
                borrowerMompFactor:        3_010.892022197881557845 * 1e18,
                borrowerCollateralization: 1.804799828867894420 * 1e18
            }
        );

        // borrower pledge additional collateral after some time has passed
        skip(10 days);
        tokenIdsToAdd = new uint256[](1);
        tokenIdsToAdd[0] = 51;
        _pledgeCollateral(
            {
                from:     _borrower,
                borrower: _borrower,
                tokenIds: tokenIdsToAdd
            }
        );

        assertEq(_pool.borrowerDebt(), 5_019.913425024098425550 * 1e18);

        _assertBorrower(
            {
                borrower:                  _borrower,
                borrowerDebt:              5_019.913425024098425550 * 1e18,
                borrowerCollateral:        4 * 1e18,
                borrowerMompFactor:        3_001.831760341859136562 * 1e18,
                borrowerCollateralization: 2.399158525076298559 * 1e18
            }
        );

        // borrower pulls some of their collateral after some time has passed
        skip(10 days);
        uint256[] memory tokenIdsToRemove = new uint256[](1);
        tokenIdsToRemove[0] = 1;
        _pullCollateral(
            {
                from:     _borrower,
                tokenIds: tokenIdsToRemove
            }
        );

        assertEq(_pool.borrowerDebt(), 5_028.241003157279922662 * 1e18);

        _assertBorrower(
            {
                borrower:                  _borrower,
                borrowerDebt:              5_028.241003157279922662 * 1e18,
                borrowerCollateral:        3 * 1e18,
                borrowerMompFactor:        2_996.860242765192441905 * 1e18,
                borrowerCollateralization: 1.796388848689221982 * 1e18
            }
        );

        // borrower borrows some additional quote after some time has passed
        skip(864000);

        _borrow(
            {
                from:       _borrower,
                amount:     1_000 * 1e18,
                indexLimit: 3_000,
                newLup:     3_010.892022197881557845 * 1e18
            }
        );

        assertEq(_pool.borrowerDebt(), 6_038.697103647272763112 * 1e18);

        _assertBorrower(
            {
                borrower:                  _borrower,
                borrowerDebt:              6_038.697103647272763112 * 1e18,
                borrowerCollateral:        3 * 1e18,
                borrowerMompFactor:        2_991.401082754081650235 * 1e18,
                borrowerCollateralization: 1.495798830701089204 * 1e18
            }
        );

        // mint additional quote to borrower to enable repayment
        deal(address(_quote), _borrower, 20_000 * 1e18);

        // borrower repays their loan after some additional time
        skip(864000);

        _repay(
            {
                from:     _borrower,
                borrower: _borrower,
                amount:   6_050.820567269683913977 * 1e18,
                repaid:   6_050.820567269683913977 * 1e18,
                newLup:   BucketMath.MAX_PRICE
            }
        );

        assertEq(_pool.borrowerDebt(), 0);

        _assertBorrower(
            {
                borrower:                  _borrower,
                borrowerDebt:              0,
                borrowerCollateral:        3 * 1e18,
                borrowerMompFactor:        0,
                borrowerCollateralization: 1 * 1e18
            }
        );

    }

    function testMultipleBorrowerInterestAccumulation() external {
        // lender deposits 10000 Quote into 3 buckets
        _addLiquidity(
            {
                from:   _lender,
                amount: 10_000 * 1e18,
                index:  2550,
                newLup: BucketMath.MAX_PRICE
            }
        );
        _addLiquidity(
            {
                from:   _lender,
                amount: 10_000 * 1e18,
                index:  2551,
                newLup: BucketMath.MAX_PRICE
            }
        );
        _addLiquidity(
            {
                from:   _lender,
                amount: 10_000 * 1e18,
                index:  2552,
                newLup: BucketMath.MAX_PRICE
            }
        );

        skip(2 hours);

        // borrower pledges three NFTs and takes out a loan with TP around 2666
        uint256[] memory tokenIdsToAdd = new uint256[](3);
        tokenIdsToAdd[0] = 1;
        tokenIdsToAdd[1] = 3;
        tokenIdsToAdd[2] = 5;
        _pledgeCollateral(
            {
                from:     _borrower,
                borrower: _borrower,
                tokenIds: tokenIdsToAdd
            }
        );

        uint256 borrowAmount = 8_000 * 1e18;
        _borrow(
            {
                from:       _borrower,
                amount:     borrowAmount,
                indexLimit: 2_551,
                newLup:     PoolUtils.indexToPrice(2550)
            }
        );

        skip(4 hours);

        // borrower 2 pledges one NFT and takes out a loan with TP around 2750
        tokenIdsToAdd = new uint256[](1);
        tokenIdsToAdd[0] = 53;
        _pledgeCollateral(
            {
                from:     _borrower2,
                borrower: _borrower2,
                tokenIds: tokenIdsToAdd
            }
        );

        borrowAmount = 2_750 * 1e18;
        _borrow(
            {
                from:       _borrower2,
                amount:     borrowAmount,
                indexLimit: 3_000,
                newLup:     PoolUtils.indexToPrice(2551)
            }
        );

        skip(4 hours);

        // borrower 3 pledges one NFT and takes out a loan with TP around 2500
        tokenIdsToAdd = new uint256[](1);
        tokenIdsToAdd[0] = 73;
        _pledgeCollateral(
            {
                from:     _borrower3,
                borrower: _borrower3,
                tokenIds: tokenIdsToAdd
            }
        );
        borrowAmount = 2_500 * 1e18;
        _borrow(
            {
                from:       _borrower3,
                amount:     borrowAmount,
                indexLimit: 3_000,
                newLup:     PoolUtils.indexToPrice(2551)
            }
        );

        skip(4 hours);

        // trigger an interest accumulation
        _addLiquidity(
            {
                from:   _lender,
                amount: 1 * 1e18,
                index:  2550,
                newLup: 2995.912459898389633881 * 1e18
            }
        );

        // check pool and borrower debt to confirm interest has accumulated
        assertEq(_pool.borrowerDebt(), 13_263.563121817930264782 * 1e18);

        _assertBorrower(
            {
                borrower:                  _borrower,
                borrowerDebt:              8_008.332217347647994785 * 1e18,
                borrowerCollateral:        3 * 1e18,
                borrowerMompFactor:        3_010.892022197881557845 * 1e18,
                borrowerCollateralization: 1.122387953276053753 * 1e18
            }
        );
        _assertBorrower(
            {
                borrower:                  _borrower2,
                borrowerDebt:              2_752.769925156330518889 * 1e18,
                borrowerCollateral:        1 * 1e18,
                borrowerMompFactor:        3_010.788911223004295676 * 1e18,
                borrowerCollateralization: 1.088376197116173336 * 1e18
            }
        );
        _assertBorrower(
            {
                borrower:                  _borrower3,
                borrowerDebt:              2_502.460979313951752502 * 1e18,
                borrowerCollateral:        1 * 1e18,
                borrowerMompFactor:        3_010.720172534836531431 * 1e18,
                borrowerCollateralization: 1.197213816827790670 * 1e18
            }
        );

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