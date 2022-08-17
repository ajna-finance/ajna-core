// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.14;

import { ERC20Pool }        from "../../erc20/ERC20Pool.sol";
import { ERC20PoolFactory } from "../../erc20/ERC20PoolFactory.sol";

import { BucketMath } from "../../libraries/BucketMath.sol";

import { DSTestPlus }                             from "../utils/DSTestPlus.sol";
import { CollateralToken, QuoteToken }            from "../utils/Tokens.sol";
import { UserWithCollateral, UserWithQuoteToken } from "../utils/Users.sol";

contract ERC20ScaledBorrowTest is DSTestPlus {

    uint256 public constant LARGEST_AMOUNT = type(uint256).max / 10**27;

    address            internal _poolAddress;
    CollateralToken    internal _collateral;
    ERC20Pool          internal _pool;
    QuoteToken         internal _quote;
    UserWithCollateral internal _borrower;
    UserWithCollateral internal _borrower2;
    UserWithQuoteToken internal _lender;
    UserWithQuoteToken internal _lender1;

    function setUp() external {
        _collateral  = new CollateralToken();
        _quote       = new QuoteToken();
        _poolAddress = new ERC20PoolFactory().deployPool(address(_collateral), address(_quote), 0.05 * 10**18);
        _pool        = ERC20Pool(_poolAddress);

        _borrower   = new UserWithCollateral();
        _borrower2  = new UserWithCollateral();
        _lender     = new UserWithQuoteToken();
        _lender1    = new UserWithQuoteToken();

        _collateral.mint(address(_borrower), 100 * 1e18);
        _collateral.mint(address(_borrower2), 200 * 1e18);

        _quote.mint(address(_lender), 200_000 * 1e18);
        _quote.mint(address(_lender1), 200_000 * 1e18);

        _borrower.approveToken(_collateral, address(_pool), 100 * 1e18);
        _borrower.approveToken(_quote,      address(_pool), 200_000 * 1e18);

        _borrower2.approveToken(_collateral, address(_pool), 200 * 1e18);
        _borrower2.approveToken(_quote,      address(_pool), 200_000 * 1e18);

        _lender.approveToken(_quote,  address(_pool), 200_000 * 1e18);
        _lender1.approveToken(_quote, address(_pool), 200_000 * 1e18);
    }

    function testScaledPoolBorrowAndRepay() external {
        // TODO: these are indexes, not prices; rename to avoid confusion
        uint256 depositPriceHighest = 2550;
        uint256 depositPriceHigh    = 2551;
        uint256 depositPriceMed     = 2552;
        uint256 depositPriceLow     = 2553;
        uint256 depositPriceLowest  = 2554;

        // lender deposits 10000 DAI in 5 buckets each
        _lender.addQuoteToken(_pool, 10_000 * 1e18, depositPriceHighest);
        _lender.addQuoteToken(_pool, 10_000 * 1e18, depositPriceHigh);
        _lender.addQuoteToken(_pool, 10_000 * 1e18, depositPriceMed);
        _lender.addQuoteToken(_pool, 10_000 * 1e18, depositPriceLow);
        _lender.addQuoteToken(_pool, 10_000 * 1e18, depositPriceLowest);

        assertEq(_pool.htp(), 0);
        assertEq(_pool.lup(), BucketMath.MAX_PRICE);

        assertEq(_pool.poolSize(),              50_000 * 1e18);
        assertEq(_pool.borrowerDebt(),          0);
        assertEq(_pool.lenderDebt(),            0);
        assertEq(_pool.poolActualUtilization(), 0);
        assertEq(_pool.poolMinDebtAmount(),     0);

        // check balances
        assertEq(_quote.balanceOf(address(_pool)),   50_000 * 1e18);
        assertEq(_quote.balanceOf(address(_lender)), 150_000 * 1e18);

        // borrower deposit 100 MKR collateral
        _borrower.pledgeCollateral(_pool, 100 * 1e18, address(0), address(0));
        assertEq(_pool.poolTargetUtilization(), 1 * 1e18);
        assertEq(_pool.poolActualUtilization(), 0);

        // get a 21_000 DAI loan
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(_pool), address(_borrower), 21_000 * 1e18);
        vm.expectEmit(true, true, false, true);
        emit Borrow(address(_borrower), 2_981.007422784467321543 * 1e18, 21_000 * 1e18);
        _borrower.borrow(_pool, 21_000 * 1e18, 3000, address(0), address(0));

        assertEq(_pool.htp(), 210.201923076923077020 * 1e18);
        assertEq(_pool.lup(), 2_981.007422784467321543 * 1e18);

        assertEq(_pool.poolSize(),     50_000 * 1e18);
        assertEq(_pool.borrowerDebt(), 21_020.192307692307702000 * 1e18);
        assertEq(_pool.lenderDebt(),   21_000 * 1e18);
        assertEq(_pool.poolTargetUtilization(), 1 * 1e18);
        assertEq(_pool.poolActualUtilization(), 0.420403846153846154 * 1e18);
        assertEq(_pool.poolMinDebtAmount(),     2_102.0192307692307702 * 1e18);

        // check balances
        assertEq(_quote.balanceOf(address(_pool)),   29_000 * 1e18);
        assertEq(_quote.balanceOf(address(_lender)), 150_000 * 1e18);

        // check LPs
        assertEq(_pool.lpBalance(depositPriceHighest, address(_lender)), 10_000 * 1e27);
        assertEq(_pool.lpBalance(depositPriceHigh, address(_lender)),    10_000 * 1e27);
        assertEq(_pool.lpBalance(depositPriceMed, address(_lender)),     10_000 * 1e27);
        assertEq(_pool.lpBalance(depositPriceLow, address(_lender)),     10_000 * 1e27);
        assertEq(_pool.lpBalance(depositPriceLowest, address(_lender)),  10_000 * 1e27);

        // check buckets
        (uint256 lpAccumulator, uint256 availableCollateral) = _pool.buckets(depositPriceHighest);
        assertEq(lpAccumulator,       10_000 * 1e27);
        assertEq(availableCollateral, 0);
        (lpAccumulator, availableCollateral) = _pool.buckets(depositPriceHigh);
        assertEq(lpAccumulator,       10_000 * 1e27);
        assertEq(availableCollateral, 0);
        (lpAccumulator, availableCollateral) = _pool.buckets(depositPriceMed);
        assertEq(lpAccumulator,       10_000 * 1e27);
        assertEq(availableCollateral, 0);
        (lpAccumulator, availableCollateral) = _pool.buckets(depositPriceLow);
        assertEq(lpAccumulator,       10_000 * 1e27);
        assertEq(availableCollateral, 0);
        (lpAccumulator, availableCollateral) = _pool.buckets(depositPriceLowest);
        assertEq(lpAccumulator,       10_000 * 1e27);
        assertEq(availableCollateral, 0);

        // borrow 19_000 DAI
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(_pool), address(_borrower), 19_000 * 1e18);
        vm.expectEmit(true, true, false, true);
        emit Borrow(address(_borrower), 2_966.176540084047110076 * 1e18, 19_000 * 1e18);
        _borrower.borrow(_pool, 19_000 * 1e18, 3500, address(0), address(0));

        assertEq(_pool.htp(), 400.384615384615384800 * 1e18);
        assertEq(_pool.lup(), 2_966.176540084047110076 * 1e18);

        assertEq(_pool.poolSize(),          50_000 * 1e18);
        assertEq(_pool.borrowerDebt(),      40_038.461538461538480000 * 1e18);
        assertEq(_pool.lenderDebt(),        40_000 * 1e18);
        assertEq(_pool.poolMinDebtAmount(), 4_003.846153846153848 * 1e18);

        // check balances
        assertEq(_quote.balanceOf(address(_pool)),   10_000 * 1e18);
        assertEq(_quote.balanceOf(address(_lender)), 150_000 * 1e18);

        // repay partial
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(_borrower), address(_pool), 10_000 * 1e18);
        vm.expectEmit(true, true, false, true);
        emit Repay(address(_borrower), 2_966.176540084047110076 * 1e18, 10_000 * 1e18);
        _borrower.repay(_pool, 10_000 * 1e18, address(0), address(0));

        assertEq(_pool.htp(), 300.384615384615384800 * 1e18);
        assertEq(_pool.lup(), 2_966.176540084047110076 * 1e18);

        assertEq(_pool.poolSize(),     50_000 * 1e18);
        assertEq(_pool.borrowerDebt(), 30_038.461538461538480000 * 1e18);
        assertEq(_pool.lenderDebt(),   30_009.606147934678200000 * 1e18);

        // check balances
        assertEq(_quote.balanceOf(address(_pool)),   20_000 * 1e18);
        assertEq(_quote.balanceOf(address(_lender)), 150_000 * 1e18);

        // repay entire loan
        _quote.mint(address(_borrower), 40 * 1e18);
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(_borrower), address(_pool), 30_038.461538461538480000 * 1e18);
        vm.expectEmit(true, true, false, true);
        emit Repay(address(_borrower), BucketMath.MAX_PRICE, 30_038.461538461538480000 * 1e18);
        _borrower.repay(_pool, 30_040 * 1e18, address(0), address(0));

        assertEq(_pool.htp(), 0);
        assertEq(_pool.lup(), BucketMath.MAX_PRICE);

        assertEq(_pool.poolSize(),     50_000 * 1e18);
        assertEq(_pool.borrowerDebt(), 0);
        assertEq(_pool.lenderDebt(),   0);

        // check balances
        assertEq(_quote.balanceOf(address(_pool)),   50_038.461538461538480000 * 1e18);
        assertEq(_quote.balanceOf(address(_lender)), 150_000 * 1e18);
    }

    function testScaledPoolBorrowerInterestAccumulation() external {
        uint256 depositPriceHighest = 2550;
        uint256 depositPriceHigh    = 2551;
        uint256 depositPriceMed     = 2552;
        uint256 depositPriceLow     = 2553;
        uint256 depositPriceLowest  = 2554;

        // lender deposits 10000 DAI in 5 buckets each
        _lender.addQuoteToken(_pool, 10_000 * 1e18, depositPriceHighest);
        _lender.addQuoteToken(_pool, 10_000 * 1e18, depositPriceHigh);
        _lender.addQuoteToken(_pool, 10_000 * 1e18, depositPriceMed);
        _lender.addQuoteToken(_pool, 10_000 * 1e18, depositPriceLow);
        _lender.addQuoteToken(_pool, 10_000 * 1e18, depositPriceLowest);

        skip(864000);

        _borrower.pledgeCollateral(_pool, 50 * 1e18, address(0), address(0));
        _borrower.borrow(_pool, 21_000 * 1e18, 3000, address(0), address(0));

        assertEq(_pool.borrowerDebt(), 21_020.192307692307702000 * 1e18);
        (uint256 debt, uint256 pendingDebt, uint256 col, uint256 inflator) = _pool.borrowerInfo(address(_borrower));
        assertEq(debt,        21_020.192307692307702000 * 1e18);
        assertEq(pendingDebt, 21_051.890446233188505554 * 1e18);
        assertEq(col,         50 * 1e18);
        assertEq(inflator,    1 * 1e18);

        skip(864000);
        _borrower.pledgeCollateral(_pool, 10 * 1e18, address(0), address(0));
        assertEq(_pool.borrowerDebt(), 21_083.636385097313216749 * 1e18);
        (debt, pendingDebt, col, inflator) = _pool.borrowerInfo(address(_borrower));
        assertEq(debt,        21_083.636385097313216749 * 1e18);
        assertEq(pendingDebt, 21_083.636385097313216749 * 1e18);
        assertEq(col,         60 * 1e18);
        assertEq(inflator,    1.003018244385032969 * 1e18);

        skip(864000);
        _borrower.pullCollateral(_pool, 10 * 1e18, address(0), address(0));
        assertEq(_pool.borrowerDebt(), 21_118.612213256345042351 * 1e18);
        (debt, pendingDebt, col, inflator) = _pool.borrowerInfo(address(_borrower));
        assertEq(debt,        21_118.612213256345042351 * 1e18);
        assertEq(pendingDebt, 21_118.612213256345042351 * 1e18);
        assertEq(col,         50 * 1e18);
        assertEq(inflator,    1.004682160092703849 * 1e18);

        skip(864000);
        _borrower.borrow(_pool, 0, 3000, address(0), address(0));
        assertEq(_pool.borrowerDebt(), 21_157.152642997118010824 * 1e18);
        (debt, pendingDebt, col, inflator) = _pool.borrowerInfo(address(_borrower));
        assertEq(debt,        21_157.152642997118010824 * 1e18);
        assertEq(pendingDebt, 21_157.152642997118010824 * 1e18);
        assertEq(col,         50 * 1e18);
        assertEq(inflator,    1.006515655675266581 * 1e18);

        skip(864000);
        _borrower.repay(_pool, 0, address(0), address(0));
        assertEq(_pool.borrowerDebt(), 21_199.628356880380570924 * 1e18);
        (debt, pendingDebt, col, inflator) = _pool.borrowerInfo(address(_borrower));
        assertEq(debt,        21_199.628356880380570924 * 1e18);
        assertEq(pendingDebt, 21_199.628356880380570924 * 1e18);
        assertEq(col,         50 * 1e18);
        assertEq(inflator,    1.008536365726892447 * 1e18);

        skip(864000);
        assertEq(_pool.borrowerDebt(), 21_199.628356880380570924 * 1e18);
        (debt, pendingDebt, col, inflator) = _pool.borrowerInfo(address(_borrower));
        assertEq(debt,        21_199.628356880380570924 * 1e18);
        assertEq(pendingDebt, 21_246.450141911768550258 * 1e18);
        assertEq(col,         50 * 1e18);
        assertEq(inflator,    1.008536365726892447 * 1e18);
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
        vm.expectRevert("S:B:LIMIT_REACHED");
        _borrower.borrow(_pool, 1_000 * 1e18, 5000, address(0), address(0));

        // add initial quote to the pool
        _lender.addQuoteToken(_pool, 10_000 * 1e18, 2550);
        _lender.addQuoteToken(_pool, 10_000 * 1e18, 2551);

        // should revert if borrow would result in pool under collateralization
        vm.expectRevert("S:B:PUNDER_COLLAT");
        _borrower.borrow(_pool, 500 * 1e18, 3000, address(0), address(0));

        // borrower 1 borrows 500 quote from the pool after adding sufficient collateral
        _borrower.pledgeCollateral(_pool, 50 * 1e18, address(0), address(0));
        _borrower.borrow(_pool, 500 * 1e18, 3000, address(0), address(0));

        // borrower 2 borrows 15k quote from the pool with borrower2 becoming new queue HEAD
        _borrower2.pledgeCollateral(_pool, 6 * 1e18, address(0), address(0));
        _borrower2.borrow(_pool, 15_000 * 1e18, 3000, address(0), address(0));

        // should revert if borrower attempts to borrow more than minimum amount
        vm.expectRevert("S:B:AMT_LT_AVG_DEBT");
        _borrower.borrow(_pool, 10 * 1e18, 3000, address(0), address(_borrower2));

        // should revert if borrow would result in borrower under collateralization
        assertEq(_pool.lup(), 2_995.912459898389633881 * 1e18);
        vm.expectRevert("S:B:BUNDER_COLLAT");
        _borrower2.borrow(_pool, 2_976 * 1e18, 3000, address(0), address(_borrower));

        // should be able to borrow if properly specified
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(_pool), address(_borrower2), 10 * 1e18);
        vm.expectEmit(true, true, false, true);
        emit Borrow(address(_borrower2), 2_995.912459898389633881 * 1e18, 10 * 1e18);
        _borrower2.borrow(_pool, 10 * 1e18, 3000, address(0), address(0));
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
        _lender.addQuoteToken(_pool, 10_000 * 1e18, 2550);
        _lender.addQuoteToken(_pool, 10_000 * 1e18, 2551);

        // should revert if borrower has insufficient quote to repay desired amount
        vm.expectRevert("S:R:INSUF_BAL");
        _borrower.repay(_pool, 10_000 * 1e18, address(0), address(0));

        // should revert if borrower has no debt
        _quote.mint(address(_borrower), 10_000 * 1e18);
        vm.expectRevert("S:R:NO_DEBT");
        _borrower.repay(_pool, 10_000 * 1e18, address(0), address(0));

        // borrower 1 borrows 1000 quote from the pool
        _borrower.pledgeCollateral(_pool, 50 * 1e18, address(0), address(0));
        _borrower.borrow(_pool, 1_000 * 1e18, 3000, address(0), address(0));

        assertEq(address(_borrower), _pool.loanQueueHead());

        // borrower 2 borrows 5k quote from the pool and becomes new queue HEAD
        _borrower2.pledgeCollateral(_pool, 50 * 1e18, address(0), address(_borrower));
        _borrower2.borrow(_pool, 5_000 * 1e18, 3000, address(0), address(0));

        assertEq(address(_borrower2), _pool.loanQueueHead());

        // should revert if amount left after repay is less than the average debt
        vm.expectRevert("R:B:AMT_LT_AVG_DEBT");
        _borrower.repay(_pool, 750 * 1e18, address(0), address(0));

        // should be able to repay loan if properly specified
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(_borrower), address(_pool), 0.0001 * 1e18);
        vm.expectEmit(true, true, false, true);
        emit Repay(address(_borrower), _pool.lup(), 0.0001 * 1e18);
        _borrower.repay(_pool, 0.0001 * 1e18, address(_borrower2), address(_borrower2));
    }

    /**
     *  @notice 1 lender, 1 borrower test significantly overcollateralized loans with 0 TP.
     *          Reverts:
     *              Attempts to borrow with a TP of 0.
     */
    function testZeroThresholdPriceLoan() external {
        // add initial quote to the pool
        _lender.addQuoteToken(_pool, 10_000 * 1e18, 2550);
        _lender.addQuoteToken(_pool, 10_000 * 1e18, 2551);

        assertEq(_pool.htp(), 0);
        assertEq(address(_pool.loanQueueHead()), address(0));

        // borrower 1 initiates a highly overcollateralized loan with a TP of 0 that won't be inserted into the Queue
        _borrower.pledgeCollateral(_pool, 50 * 1e18, address(0), address(0));
        vm.expectRevert("B:U:TP_EQ_0");
        _borrower.borrow(_pool, .00000000000000001 * 1e18, 3000, address(0), address(0));

        // borrower 1 borrows 500 quote from the pool after using a non 0 TP
        _borrower.pledgeCollateral(_pool, 50 * 1e18, address(0), address(0));
        _borrower.borrow(_pool, 500 * 1e18, 3000, address(0), address(0));

        assertGt(_pool.htp(), 0);
        assertEq(address(_pool.loanQueueHead()), address(_borrower));

    }

    /**
     *  @notice 1 lender, 1 borrower test repayment that would result in significant overcollateraization and 0 TP.
     *          Reverts:
     *              Attempts to repay with a subsequent TP of 0.
     */
    function testZeroThresholdPriceLoanAfterRepay() external {

        // add initial quote to the pool
        _lender.addQuoteToken(_pool, 10_000 * 1e18, 2550);
        _lender.addQuoteToken(_pool, 10_000 * 1e18, 2551);

        assertEq(_pool.htp(), 0);

        // borrower 1 borrows 500 quote from the pool
        _borrower.pledgeCollateral(_pool, 50 * 1e18, address(0), address(0));
        _borrower.borrow(_pool, 500 * 1e18, 2551, address(0), address(0));

        assertGt(_pool.htp(), 0);
        assertEq(address(_pool.loanQueueHead()), address(_borrower));

        (, uint256 pendingDebt, , ) = _pool.borrowerInfo(address(_borrower));
        _quote.mint(address(_borrower), 10_000 * 1e18);

        // should revert if borrower repays most, but not all of their debt resulting in a 0 tp loan remaining on the book
        vm.expectRevert("B:U:TP_EQ_0");
        _borrower.repay(_pool, pendingDebt - 1, address(0), address(0));

        // should be able to pay back all pendingDebt
        _borrower.repay(_pool, pendingDebt, address(0), address(0));
        assertEq(_pool.htp(), 0);
        assertEq(address(_pool.loanQueueHead()), address(0));
    }

}
