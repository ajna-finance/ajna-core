// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.14;

import { ERC20Pool }        from "../../erc20/ERC20Pool.sol";
import { ERC20PoolFactory } from "../../erc20/ERC20PoolFactory.sol";

import { IERC20Pool } from "../../erc20/interfaces/IERC20Pool.sol";
import { IScaledPool } from "../../base/interfaces/IScaledPool.sol";

import { BucketMath } from "../../libraries/BucketMath.sol";

import { ERC20HelperContract } from "./ERC20DSTestPlus.sol";

contract ERC20ScaledBorrowTest is ERC20HelperContract {

    address internal _borrower;
    address internal _borrower2;
    address internal _lender;
    address internal _lender1;

    function setUp() external {
        _borrower  = makeAddr("borrower");
        _borrower2 = makeAddr("borrower2");
        _lender    = makeAddr("lender");
        _lender1   = makeAddr("lender1");

        _mintCollateralAndApproveTokens(_borrower,  100 * 1e18);
        _mintCollateralAndApproveTokens(_borrower2,  100 * 1e18);

        _mintQuoteAndApproveTokens(_lender,   200_000 * 1e18);
        _mintQuoteAndApproveTokens(_lender1,  200_000 * 1e18);
    }

    function testScaledPoolBorrowAndRepay() external {
        uint256 depositIndexHighest = 2550;
        uint256 depositIndexHigh    = 2551;
        uint256 depositIndexMed     = 2552;
        uint256 depositIndexLow     = 2553;
        uint256 depositIndexLowest  = 2554;

        // lender deposits 10000 DAI in 5 buckets each
        changePrank(_lender);
        _pool.addQuoteToken(10_000 * 1e18, depositIndexHighest);
        _pool.addQuoteToken(10_000 * 1e18, depositIndexHigh);
        _pool.addQuoteToken(10_000 * 1e18, depositIndexMed);
        _pool.addQuoteToken(10_000 * 1e18, depositIndexLow);
        _pool.addQuoteToken(10_000 * 1e18, depositIndexLowest);

        assertEq(_pool.htp(), 0);
        assertEq(_pool.lup(), BucketMath.MAX_PRICE);

        assertEq(_pool.poolSize(),              50_000 * 1e18);
        assertEq(_pool.borrowerDebt(),          0);
        assertEq(_pool.poolActualUtilization(), 0);
        assertEq(_pool.poolMinDebtAmount(),     0);

        // check balances
        assertEq(_quote.balanceOf(address(_pool)), 50_000 * 1e18);
        assertEq(_quote.balanceOf(_lender),        150_000 * 1e18);

        // borrower deposit 100 WETH collateral
        changePrank(_borrower);
        _pool.pledgeCollateral(_borrower, 100 * 1e18);
        assertEq(_pool.poolTargetUtilization(), 1 * 1e18);
        assertEq(_pool.poolActualUtilization(), 0);

        // get a 21_000 DAI loan
        vm.expectEmit(true, true, false, true);
        emit Borrow(_borrower, 2_981.007422784467321543 * 1e18, 21_000 * 1e18);
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(_pool), _borrower, 21_000 * 1e18);
        _pool.borrow(21_000 * 1e18, 3000);

        assertEq(_pool.htp(), 210.201923076923077020 * 1e18);
        assertEq(_pool.lup(), 2_981.007422784467321543 * 1e18);

        assertEq(_pool.poolSize(),     50_000 * 1e18);
        assertEq(_pool.borrowerDebt(), 21_020.192307692307702000 * 1e18);
        assertEq(_pool.poolTargetUtilization(), 1 * 1e18);
        assertEq(_pool.poolActualUtilization(), 0.420403846153846154 * 1e18);
        assertEq(_pool.poolMinDebtAmount(),     2_102.0192307692307702 * 1e18);

        // check balances
        assertEq(_quote.balanceOf(address(_pool)), 29_000 * 1e18);
        assertEq(_quote.balanceOf(_lender),        150_000 * 1e18);

        // check LPs
        (uint256 lpBalance, ) = _pool.bucketLenders(depositIndexHighest, _lender);
        assertEq(lpBalance, 10_000 * 1e27);
        (lpBalance, ) = _pool.bucketLenders(depositIndexHigh, _lender);
        assertEq(lpBalance, 10_000 * 1e27);
        (lpBalance, ) = _pool.bucketLenders(depositIndexMed, _lender);
        assertEq(lpBalance, 10_000 * 1e27);
        (lpBalance, ) = _pool.bucketLenders(depositIndexLow, _lender);
        assertEq(lpBalance, 10_000 * 1e27);
        (lpBalance, ) = _pool.bucketLenders(depositIndexLowest, _lender);
        assertEq(lpBalance, 10_000 * 1e27);

        // check buckets
        (uint256 lpAccumulator, uint256 availableCollateral) = _pool.buckets(depositIndexHighest);
        assertEq(lpAccumulator,       10_000 * 1e27);
        assertEq(availableCollateral, 0);
        (lpAccumulator, availableCollateral) = _pool.buckets(depositIndexHigh);
        assertEq(lpAccumulator,       10_000 * 1e27);
        assertEq(availableCollateral, 0);
        (lpAccumulator, availableCollateral) = _pool.buckets(depositIndexMed);
        assertEq(lpAccumulator,       10_000 * 1e27);
        assertEq(availableCollateral, 0);
        (lpAccumulator, availableCollateral) = _pool.buckets(depositIndexLow);
        assertEq(lpAccumulator,       10_000 * 1e27);
        assertEq(availableCollateral, 0);
        (lpAccumulator, availableCollateral) = _pool.buckets(depositIndexLowest);
        assertEq(lpAccumulator,       10_000 * 1e27);
        assertEq(availableCollateral, 0);

        // borrow 19_000 DAI
        vm.expectEmit(true, true, false, true);
        emit Borrow(_borrower, 2_951.419442869698640451 * 1e18, 19_000 * 1e18);
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(_pool), _borrower, 19_000 * 1e18);
        _pool.borrow(19_000 * 1e18, 3500);

        assertEq(_pool.htp(), 400.384615384615384800 * 1e18);
        assertEq(_pool.lup(), 2_951.419442869698640451 * 1e18);

        assertEq(_pool.poolSize(),          50_000 * 1e18);
        assertEq(_pool.borrowerDebt(),      40_038.461538461538480000 * 1e18);
        assertEq(_pool.poolMinDebtAmount(), 4_003.846153846153848 * 1e18);

        // check balances
        assertEq(_quote.balanceOf(address(_pool)), 10_000 * 1e18);
        assertEq(_quote.balanceOf(_lender),        150_000 * 1e18);

        // repay partial
        vm.expectEmit(true, true, false, true);
        emit Repay(_borrower, 2_966.176540084047110076 * 1e18, 10_000 * 1e18);
        vm.expectEmit(true, true, false, true);
        emit Transfer(_borrower, address(_pool), 10_000 * 1e18);
        _pool.repay(_borrower, 10_000 * 1e18);

        assertEq(_pool.htp(), 300.384615384615384800 * 1e18);
        assertEq(_pool.lup(), 2_966.176540084047110076 * 1e18);

        assertEq(_pool.poolSize(),     50_000 * 1e18);
        assertEq(_pool.borrowerDebt(), 30_038.461538461538480000 * 1e18);

        // check balances
        assertEq(_quote.balanceOf(address(_pool)), 20_000 * 1e18);
        assertEq(_quote.balanceOf(_lender),        150_000 * 1e18);

        // repay entire loan
        deal(address(_quote), _borrower,  _quote.balanceOf(_borrower) + 40 * 1e18);
        vm.expectEmit(true, true, false, true);
        emit Repay(_borrower, BucketMath.MAX_PRICE, 30_038.461538461538480000 * 1e18);
        vm.expectEmit(true, true, false, true);
        emit Transfer(_borrower, address(_pool), 30_038.461538461538480000 * 1e18);
        _pool.repay(_borrower, 30_040 * 1e18);

        assertEq(_pool.htp(), 0);
        assertEq(_pool.lup(), BucketMath.MAX_PRICE);

        assertEq(_pool.poolSize(),     50_000 * 1e18);
        assertEq(_pool.borrowerDebt(), 0);

        // check balances
        assertEq(_quote.balanceOf(address(_pool)), 50_038.461538461538480000 * 1e18);
        assertEq(_quote.balanceOf(_lender),        150_000 * 1e18);
    }

    function testScaledPoolBorrowerInterestAccumulation() external {
        uint256 depositIndexHighest = 2550;
        uint256 depositIndexHigh    = 2551;
        uint256 depositIndexMed     = 2552;
        uint256 depositIndexLow     = 2553;
        uint256 depositIndexLowest  = 2554;

        // lender deposits 10000 DAI in 5 buckets each
        changePrank(_lender);
        _pool.addQuoteToken(10_000 * 1e18, depositIndexHighest);
        _pool.addQuoteToken(10_000 * 1e18, depositIndexHigh);
        _pool.addQuoteToken(10_000 * 1e18, depositIndexMed);
        _pool.addQuoteToken(10_000 * 1e18, depositIndexLow);
        _pool.addQuoteToken(10_000 * 1e18, depositIndexLowest);

        skip(864000);

        changePrank(_borrower);
        _pool.pledgeCollateral(_borrower, 50 * 1e18);
        _pool.borrow(21_000 * 1e18, 3000);

        assertEq(_pool.borrowerDebt(), 21_020.192307692307702000 * 1e18);
        (uint256 debt, uint256 pendingDebt, uint256 col, uint256 inflator) = _pool.borrowerInfo(_borrower);
        assertEq(debt,        21_020.192307692307702000 * 1e18);
        assertEq(pendingDebt, 21_051.890446235135648008 * 1e18);
        assertEq(col,         50 * 1e18);
        assertEq(inflator,    1 * 1e18);

        skip(864000);
        _pool.pledgeCollateral(_borrower, 10 * 1e18);
        assertEq(_pool.borrowerDebt(), 21_083.636385101213387311 * 1e18);
        (debt, pendingDebt, col, inflator) = _pool.borrowerInfo(_borrower);
        assertEq(debt,        21_083.636385101213387311 * 1e18);
        assertEq(pendingDebt, 21_083.636385101213387311 * 1e18);
        assertEq(col,         60 * 1e18);
        assertEq(inflator,    1.003018244385218513 * 1e18);

        skip(864000);
        _pool.pullCollateral(10 * 1e18);
        assertEq(_pool.borrowerDebt(), 21_118.612213260575675180 * 1e18);
        (debt, pendingDebt, col, inflator) = _pool.borrowerInfo(_borrower);
        assertEq(debt,        21_118.612213260575675180 * 1e18);
        assertEq(pendingDebt, 21_118.612213260575675180 * 1e18);
        assertEq(col,         50 * 1e18);
        assertEq(inflator,    1.004682160092905114 * 1e18);

        skip(864000);
        _pool.borrow(0, 3000);
        assertEq(_pool.borrowerDebt(), 21_157.152643010853298669 * 1e18);
        (debt, pendingDebt, col, inflator) = _pool.borrowerInfo(_borrower);
        assertEq(debt,        21_157.152643010853298669 * 1e18);
        assertEq(pendingDebt, 21_157.152643010853298669 * 1e18);
        assertEq(col,         50 * 1e18);
        assertEq(inflator,    1.006515655675920014 * 1e18);

        skip(864000);
        _pool.repay(_borrower, 0);
        assertEq(_pool.borrowerDebt(), 21_199.628356897284446170 * 1e18);
        (debt, pendingDebt, col, inflator) = _pool.borrowerInfo(_borrower);
        assertEq(debt,        21_199.628356897284446170 * 1e18);
        assertEq(pendingDebt, 21_199.628356897284446170 * 1e18);
        assertEq(col,         50 * 1e18);
        assertEq(inflator,    1.008536365727696620 * 1e18);

        skip(864000);
        assertEq(_pool.borrowerDebt(), 21_199.628356897284446170 * 1e18);
        (debt, pendingDebt, col, inflator) = _pool.borrowerInfo(_borrower);
        assertEq(debt,        21_199.628356897284446170 * 1e18);
        assertEq(pendingDebt, 21_246.450141935843879765 * 1e18);
        assertEq(col,         50 * 1e18);
        assertEq(inflator,    1.008536365727696620 * 1e18);
    }

    /**
     *  @notice 1 lender, 2 borrowers tests reverts in borrow.
     *          Reverts:
     *              Attempts to borrow with no available quote.
     *              Attempts to borrow more than minimum amount.
     *              Attempts to borrow when result would be borrower under collateralization.
     *              Attempts to borrow when result would be pool under collateralization.
     */
    function testScaledPoolBorrowRequireChecks() external {
        // should revert if borrower attempts to borrow with an out of bounds limitIndex
        changePrank(_borrower);
        vm.expectRevert(IScaledPool.BorrowLimitIndexReached.selector);
        _pool.borrow(1_000 * 1e18, 5000);

        // add initial quote to the pool
        changePrank(_lender);
        _pool.addQuoteToken(10_000 * 1e18, 2550);
        _pool.addQuoteToken(10_000 * 1e18, 2551);

        changePrank(_borrower);
        // should revert if borrow would result in pool under collateralization
        vm.expectRevert(IScaledPool.BorrowPoolUnderCollateralized.selector);
        _pool.borrow(500 * 1e18, 3000);

        // borrower 1 borrows 500 quote from the pool after adding sufficient collateral
        _pool.pledgeCollateral(_borrower, 50 * 1e18);
        _pool.borrow(500 * 1e18, 3000);

        // borrower 2 borrows 15k quote from the pool with borrower2 becoming new queue HEAD
        changePrank(_borrower2);
        _pool.pledgeCollateral(_borrower2, 6 * 1e18);
        _pool.borrow(15_000 * 1e18, 3000);

        changePrank(_borrower);
        // should revert if borrower attempts to borrow more than minimum amount
        vm.expectRevert(IScaledPool.BorrowAmountLTMinDebt.selector);
        _pool.borrow(10 * 1e18, 3000);

        changePrank(_borrower2);
        // should revert if borrow would result in borrower under collateralization
        assertEq(_pool.lup(), 2_995.912459898389633881 * 1e18);

        vm.expectRevert(IScaledPool.BorrowBorrowerUnderCollateralized.selector);
        _pool.borrow(2_976 * 1e18, 3000);

        // should be able to borrow if properly specified
        vm.expectEmit(true, true, false, true);
        emit Borrow(_borrower2, 2_995.912459898389633881 * 1e18, 10 * 1e18);
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(_pool), _borrower2, 10 * 1e18);
        _pool.borrow(10 * 1e18, 3000);
    }

    /**
     *  @notice 1 lender, 2 borrowers tests reverts in repay.
     *          Reverts:
     *              Attempts to repay without quote tokens.
     *              Attempts to repay without debt.
     *              Attempts to repay when bucket would be left with amount less than averge debt.
     */
    function testScaledPoolRepayRequireChecks() external {
        // add initial quote to the pool
        changePrank(_lender);
        _pool.addQuoteToken(10_000 * 1e18, 2550);
        _pool.addQuoteToken(10_000 * 1e18, 2551);

        changePrank(_borrower);

        // should revert if borrower has no debt
        deal(address(_quote), _borrower,  _quote.balanceOf(_borrower) + 10_000 * 1e18);
        vm.expectRevert(IScaledPool.RepayNoDebt.selector);
        _pool.repay(_borrower, 10_000 * 1e18);

        // borrower 1 borrows 1000 quote from the pool
        _pool.pledgeCollateral(_borrower, 50 * 1e18);
        _pool.borrow(1_000 * 1e18, 3000);

        assertEq(_pool.maxBorrower(), _borrower);
        assertEq(_pool.loansCount(),  1);

        // borrower 2 borrows 5k quote from the pool and becomes new queue HEAD
        changePrank(_borrower2);
        _pool.pledgeCollateral(_borrower2, 50 * 1e18);
        _pool.borrow(5_000 * 1e18, 3000);

        assertEq(_pool.maxBorrower(), _borrower2);
        assertEq(_pool.loansCount(),  2);

        // should revert if amount left after repay is less than the average debt
        changePrank(_borrower);
        vm.expectRevert(IScaledPool.BorrowAmountLTMinDebt.selector);
        _pool.repay(_borrower, 750 * 1e18);

        // should be able to repay loan if properly specified
        vm.expectEmit(true, true, false, true);
        emit Repay(_borrower, _pool.lup(), 0.0001 * 1e18);
        vm.expectEmit(true, true, false, true);
        emit Transfer(_borrower, address(_pool), 0.0001 * 1e18);
        _pool.repay(_borrower, 0.0001 * 1e18);
    }

    function testRepayLoanFromDifferentActor() external {
        changePrank(_lender);
        _pool.addQuoteToken(10_000 * 1e18, 2550);
        _pool.addQuoteToken(10_000 * 1e18, 2551);

        // borrower 1 borrows 1000 quote from the pool
        changePrank(_borrower);
        _pool.pledgeCollateral(_borrower, 50 * 1e18);
        _pool.borrow(1_000 * 1e18, 3000);

        // should be able to repay loan on behalf of borrower
        changePrank(_lender);
        vm.expectEmit(true, true, false, true);
        emit Repay(_borrower, _pool.lup(), 0.0001 * 1e18);
        vm.expectEmit(true, true, false, true);
        emit Transfer(_lender, address(_pool), 0.0001 * 1e18);
        _pool.repay(_borrower, 0.0001 * 1e18);
    }

    /**
     *  @notice 1 lender, 1 borrower test significantly overcollateralized loans with 0 TP.
     *          Reverts:
     *              Attempts to borrow with a TP of 0.
     */
    function testZeroThresholdPriceLoan() external {
        // add initial quote to the pool
        changePrank(_lender);
        _pool.addQuoteToken(10_000 * 1e18, 2550);
        _pool.addQuoteToken(10_000 * 1e18, 2551);

        assertEq(_pool.htp(), 0);
        assertEq(_pool.maxBorrower(), address(0));
        assertEq(_pool.loansCount(),  0);

        // borrower 1 initiates a highly overcollateralized loan with a TP of 0 that won't be inserted into the Queue
        changePrank(_borrower);
        _pool.pledgeCollateral(_borrower, 50 * 1e18);
        vm.expectRevert("H:I:VAL_EQ_0");
        _pool.borrow(0.00000000000000001 * 1e18, 3000);

        // borrower 1 borrows 500 quote from the pool after using a non 0 TP
        _pool.pledgeCollateral(_borrower, 50 * 1e18);
        _pool.borrow(500 * 1e18, 3000);

        assertGt(_pool.htp(), 0);
        assertEq(_pool.maxBorrower(), _borrower);
        assertEq(_pool.loansCount(),  1);

    }

    /**
     *  @notice 1 lender, 1 borrower test repayment that would result in significant overcollateraization and 0 TP.
     *          Reverts:
     *              Attempts to repay with a subsequent TP of 0.
     */
    function testZeroThresholdPriceLoanAfterRepay() external {

        // add initial quote to the pool
        changePrank(_lender);
        _pool.addQuoteToken(10_000 * 1e18, 2550);
        _pool.addQuoteToken(10_000 * 1e18, 2551);

        assertEq(_pool.htp(), 0);

        // borrower 1 borrows 500 quote from the pool
        changePrank(_borrower);
        _pool.pledgeCollateral(_borrower, 50 * 1e18);
        _pool.borrow(500 * 1e18, 2551);

        assertGt(_pool.htp(), 0);
        assertEq(_pool.maxBorrower(), _borrower);
        assertEq(_pool.loansCount(),  1);

        (, uint256 pendingDebt, , ) = _pool.borrowerInfo(_borrower);
        deal(address(_quote), _borrower,  _quote.balanceOf(_borrower) + 10_000 * 1e18);

        // should revert if borrower repays most, but not all of their debt resulting in a 0 tp loan remaining on the book
        vm.expectRevert("H:I:VAL_EQ_0");
        _pool.repay(_borrower, pendingDebt - 1);

        // should be able to pay back all pendingDebt
        _pool.repay(_borrower, pendingDebt);
        assertEq(_pool.htp(), 0);
        assertEq(_pool.maxBorrower(), address(0));
        assertEq(_pool.loansCount(),  0);
    }

}
