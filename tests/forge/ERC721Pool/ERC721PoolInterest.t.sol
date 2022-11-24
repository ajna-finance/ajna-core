// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.14;

import { ERC721HelperContract } from './ERC721DSTestPlus.sol';
import 'src/erc721/ERC721Pool.sol';

import 'src/libraries/BucketMath.sol';
import 'src/libraries/PoolUtils.sol';

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
        vm.prank(_borrower3);
        _quote.approve(address(_pool), 200_000 * 1e18);
        vm.prank(_borrower2);
        _quote.approve(address(_pool), 200_000 * 1e18);
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

    function testBorrowerInterestCalculation() external tearDown {
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
        (uint256 liquidityAdded, , , , ) = _poolUtils.poolLoansInfo(address(_pool));

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
        uint256 expectedDebt = 5_004.807692307692310000 * 1e18;
        (uint256 poolDebt,,) = _pool.debtInfo();
        assertEq(poolDebt, expectedDebt);
        _assertBorrower(
            {
                borrower:                  _borrower,
                borrowerDebt:              expectedDebt,
                borrowerCollateral:        3 * 1e18,
                borrowerMompFactor:        3_010.892022197881557845 * 1e18,
                borrowerCollateralization: 1.804799828867894420 * 1e18
            }
        );
        _assertLenderInterest(liquidityAdded, 0); 

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

        expectedDebt = 5_012.354868151222773335 * 1e18;
        (poolDebt,,) = _pool.debtInfo();
        assertEq(poolDebt, expectedDebt);
        _assertBorrower(
            {
                borrower:                  _borrower,
                borrowerDebt:              expectedDebt,
                borrowerCollateral:        4 * 1e18,
                borrowerMompFactor:        3_006.358478158173141857 * 1e18,
                borrowerCollateralization: 2.402776420583669600 * 1e18
            }
        );
        _assertLenderInterest(liquidityAdded, 6.454207045591150000 * 1e18);  

        // borrower pulls some of their collateral after some time has passed
        skip(10 days);

        _pullCollateral(
            {
                from:   _borrower,
                amount: 1
            }
        );

        expectedDebt = 5_020.669907328529218397 * 1e18;
        (poolDebt,,) = _pool.debtInfo();
        assertEq(poolDebt, expectedDebt);
        _assertBorrower(
            {
                borrower:                  _borrower,
                borrowerDebt:              expectedDebt,
                borrowerCollateral:        3 * 1e18,
                borrowerMompFactor:        3_001.379463606664041733 * 1e18,
                borrowerCollateralization: 1.799097776455867782 * 1e18
            }
        );
        _assertLenderInterest(liquidityAdded, 13.565138359073600000 * 1e18);

        // borrower borrows some additional quote after some time has passed
        skip(10 days);

        _borrow(
            {
                from:       _borrower,
                amount:     1_000 * 1e18,
                indexLimit: 3_000,
                newLup:     3_010.892022197881557845 * 1e18
            }
        );

        expectedDebt = 6_031.112190940595898550 * 1e18;
        (poolDebt,,) = _pool.debtInfo();
        assertEq(poolDebt, expectedDebt);
        _assertBorrower(
            {
                borrower:                  _borrower,
                borrowerDebt:              expectedDebt,
                borrowerCollateral:        3 * 1e18,
                borrowerMompFactor:        2_995.912071263145122807 * 1e18,
                borrowerCollateralization: 1.497679993444945851 * 1e18
            }
        );
        _assertLenderInterest(liquidityAdded, 21.400863103971100000 * 1e18);

        // mint additional quote to borrower to enable repayment
        deal(address(_quote), _borrower, 20_000 * 1e18);

        // borrower repays their loan after some additional time
        skip(10 days);

        _repay(
            {
                from:     _borrower,
                borrower: _borrower,
                amount:   6_043.220426872049838854 * 1e18,
                repaid:   6_043.220426872049838854 * 1e18,
                newLup:   BucketMath.MAX_PRICE
            }
        );

        (poolDebt,,) = _pool.debtInfo();
        assertEq(poolDebt, 0);

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

    function testMultipleBorrowerInterestAccumulation() external tearDown {
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
        (uint256 liquidityAdded, , , , ) = _poolUtils.poolLoansInfo(address(_pool));

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
        uint256 expectedBorrower1Debt = 8_007.692307692307696000 * 1e18;
        (uint256 poolDebt,,) = _pool.debtInfo();
        assertEq(poolDebt, expectedBorrower1Debt);
        _assertBorrower(
            {
                borrower:                  _borrower,
                borrowerDebt:              expectedBorrower1Debt,
                borrowerCollateral:        3 * 1e18,
                borrowerMompFactor:        3_010.892022197881557845 * 1e18,
                borrowerCollateralization: 1.127999893042434013 * 1e18
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
        expectedBorrower1Debt = 8_007.875133804645608008 * 1e18;
        uint256 expectedBorrower2Debt = 2_752.644230769230770500 * 1e18;
        uint256 expectedPoolDebt = 10_760.519364573876378508 * 1e18;
        (poolDebt,,) = _pool.debtInfo();
        assertEq(poolDebt, expectedPoolDebt);
        _assertBorrower(
            {
                borrower:                  _borrower,
                borrowerDebt:              expectedBorrower1Debt,
                borrowerCollateral:        3 * 1e18,
                borrowerMompFactor:        3_010.892022197881557845 * 1e18,
                borrowerCollateralization: 1.122362328272840838 * 1e18
            }
        );
        _assertBorrower(
            {
                borrower:                  _borrower2,
                borrowerDebt:              expectedBorrower2Debt,
                borrowerCollateral:        1 * 1e18,
                borrowerMompFactor:        3010.823281155608819803 * 1e18,
                borrowerCollateralization: 1.088376197116173336 * 1e18
            }
        );
        _assertLenderInterest(liquidityAdded, 0.158098662307440000 * 1e18);

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
        expectedBorrower1Debt = 8_008.057964091143327677 * 1e18;
         expectedBorrower2Debt = 2_752.707077245346929053 * 1e18;
        uint256 expectedBorrower3Debt = 2_502.403846153846155000 * 1e18;
        expectedPoolDebt = 13_263.168887490336411731 * 1e18;
        (poolDebt,,) = _pool.debtInfo();
        assertEq(poolDebt, expectedPoolDebt);
        _assertBorrower(
            {
                borrower:                  _borrower,
                borrowerDebt:              expectedBorrower1Debt,
                borrowerCollateral:        3 * 1e18,
                borrowerMompFactor:        3_010.892022197881557845 * 1e18,
                borrowerCollateralization: 1.122336703854666979 * 1e18
            }
        );
        _assertBorrower(
            {
                borrower:                  _borrower2,
                borrowerDebt:              expectedBorrower2Debt,
                borrowerCollateral:        1 * 1e18,
                borrowerMompFactor:        3_010.823281155608819803 * 1e18,
                borrowerCollateralization: 1.088351348628209297 * 1e18
            }
        );
        _assertBorrower(
            {
                borrower:                  _borrower3,
                borrowerDebt:              expectedBorrower3Debt,
                borrowerCollateral:        1 * 1e18,
                borrowerMompFactor:        3_010.754541682748353480 * 1e18,
                borrowerCollateralization: 1.197213816827790670 * 1e18
            }
        );
        _assertLenderInterest(liquidityAdded, 0.371995968618930000 * 1e18);

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
        liquidityAdded += 1e18;

        // check pool and borrower debt to confirm interest has accumulated
        expectedPoolDebt = 13_263.471703022178416340 * 1e18;
        (poolDebt,,) = _pool.debtInfo();
        assertEq(poolDebt, expectedPoolDebt);
        _assertLenderInterest(liquidityAdded, 0.637418685977190000 * 1e18);

        expectedBorrower1Debt = 8_008.240798551896146546 * 1e18;
        _assertBorrower(
            {
                borrower:                  _borrower,
                borrowerDebt:              expectedBorrower1Debt,
                borrowerCollateral:        3 * 1e18,
                borrowerMompFactor:        3_010.892022197881557845 * 1e18,
                borrowerCollateralization: 1.122311080021518821 * 1e18
            }
        );
        expectedBorrower2Debt = 2_752.769925156330518052 * 1e18;
        _assertBorrower(
            {
                borrower:                  _borrower2,
                borrowerDebt:              expectedBorrower2Debt,
                borrowerCollateral:        1 * 1e18,
                borrowerMompFactor:        3_010.823281155608819803 * 1e18,
                borrowerCollateralization: 1.088326500707555859 * 1e18
            }
        );
        expectedBorrower3Debt = 2_502.460979313951751742 * 1e18;
        _assertBorrower(
            {
                borrower:                  _borrower3,
                borrowerDebt:              expectedBorrower3Debt,
                borrowerCollateral:        1 * 1e18,
                borrowerMompFactor:        3_010.754541682748353480 * 1e18,
                borrowerCollateralization: 1.197186483491030227 * 1e18
            }
        );

        // ensure debt from the three borrowers adds up to the pool debt
        assertEq(expectedPoolDebt, expectedBorrower1Debt + expectedBorrower2Debt + expectedBorrower3Debt);
    }

    function testBorrowerInterestCalculationAfterRepayingAllDebtOnce() external tearDown {
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
        (uint256 liquidityAdded, , , , ) = _poolUtils.poolLoansInfo(address(_pool));

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

        uint256 expectedDebt = 5_004.807692307692310000 * 1e18;
        (uint256 poolDebt, , ) = _pool.debtInfo();
        assertEq(poolDebt, expectedDebt);
        _assertBorrower(
            {
                borrower:                  _borrower,
                borrowerDebt:              expectedDebt,
                borrowerCollateral:        3 * 1e18,
                borrowerMompFactor:        3_010.892022197881557845 * 1e18,
                borrowerCollateralization: 1.804799828867894420 * 1e18
            }
        );

        // time passes and interest accrues
        skip(30 days);

        expectedDebt = 5_027.483380088742884664 * 1e18;
        (poolDebt, , ) = _pool.debtInfo();
        assertEq(poolDebt, expectedDebt);
        _assertBorrower(
            {
                borrower:                  _borrower,
                borrowerDebt:              expectedDebt,
                borrowerCollateral:        3 * 1e18,
                borrowerMompFactor:        3_010.892022197881557845 * 1e18,
                borrowerCollateralization: 1.796659557815227213 * 1e18
            }
        );

        // mint additional quote to borrower to enable repayment
        deal(address(_quote), _borrower, 20_000 * 1e18);

        // borrower repays their loan after some additional time
        skip(10 days);

        _repay(
            {
                from:     _borrower,
                borrower: _borrower,
                amount:   6_000 * 1e18,
                repaid:   5_035.064750533460450062 * 1e18,
                newLup:   BucketMath.MAX_PRICE
            }
        );

        (poolDebt, , ) = _pool.debtInfo();
        assertEq(poolDebt, 0);

        _assertBorrower(
            {
                borrower:                  _borrower,
                borrowerDebt:              0,
                borrowerCollateral:        3 * 1e18,
                borrowerMompFactor:        0,
                borrowerCollateralization: 1 * 1e18
            }
        );
        _assertLenderInterest(liquidityAdded, 25.875284004017950000 * 1e18);


        // Borrower borrows Again Once repayed All debt 

        _borrow(
            {
                from:       _borrower,
                amount:     5_000 * 1e18,
                indexLimit: 2_551,
                newLup:     3_010.892022197881557845 * 1e18
            }
        );

        expectedDebt = 5_005.288461538461540000 * 1e18;
        (poolDebt, , ) = _pool.debtInfo();
        assertEq(poolDebt, expectedDebt);

        _assertBorrower(
            {
                borrower:                  _borrower,
                borrowerDebt:              expectedDebt,
                borrowerCollateral:        3 * 1e18,
                borrowerMompFactor:        2_992.798762281514038843 * 1e18,
                borrowerCollateralization: 1.804626473779154828 * 1e18
            }
        );
        _assertLenderInterest(liquidityAdded, 25.875284004017950000 * 1e18);


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

        expectedDebt = 5_013.591778192248902657 * 1e18;
        (poolDebt, , ) = _pool.debtInfo();
        assertEq(poolDebt, expectedDebt);
        _assertBorrower(
            {
                borrower:                  _borrower,
                borrowerDebt:              expectedDebt,
                borrowerCollateral:        4 * 1e18,
                borrowerMompFactor:        2_987.842204806615968064 * 1e18,
                borrowerCollateralization: 2.402183628347594810 * 1e18
            }
        );
        _assertLenderInterest(liquidityAdded, 32.976110091508700000 * 1e18);

        // borrower pulls some of their collateral after some time has passed
        skip(10 days);

        _pullCollateral(
            {
                from:   _borrower,
                amount: 1
            }
        );

        expectedDebt = 5_022.741336874076464394 * 1e18;
        (poolDebt, , ) = _pool.debtInfo();
        assertEq(poolDebt, expectedDebt);
        _assertBorrower(
            {
                borrower:                  _borrower,
                borrowerDebt:              expectedDebt,
                borrowerCollateral:        3 * 1e18,
                borrowerMompFactor:        2_982.399472292356585038 * 1e18,
                borrowerCollateralization: 1.798355810258620132 * 1e18
            }
        );
        _assertLenderInterest(liquidityAdded, 40.800699487970150000 * 1e18);

        // borrower borrows some additional quote after some time has passed
        skip(10 days);

        _borrow(
            {
                from:       _borrower,
                amount:     1_000 * 1e18,
                indexLimit: 3_000,
                newLup:     3_010.892022197881557845 * 1e18
            }
        );

        expectedDebt = 6_034.232926665142656779 * 1e18;
        (poolDebt, , ) = _pool.debtInfo();
        assertEq(poolDebt, expectedDebt);
        _assertBorrower(
            {
                borrower:                  _borrower,
                borrowerDebt:              expectedDebt,
                borrowerCollateral:        3 * 1e18,
                borrowerMompFactor:        2_976.423917223773588552 * 1e18,
                borrowerCollateralization: 1.496905435432969068 * 1e18
            }
        );
        _assertLenderInterest(liquidityAdded, 49.424332079106750000 * 1e18);

        // mint additional quote to borrower to enable repayment
        deal(address(_quote), _borrower, 20_000 * 1e18);

        // borrower repays their loan after some additional time
        skip(10 days);
        
        _repay(
            {
                from:     _borrower,
                borrower: _borrower,
                amount:   7_000 * 1e18,
                repaid:   6_047.560214870786628632 * 1e18,
                newLup:   BucketMath.MAX_PRICE
            }
        );

        (poolDebt, , ) = _pool.debtInfo();
        assertEq(poolDebt, 0);

        _assertBorrower(
            {
                borrower:                  _borrower,
                borrowerDebt:              0,
                borrowerCollateral:        3 * 1e18,
                borrowerMompFactor:        0,
                borrowerCollateralization: 1 * 1e18
            }
        );
        _assertLenderInterest(liquidityAdded, 60.836331709962400000 * 1e18);

    }
}