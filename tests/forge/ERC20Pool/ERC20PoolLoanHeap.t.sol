// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.14;

import { ERC20HelperContract } from './ERC20DSTestPlus.sol';

import 'src/libraries/helpers/PoolHelper.sol';

contract ERC20PoolLoanHeapTest is ERC20HelperContract {

    address internal _borrower1;
    address internal _borrower2;
    address internal _borrower3;
    address internal _borrower4;
    address internal _borrower5;
    address internal _borrower6;
    address internal _lender1;
    address internal _lender2;
    address internal _lender3;
    address internal _lender4;

    function setUp() external {
        _borrower1 = makeAddr("borrower1");
        _borrower2 = makeAddr("borrower2");
        _borrower3 = makeAddr("borrower3");
        _borrower4 = makeAddr("borrower4");
        _borrower5 = makeAddr("borrower5");
        _borrower6 = makeAddr("borrower6");
        _lender1   = makeAddr("lender1");
        _lender2   = makeAddr("lender2");
        _lender3   = makeAddr("lender3");
        _lender4   = makeAddr("lender4");

        _mintQuoteAndApproveTokens(_lender1, 150_000 * 1e18);
        _mintQuoteAndApproveTokens(_lender2, 150_000 * 1e18);
        _mintQuoteAndApproveTokens(_lender3, 150_000 * 1e18);
        _mintQuoteAndApproveTokens(_lender4, 5_000 * 1e18);

        _mintCollateralAndApproveTokens(_lender1,   1_000 * 1e18);
        _mintCollateralAndApproveTokens(_lender3,   1_000 * 1e18);
        _mintCollateralAndApproveTokens(_borrower1, 1_000 * 1e18);
        _mintCollateralAndApproveTokens(_borrower2, 1_000 * 1e18);
        _mintCollateralAndApproveTokens(_borrower3, 1_000 * 1e18);
        _mintCollateralAndApproveTokens(_borrower4, 1_000 * 1e18);
        _mintCollateralAndApproveTokens(_borrower5, 1_000 * 1e18);
        _mintCollateralAndApproveTokens(_borrower6, 1_000 * 1e18);

        // Lender 1 adds Quote token accross 3 buckets
        _addInitialLiquidity({
            from:   _lender1,
            amount: 50_000 * 1e18,
            index:  2500
        });
        _addInitialLiquidity({
            from:   _lender1,
            amount: 50_000 * 1e18,
            index:  2501
        });
        _addInitialLiquidity({
            from:   _lender1,
            amount: 1_000 * 1e18,
            index:  2502
        });
    }
    
    function testLoanHeapUpdateThresholdPrice() external {
        // all 6 borrowers draw debt from pool
        _drawDebt({
            from:               _borrower1,
            borrower:           _borrower1,
            amountToBorrow:     1_000 * 1e18,
            limitIndex:         5000,
            collateralToPledge: 1_000 * 1e18,
            newLup:             3_863.654368867279344664 * 1e18
        });
        _drawDebt({
            from:               _borrower2,
            borrower:           _borrower2,
            amountToBorrow:     2_000 * 1e18,
            limitIndex:         5000,
            collateralToPledge: 1_000 * 1e18,
            newLup:             3_863.654368867279344664 * 1e18
        });
        _drawDebt({
            from:               _borrower3,
            borrower:           _borrower3,
            amountToBorrow:     3_000 * 1e18,
            limitIndex:         5000,
            collateralToPledge: 1_000 * 1e18,
            newLup:             3_863.654368867279344664 * 1e18
        });
        _drawDebt({
            from:               _borrower4,
            borrower:           _borrower4,
            amountToBorrow:     4_000 * 1e18,
            limitIndex:         5000,
            collateralToPledge: 1_000 * 1e18,
            newLup:             3_863.654368867279344664 * 1e18
        });
        _drawDebt({
            from:               _borrower5,
            borrower:           _borrower5,
            amountToBorrow:     5_000 * 1e18,
            limitIndex:         5000,
            collateralToPledge: 1_000 * 1e18,
            newLup:             3_863.654368867279344664 * 1e18
        });
        _drawDebt({
            from:               _borrower6,
            borrower:           _borrower6,
            amountToBorrow:     6_000 * 1e18,
            limitIndex:         5000,
            collateralToPledge: 1_000 * 1e18,
            newLup:             3_863.654368867279344664 * 1e18
        });

        _assertLoans({
            noOfLoans:         6,
            maxBorrower:       _borrower6,
            maxThresholdPrice: 6.005769230769230772 * 1e18
        });

        // borrower 4 draws debt and becomes loan with highest threshold price in heap
        _drawDebt({
            from:               _borrower4,
            borrower:           _borrower4,
            amountToBorrow:     10_000 * 1e18,
            limitIndex:         5000,
            collateralToPledge: 0,
            newLup:             3_863.654368867279344664 * 1e18
        });

        _assertLoans({
            noOfLoans:         6,
            maxBorrower:       _borrower4,
            maxThresholdPrice: 14.013461538461538468 * 1e18
        });

        // borrower 4 repays debt, borrower 6 becomes loan with highest threshold price in heap
        _repayDebt({
            from:             _borrower4,
            borrower:         _borrower4,
            amountToRepay:    11_000 * 1e18,
            amountRepaid:     11_000 * 1e18,
            collateralToPull: 0,
            newLup:           3_863.654368867279344664 * 1e18
        });

        _assertLoans({
            noOfLoans:         6,
            maxBorrower:       _borrower6,
            maxThresholdPrice: 6.005769230769230772 * 1e18
        });

        // borrower 6 repays debt, borrower 5 becomes loan with highest threshold price in heap
        _repayDebt({
            from:             _borrower6,
            borrower:         _borrower6,
            amountToRepay:    5_000 * 1e18,
            amountRepaid:     5_000 * 1e18,
            collateralToPull: 0,
            newLup:           3_863.654368867279344664 * 1e18
        });

        _assertLoans({
            noOfLoans:         6,
            maxBorrower:       _borrower5,
            maxThresholdPrice: 5.004807692307692310 * 1e18
        });

        // borrower 6 draws more debt and becomes loan with highest threshold price in heap
        _drawDebt({
            from:               _borrower6,
            borrower:           _borrower6,
            amountToBorrow:     11_000 * 1e18,
            limitIndex:         5000,
            collateralToPledge: 0,
            newLup:             3_863.654368867279344664 * 1e18
        });

        _assertLoans({
            noOfLoans:         6,
            maxBorrower:       _borrower6,
            maxThresholdPrice: 12.016346153846153854 * 1e18
        });
    }
}