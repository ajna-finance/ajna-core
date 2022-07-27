// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.14;

import { ScaledPool }        from "../../ScaledPool.sol";
import { ScaledPoolFactory } from "../../ScaledPoolFactory.sol";

import { BucketMath }        from "../../libraries/BucketMath.sol";

import { DSTestPlus }                             from "../utils/DSTestPlus.sol";
import { CollateralToken, QuoteToken }            from "../utils/Tokens.sol";
import { UserWithCollateralInScaledPool, UserWithQuoteTokenInScaledPool } from "../utils/Users.sol";

contract ScaledBorrowTest is DSTestPlus {

    uint256 public constant LARGEST_AMOUNT = type(uint256).max / 10**27;

    address                        internal _poolAddress;
    CollateralToken                internal _collateral;
    ScaledPool                     internal _pool;
    QuoteToken                     internal _quote;
    UserWithCollateralInScaledPool internal _borrower;
    UserWithCollateralInScaledPool internal _borrower2;
    UserWithQuoteTokenInScaledPool internal _lender;
    UserWithQuoteTokenInScaledPool internal _lender1;

    function setUp() external {
        _collateral  = new CollateralToken();
        _quote       = new QuoteToken();
        _poolAddress = new ScaledPoolFactory().deployPool(address(_collateral), address(_quote), 0.05 * 10**18);
        _pool        = ScaledPool(_poolAddress);

        _borrower   = new UserWithCollateralInScaledPool();
        _borrower2  = new UserWithCollateralInScaledPool();
        _lender     = new UserWithQuoteTokenInScaledPool();
        _lender1    = new UserWithQuoteTokenInScaledPool();

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

        assertEq(_pool.treeSum(),      50_000 * 1e18);
        assertEq(_pool.borrowerDebt(), 0);
        assertEq(_pool.lenderDebt(),   0);

        // check balances
        assertEq(_quote.balanceOf(address(_pool)),   50_000 * 1e18);
        assertEq(_quote.balanceOf(address(_lender)), 150_000 * 1e18);

        // borrower deposit 100 MKR collateral
        _borrower.addCollateral(_pool, 100 * 1e18, address(0), address(0), 1);
        assertEq(_pool.poolTargetUtilization(), 1 * 1e18);
        assertEq(_pool.poolActualUtilization(), 0);

        // get a 21_000 DAI loan
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(_pool), address(_borrower), 21_000 * 1e18);
        vm.expectEmit(true, true, false, true);
        emit Borrow(address(_borrower), 2_981.007422784467321543 * 1e18, 21_000 * 1e18);
        _borrower.borrow(_pool, 21_000 * 1e18, 3000, address(0), address(0), 1);

        assertEq(_pool.htp(), 210.201923076923077020 * 1e18);
        assertEq(_pool.lup(), 2_981.007422784467321543 * 1e18);

        assertEq(_pool.treeSum(),      50_000 * 1e18);
        assertEq(_pool.borrowerDebt(), 21_020.192307692307702000 * 1e18);
        assertEq(_pool.lenderDebt(),   21_000 * 1e18);
        assertEq(_pool.poolTargetUtilization(), 1 * 1e18);
        assertEq(_pool.poolActualUtilization(), 0.420403846153846154 * 1e18);

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
        _borrower.borrow(_pool, 19_000 * 1e18, 3500, address(0), address(0), 1);

        assertEq(_pool.htp(), 400.384615384615384800 * 1e18);
        assertEq(_pool.lup(), 2_966.176540084047110076 * 1e18);

        assertEq(_pool.treeSum(),      50_000 * 1e18);
        assertEq(_pool.borrowerDebt(), 40_038.461538461538480000 * 1e18);
        assertEq(_pool.lenderDebt(),   40_000 * 1e18);

        // check balances
        assertEq(_quote.balanceOf(address(_pool)),   10_000 * 1e18);
        assertEq(_quote.balanceOf(address(_lender)), 150_000 * 1e18);

        // repay partial
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(_borrower), address(_pool), 10_000 * 1e18);
        vm.expectEmit(true, true, false, true);
        emit Repay(address(_borrower), 2_966.176540084047110076 * 1e18, 10_000 * 1e18);
        _borrower.repay(_pool, 10_000 * 1e18, address(0), address(0), 1);

        assertEq(_pool.htp(), 300.384615384615384800 * 1e18);
        assertEq(_pool.lup(), 2_966.176540084047110076 * 1e18);

        assertEq(_pool.treeSum(),      50_000 * 1e18);
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
        _borrower.repay(_pool, 30_040 * 1e18, address(0), address(0), 1);

        assertEq(_pool.htp(), 0);
        assertEq(_pool.lup(), BucketMath.MAX_PRICE);

        assertEq(_pool.treeSum(),      50_000 * 1e18);
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

        _borrower.addCollateral(_pool, 50 * 1e18, address(0), address(0), 1);
        _borrower.borrow(_pool, 21_000 * 1e18, 3000, address(0), address(0), 1);

        assertEq(_pool.borrowerDebt(), 21_020.192307692307702000 * 1e18);
        (uint256 debt, uint256 pendingDebt, uint256 col, uint256 inflator) = _pool.borrowerInfo(address(_borrower));
        assertEq(debt,        21_020.192307692307702000 * 1e18);
        assertEq(pendingDebt, 21_051.890446205859712111 * 1e18);
        assertEq(col,         50 * 1e18);
        assertEq(inflator,    1 * 1e18);

        skip(864000);
        _borrower.addCollateral(_pool, 10 * 1e18, address(0), address(0), 1);
        assertEq(_pool.borrowerDebt(), 21_083.636385042573188669 * 1e18);
        (debt, pendingDebt, col, inflator) = _pool.borrowerInfo(address(_borrower));
        assertEq(debt,        21_083.636385042573188669 * 1e18);
        assertEq(pendingDebt, 21_083.636385042573188669 * 1e18);
        assertEq(col,         60 * 1e18);
        assertEq(inflator,    1.003018244382428805 * 1e18);

        skip(864000);
        _borrower.removeCollateral(_pool, 10 * 1e18, address(0), address(0), 1);
        assertEq(_pool.borrowerDebt(), 21_118.612213172841725096 * 1e18);
        (debt, pendingDebt, col, inflator) = _pool.borrowerInfo(address(_borrower));
        assertEq(debt,        21_118.612213172841725096 * 1e18);
        assertEq(pendingDebt, 21_118.612213172841725096 * 1e18);
        assertEq(col,         50 * 1e18);
        assertEq(inflator,    1.004682160088731320 * 1e18);

        skip(864000);
        _borrower.borrow(_pool, 0, 3000, address(0), address(0), 1);
        assertEq(_pool.borrowerDebt(), 21_157.152642868828624051 * 1e18);
        (debt, pendingDebt, col, inflator) = _pool.borrowerInfo(address(_borrower));
        assertEq(debt,        21_157.152642868828624051 * 1e18);
        assertEq(pendingDebt, 21_157.152642868828624051 * 1e18);
        assertEq(col,         50 * 1e18);
        assertEq(inflator,    1.006515655669163431 * 1e18);

        skip(864000);
        _borrower.repay(_pool, 0, address(0), address(0), 1);
        assertEq(_pool.borrowerDebt(), 21_199.628356700342110209 * 1e18);
        (debt, pendingDebt, col, inflator) = _pool.borrowerInfo(address(_borrower));
        assertEq(debt,        21_199.628356700342110209 * 1e18);
        assertEq(pendingDebt, 21_199.628356700342110209 * 1e18);
        assertEq(col,         50 * 1e18);
        assertEq(inflator,    1.008536365718327423 * 1e18);

        skip(864000);
        (debt, pendingDebt, col, inflator) = _pool.borrowerInfo(address(_borrower));
        assertEq(debt,        21_199.628356700342110209 * 1e18);
        assertEq(pendingDebt, 21_246.450141674447660998 * 1e18);
        assertEq(col,         50 * 1e18);
        assertEq(inflator,    1.008536365718327423 * 1e18);
    }

}
