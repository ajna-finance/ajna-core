// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.18;

import { ERC721HelperContract } from './ERC721DSTestPlus.sol';
import 'src/ERC721Pool.sol';

import { MAX_PRICE, _priceAt } from 'src/libraries/helpers/PoolHelper.sol';

abstract contract ERC721PoolInterestTest is ERC721HelperContract {
    address internal _borrower;
    address internal _borrower2;
    address internal _borrower3;
    address internal _lender;
    address internal _lender2;

    // Called by setUp method to set the _pool which tests will use
    function createPool() external virtual returns (ERC721Pool);

    function setUp() external {
        _startTest();

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
        _addInitialLiquidity({
            from:   _lender,
            amount: 10_000 * 1e18,
            index:  2550
        });
        _addInitialLiquidity({
            from:   _lender,
            amount: 10_000 * 1e18,
            index:  2551
        });
        _addInitialLiquidity({
            from:   _lender,
            amount: 10_000 * 1e18,
            index:  2552
        });
        _addInitialLiquidity({
            from:   _lender,
            amount: 10_000 * 1e18,
            index:  2553
        });
        _addInitialLiquidity({
            from:   _lender,
            amount: 10_000 * 1e18,
            index:  2554
        });

        (uint256 liquidityAdded, , , , ) = _poolUtils.poolLoansInfo(address(_pool));

        skip(10 days);

        // borrower adds collateral and borrows initial amount
        uint256[] memory tokenIdsToAdd = new uint256[](3);
        tokenIdsToAdd[0] = 1;
        tokenIdsToAdd[1] = 3;
        tokenIdsToAdd[2] = 5;
        _pledgeCollateral({
            from:     _borrower,
            borrower: _borrower,
            tokenIds: tokenIdsToAdd
        });
        _borrow({
            from:       _borrower,
            amount:     5_000 * 1e18,
            indexLimit: 2_551,
            newLup:     3_010.892022197881557845 * 1e18
        });

        uint256 expectedDebt = 5_004.326923076923075000 * 1e18;
        (uint256 poolDebt,,,) = _pool.debtInfo();
        assertEq(poolDebt, expectedDebt);

        _assertBorrower({
            borrower:                  _borrower,
            borrowerDebt:              expectedDebt,
            borrowerCollateral:        3 * 1e18,
            borrowert0Np:              1_918.840195467602660987 * 1e18,
            borrowerCollateralization: 1.735551170447429086 * 1e18
        });

        _assertLenderInterest(liquidityAdded, 0); 

        // borrower pledge additional collateral after some time has passed
        skip(10 days);
        tokenIdsToAdd = new uint256[](1);
        tokenIdsToAdd[0] = 51;
        _pledgeCollateral({
            from:     _borrower,
            borrower: _borrower,
            tokenIds: tokenIdsToAdd
        });

        expectedDebt = 5_010.500446015624727374 * 1e18;
        (poolDebt,,,) = _pool.debtInfo();
        assertEq(poolDebt, expectedDebt);

        _assertBorrower({
            borrower:                  _borrower,
            borrowerDebt:              expectedDebt,
            borrowerCollateral:        4 * 1e18,
            borrowert0Np:              1_439.130146600701995740 * 1e18,
            borrowerCollateralization: 2.311217024387068890 * 1e18
        });

        _assertLenderInterest(liquidityAdded, 5.247494497896371966 * 1e18);

        // borrower pulls some of their collateral after some time has passed
        skip(10 days);

        _approveAndRepayDebtNoLupCheck({
            from:             _borrower,
            borrower:         _borrower,
            amountToRepay:    0,
            amountRepaid:     0,
            collateralToPull: 1
        });

        expectedDebt = 5_016.063127975675193807 * 1e18;
        (poolDebt,,,) = _pool.debtInfo();
        assertEq(poolDebt, expectedDebt);

        _assertBorrower({
            borrower:                  _borrower,
            borrowerDebt:              expectedDebt,
            borrowerCollateral:        3 * 1e18,
            borrowert0Np:              1_909.397570166798164136 * 1e18,
            borrowerCollateralization: 1.731490459162708814 * 1e18
        });

        _assertLenderInterest(liquidityAdded, 10.004597057423574190 * 1e18);

        // borrower borrows some additional quote after some time has passed
        skip(10 days);

        _borrow({
            from:       _borrower,
            amount:     1_000 * 1e18,
            indexLimit: 3_000,
            newLup:     3_010.892022197881557845 * 1e18
        });

        expectedDebt = 6_021.775783320497493094 * 1e18;
        (poolDebt,,,) = _pool.debtInfo();
        assertEq(poolDebt, expectedDebt);

        _assertBorrower({
            borrower:                  _borrower,
            borrowerDebt:              expectedDebt,
            borrowerCollateral:        3 * 1e18,
            borrowert0Np:              2_279.197387150401832726 * 1e18,
            borrowerCollateralization: 1.442309670961968235 * 1e18
        });

        _assertLenderInterest(liquidityAdded, 14.290535149874139349 * 1e18);

        // mint additional quote to borrower to enable repayment
        deal(address(_quote), _borrower, 20_000 * 1e18);

        // borrower repays their loan after some additional time
        skip(10 days);

        _approveAndRepayDebt({
            from:             _borrower,
            borrower:         _borrower,
            amountToRepay:    6_027.190390289235012951 * 1e18,
            amountRepaid:     6_027.190390289235012951 * 1e18,
            collateralToPull: 0,
            newLup:           MAX_PRICE
        });

        (poolDebt,,,) = _pool.debtInfo();
        assertEq(poolDebt, 0);  

        _assertBorrower({
            borrower:                  _borrower,
            borrowerDebt:              0,
            borrowerCollateral:        3 * 1e18,
            borrowert0Np:              0.000000000000000000 * 1e18,
            borrowerCollateralization: 1 * 1e18
        });
    }

    function testMultipleBorrowerInterestAccumulation() external tearDown {
        // lender deposits 10000 Quote into 3 buckets
        _addInitialLiquidity({
            from:   _lender,
            amount: 10_000 * 1e18,
            index:  2550
        });
        _addInitialLiquidity({
            from:   _lender,
            amount: 10_000 * 1e18,
            index:  2551
        });
        _addInitialLiquidity({
            from:   _lender,
            amount: 10_000 * 1e18,
            index:  2552
        });

        (uint256 liquidityAdded, , , , ) = _poolUtils.poolLoansInfo(address(_pool));

        skip(2 hours);

        // borrower pledges three NFTs and takes out a loan with TP around 2666
        uint256[] memory tokenIdsToAdd = new uint256[](3);
        tokenIdsToAdd[0] = 1;
        tokenIdsToAdd[1] = 3;
        tokenIdsToAdd[2] = 5;
        _pledgeCollateral({
            from:     _borrower,
            borrower: _borrower,
            tokenIds: tokenIdsToAdd
        });

        uint256 borrowAmount = 8_000 * 1e18;

        _borrow({
            from:       _borrower,
            amount:     borrowAmount,
            indexLimit: 2_551,
            newLup:     _priceAt(2550)
        });

        uint256 expectedBorrower1Debt = 8_007.692307692307696000 * 1e18;
        (uint256 poolDebt,,,) = _pool.debtInfo();
        assertEq(poolDebt, expectedBorrower1Debt);

        _assertBorrower({
            borrower:                  _borrower,
            borrowerDebt:              expectedBorrower1Debt,
            borrowerCollateral:        3 * 1e18,
            borrowert0Np:              3_086.366235276970809007 * 1e18,
            borrowerCollateralization: 1.084615281771571166 * 1e18
        });

        skip(4 hours);

        // borrower 2 pledges one NFT and takes out a loan with TP around 2750
        tokenIdsToAdd = new uint256[](1);
        tokenIdsToAdd[0] = 53;
        _pledgeCollateral({
            from:     _borrower2,
            borrower: _borrower2,
            tokenIds: tokenIdsToAdd
        });

        borrowAmount = 2_750 * 1e18;
        _borrow({
            from:       _borrower2,
            amount:     borrowAmount,
            indexLimit: 3_000,
            newLup:     _priceAt(2551)
        });

        expectedBorrower1Debt = 8_007.875133804645608008 * 1e18;
        uint256 expectedBorrower2Debt = 2_752.644230769230770501 * 1e18;
        uint256 expectedPoolDebt = 10_760.519364573876378509 * 1e18;
        (poolDebt,,,) = _pool.debtInfo();
        assertEq(poolDebt, expectedPoolDebt);

        _assertBorrower({
            borrower:                  _borrower,
            borrowerDebt:              expectedBorrower1Debt,
            borrowerCollateral:        3 * 1e18,
            borrowert0Np:              3_086.366235276970809007 * 1e18,
            borrowerCollateralization: 1.079194546416193113 * 1e18
        });
        _assertBorrower({
            borrower:                  _borrower2,
            borrowerDebt:              expectedBorrower2Debt,
            borrowerCollateral:        1 * 1e18,
            borrowert0Np:              3_182.742513945656986337 * 1e18,
            borrowerCollateralization: 1.046515574150166669 * 1e18
        });

        _assertLenderInterest(liquidityAdded, 0.155402195487205849 * 1e18);

        skip(4 hours);

        // borrower 3 pledges one NFT and takes out a loan with TP around 2500
        tokenIdsToAdd = new uint256[](1);
        tokenIdsToAdd[0] = 73;
        _pledgeCollateral({
            from:     _borrower3,
            borrower: _borrower3,
            tokenIds: tokenIdsToAdd
        });

        borrowAmount = 2_500 * 1e18;
        _borrow({
            from:       _borrower3,
            amount:     borrowAmount,
            indexLimit: 3_000,
            newLup:     _priceAt(2551)
        });

        expectedBorrower1Debt = 8_008.057964091143327678 * 1e18;
         expectedBorrower2Debt = 2_752.707077245346929055 * 1e18;
        uint256 expectedBorrower3Debt = 2_502.403846153846155001 * 1e18;
        expectedPoolDebt = 13_263.168887490336411732 * 1e18;

        (poolDebt,,,) = _pool.debtInfo();
        assertEq(poolDebt, expectedPoolDebt);

        _assertBorrower({
            borrower:                  _borrower,
            borrowerDebt:              expectedBorrower1Debt,
            borrowerCollateral:        3 * 1e18,
            borrowert0Np:              3_086.366235276970809007 * 1e18,
            borrowerCollateralization: 1.079169907552564403 * 1e18
        });
        _assertBorrower({
            borrower:                  _borrower2,
            borrowerDebt:              expectedBorrower2Debt,
            borrowerCollateral:        1 * 1e18,
            borrowert0Np:              3_182.742513945656986337 * 1e18,
            borrowerCollateralization: 1.046491681373278170 * 1e18
        });
        _assertBorrower({
            borrower:                  _borrower3,
            borrowerDebt:              expectedBorrower3Debt,
            borrowerCollateral:        1 * 1e18,
            borrowert0Np:              2_893.336226746331069131 * 1e18,
            borrowerCollateralization: 1.151167131565183336 * 1e18
        });

        _assertLenderInterest(liquidityAdded, 0.365554368557644878 * 1e18);

        skip(4 hours);

        // trigger an interest accumulation
        _addLiquidity({
            from:    _lender,
            amount:  1 * 1e18,
            index:   2550,
            lpAward: 0.999933471831480917 * 1e18,
            newLup:  2995.912459898389633881 * 1e18
        });
        liquidityAdded += 1e18;

        // check pool and borrower debt to confirm interest has accumulated
        expectedPoolDebt = 13_263.471703022178416342 * 1e18;

        (poolDebt,,,) = _pool.debtInfo();
        assertEq(poolDebt, expectedPoolDebt);

        _assertLenderInterest(liquidityAdded, 0.625949442426308567 * 1e18);

        expectedBorrower1Debt = 8_008.240798551896146547 * 1e18;

        _assertBorrower({
            borrower:                  _borrower,
            borrowerDebt:              expectedBorrower1Debt,
            borrowerCollateral:        3 * 1e18,
            borrowert0Np:              3_086.366235276970809007 * 1e18,
            borrowerCollateralization: 1.079145269251460405 * 1e18
        });

        expectedBorrower2Debt = 2_752.769925156330518053 * 1e18;

        _assertBorrower({
            borrower:                  _borrower2,
            borrowerDebt:              expectedBorrower2Debt,
            borrowerCollateral:        1 * 1e18,
            borrowert0Np:              3_182.742513945656986337 * 1e18,
            borrowerCollateralization: 1.046467789141880633 * 1e18
        });

        expectedBorrower3Debt = 2_502.460979313951751742 * 1e18;

        _assertBorrower({
            borrower:                  _borrower3,
            borrowerDebt:              expectedBorrower3Debt,
            borrowerCollateral:        1 * 1e18,
            borrowert0Np:              2_893.336226746331069131 * 1e18,
            borrowerCollateralization: 1.151140849510605988 * 1e18
        });

        // ensure debt from the three borrowers adds up to the pool debt
        assertEq(expectedPoolDebt, expectedBorrower1Debt + expectedBorrower2Debt + expectedBorrower3Debt);
    }

    function testBorrowerInterestCalculationAfterRepayingAllDebtOnce() external tearDown {
        _addInitialLiquidity({
            from:   _lender,
            amount: 10_000 * 1e18,
            index:  2550
        });
        _addInitialLiquidity({
            from:   _lender,
            amount: 10_000 * 1e18,
            index:  2551
        });
        _addInitialLiquidity({
            from:   _lender,
            amount: 10_000 * 1e18,
            index:  2552
        });
        _addInitialLiquidity({
            from:   _lender,
            amount: 10_000 * 1e18,
            index:  2553
        });
        _addInitialLiquidity({
            from:   _lender,
            amount: 10_000 * 1e18,
            index:  2554
        });

        (uint256 liquidityAdded, , , , ) = _poolUtils.poolLoansInfo(address(_pool));

        skip(10 days);

        // borrower adds collateral and borrows initial amount
        uint256[] memory tokenIdsToAdd = new uint256[](3);
        tokenIdsToAdd[0] = 1;
        tokenIdsToAdd[1] = 3;
        tokenIdsToAdd[2] = 5;
        _pledgeCollateral({
            from:     _borrower,
            borrower: _borrower,
            tokenIds: tokenIdsToAdd
        });
        _borrow({
            from:       _borrower,
            amount:     5_000 * 1e18,
            indexLimit: 2_551,
            newLup:     3_010.892022197881557845 * 1e18
        });

        uint256 expectedDebt = 5_004.326923076923075000 * 1e18;
        (uint256 poolDebt, , ,) = _pool.debtInfo();
        assertEq(poolDebt, expectedDebt);

        _assertBorrower({
            borrower:                  _borrower,
            borrowerDebt:              expectedDebt,
            borrowerCollateral:        3 * 1e18,
            borrowert0Np:              1_918.840195467602660987 * 1e18,
            borrowerCollateralization: 1.735551170447429086 * 1e18
        });

        // time passes and interest accrues
        skip(30 days);

        expectedDebt = 5_022.870348947539432924 * 1e18;
        (poolDebt, , ,) = _pool.debtInfo();
        assertEq(poolDebt, expectedDebt);

        _assertBorrower({
            borrower:                  _borrower,
            borrowerDebt:              expectedDebt,
            borrowerCollateral:        3 * 1e18,
            borrowert0Np:              1_918.840195467602660987 * 1e18,
            borrowerCollateralization: 1.729143865014869634 * 1e18
        });

        // mint additional quote to borrower to enable repayment
        deal(address(_quote), _borrower, 20_000 * 1e18);

        // borrower repays their loan after some additional time
        skip(10 days);

        _approveAndRepayDebt({
            from:             _borrower,
            borrower:         _borrower,
            amountToRepay:    6_000 * 1e18,
            amountRepaid:     5_029.066747742821613943 * 1e18,
            collateralToPull: 0,
            newLup:           MAX_PRICE
        });

        (poolDebt, , ,) = _pool.debtInfo();
        assertEq(poolDebt, 0);

        _assertBorrower({
            borrower:                  _borrower,
            borrowerDebt:              0,
            borrowerCollateral:        3 * 1e18,
            borrowert0Np:              0,
            borrowerCollateralization: 1 * 1e18
        });

        _assertLenderInterest(liquidityAdded, 21.028850966013719555 * 1e18);

        // borrower borrows again once repayed all debt 
        _borrow({
            from:       _borrower,
            amount:     5_000 * 1e18,
            indexLimit: 2_551,
            newLup:     3_010.892022197881557845 * 1e18
        });

        expectedDebt = 5_003.894230769230770001 * 1e18;
        (poolDebt, , ,) = _pool.debtInfo();
        assertEq(poolDebt, expectedDebt);

        _assertBorrower({
            borrower:                  _borrower,
            borrowerDebt:              expectedDebt,
            borrowerCollateral:        3 * 1e18,
            borrowert0Np:              1_899.840261593407406983 * 1e18,
            borrowerCollateralization: 1.735701245490270976 * 1e18
        });

        _assertLenderInterest(liquidityAdded, 21.028850966013719555 * 1e18);

        // borrower pledge additional collateral after some time has passed
        skip(10 days);
        tokenIdsToAdd = new uint256[](1);
        tokenIdsToAdd[0] = 51;
        _pledgeCollateral({
            from:     _borrower,
            borrower: _borrower,
            tokenIds: tokenIdsToAdd
        });

        expectedDebt = 5_009.449578476990224066 * 1e18;
        (poolDebt, , ,) = _pool.debtInfo();
        assertEq(poolDebt, expectedDebt);

        _assertBorrower({
            borrower:                  _borrower,
            borrowerDebt:              expectedDebt,
            borrowerCollateral:        4 * 1e18,
            borrowert0Np:              1_424.880196195055555237 * 1e18,
            borrowerCollateralization: 2.311701864668943973 * 1e18
        });

        _assertLenderInterest(liquidityAdded, 25.779681437299323212 * 1e18);

        // borrower pulls some of their collateral after some time has passed
        skip(10 days);

        _approveAndRepayDebtNoLupCheck({
            from:             _borrower,
            borrower:         _borrower,
            amountToRepay:    0,
            amountRepaid:     0,
            collateralToPull: 1
        });

        expectedDebt = 5_014.454664494689841710 * 1e18;
        (poolDebt, , ,) = _pool.debtInfo();
        assertEq(poolDebt, expectedDebt);

        _assertBorrower({
            borrower:                  _borrower,
            borrowerDebt:              expectedDebt,
            borrowerCollateral:        3 * 1e18,
            borrowert0Np:              1_890.927039405678542204 * 1e18,
            borrowerCollateralization: 1.732045861366453421 * 1e18
        });

        _assertLenderInterest(liquidityAdded, 30.059924682352556770 * 1e18);

        // borrower borrows some additional quote after some time has passed
        skip(10 days);

        _borrow({
            from:       _borrower,
            amount:     1_000 * 1e18,
            indexLimit: 3_000,
            newLup:     3_010.892022197881557845 * 1e18
        });

        expectedDebt = 6_019.594382773827921758 * 1e18;
        (poolDebt, , ,) = _pool.debtInfo();
        assertEq(poolDebt, expectedDebt);

        _assertBorrower({
            borrower:                  _borrower,
            borrowerDebt:              expectedDebt,
            borrowerCollateral:        3 * 1e18,
            borrowert0Np:              2_257.779541250011702731 * 1e18,
            borrowerCollateralization: 1.442832339916824534 * 1e18
        });

        _assertLenderInterest(liquidityAdded, 33.915824463483626210 * 1e18);

        // mint additional quote to borrower to enable repayment
        deal(address(_quote), _borrower, 20_000 * 1e18);

        // borrower repays their loan after some additional time
        skip(10 days);

        _approveAndRepayDebt({
            from:             _borrower,
            borrower:         _borrower,
            amountToRepay:    7_000 * 1e18,
            amountRepaid:     6_024.465544800440916672 * 1e18,
            collateralToPull: 0,
            newLup:           MAX_PRICE
        });

        (poolDebt, , ,) = _pool.debtInfo();
        assertEq(poolDebt, 0);

        _assertBorrower({
            borrower:                  _borrower,
            borrowerDebt:              0,
            borrowerCollateral:        3 * 1e18,
            borrowert0Np:              0,
            borrowerCollateralization: 1 * 1e18
        });

        _assertLenderInterest(liquidityAdded, 38.081589196796064735 * 1e18);
    }
}
