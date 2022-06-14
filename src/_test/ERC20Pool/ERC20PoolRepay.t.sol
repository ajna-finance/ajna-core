// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.11;

import { ERC20Pool }        from "../../ERC20Pool.sol";
import { ERC20PoolFactory } from "../../ERC20PoolFactory.sol";

import { IPool } from "../../interfaces/IPool.sol";

import { Maths } from "../../libraries/Maths.sol";

import { DSTestPlus }                             from "../utils/DSTestPlus.sol";
import { CollateralToken, QuoteToken }            from "../utils/Tokens.sol";
import { UserWithCollateral, UserWithQuoteToken } from "../utils/Users.sol";

contract ERC20PoolRepayTest is DSTestPlus {

    address            internal _poolAddress;
    CollateralToken    internal _collateral;
    ERC20Pool          internal _pool;
    QuoteToken         internal _quote;
    UserWithCollateral internal _borrower;
    UserWithCollateral internal _borrower2;
    UserWithQuoteToken internal _lender;

    function setUp() external {
        _collateral  = new CollateralToken();
        _quote       = new QuoteToken();
        _poolAddress = new ERC20PoolFactory().deployPool(address(_collateral), address(_quote));
        _pool        = ERC20Pool(_poolAddress);

        _borrower   = new UserWithCollateral();
        _borrower2  = new UserWithCollateral();
        _lender     = new UserWithQuoteToken();

        _collateral.mint(address(_borrower), 100 * 1e18);
        _collateral.mint(address(_borrower2), 100 * 1e18);
        _quote.mint(address(_lender), 200_000 * 1e18);

        _borrower.approveToken(_collateral, address(_pool), 100 * 1e18);
        _borrower2.approveToken(_collateral, address(_pool), 100 * 1e18);
        _lender.approveToken(_quote, address(_pool), 200_000 * 1e18);
    }

    /**
     *  @notice 1 lender 1 borrower deposits quote token, borrows, partially repay then overpay purposefully.
     */
    function testOverRepayOneBorrower() external {
        uint256 priceHigh = _p5007;
        uint256 priceMid  = _p4000;
        uint256 priceLow  = _p3010;

        // lender deposits 10000 DAI in 3 buckets each
        _lender.addQuoteToken(_pool, address(_lender), 10_000 * 1e18, priceHigh);
        skip(14);

        _lender.addQuoteToken(_pool, address(_lender), 10_000 * 1e18, priceMid);
        skip(14);

        _lender.addQuoteToken(_pool, address(_lender), 10_000 * 1e18, priceLow);

        // borrower starts with 10_000 DAI and deposit 100 collateral
        _quote.mint(address(_borrower), 10_000 * 1e18);
        _borrower.approveToken(_quote, address(_pool), 100_000 * 1e18);
        _borrower.addCollateral(_pool, 100 * 1e18);

        assertEq(_pool.hpb(), priceHigh);
        assertEq(_pool.lup(), 0);

        assertEq(_pool.totalDebt(),       0);
        assertEq(_pool.totalQuoteToken(), 30_000 * 1e18);
        assertEq(_pool.totalCollateral(), 100 * 1e18);
        assertEq(_pool.pdAccumulator(),   120_194_640.856836005674960000 * 1e18);

        assertEq(_pool.getPoolCollateralization(), Maths.ONE_WAD);
        assertEq(_pool.getPoolActualUtilization(), 0);
        assertEq(_pool.getPendingPoolInterest(),   0);

        // check balances
        assertEq(_collateral.balanceOf(address(_borrower)), 0);
        assertEq(_collateral.balanceOf(address(_pool)),     100 * 1e18);

        // borrower takes loan of 25_000 DAI from 3 buckets
        _borrower.borrow(_pool, 25_000 * 1e18, 2_500 * 1e18);

        assertEq(_pool.hpb(), priceHigh);
        assertEq(_pool.lup(), priceLow);

        assertEq(_pool.totalDebt(),       25_000.000961538461538462 * 1e18);
        assertEq(_pool.totalQuoteToken(), 5_000 * 1e18);
        assertEq(_pool.totalCollateral(), 100 * 1e18);
        assertEq(_pool.pdAccumulator(),   15_054_460.110989407789225000 * 1e18);

        assertEq(_pool.getPoolCollateralization(), 12.043567625577386786 * 1e18);
        assertEq(_pool.getPoolActualUtilization(), 0.833333338675213504 * 1e18);
        assertEq(_pool.getPendingPoolInterest(),   0);

        assertEq(_pool.getEncumberedCollateral(_pool.totalDebt()), 8.303187486374565797557216819 * 1e27);

        // check balances
        assertEq(_quote.balanceOf(address(_borrower)), 35_000 * 1e18);
        assertEq(_quote.balanceOf(address(_pool)),     5_000 * 1e18);

        // check borrower
        (   uint256 borrowerDebt,
            uint256 borrowerPendingDebt,
            uint256 depositedCollateral,
            , , , ) = _pool.getBorrowerInfo(address(_borrower));
        assertEq(borrowerDebt,        25_000.000961538461538462 * 1e18);
        assertEq(borrowerPendingDebt, 25_000.000961538461538462 * 1e18);
        assertEq(depositedCollateral, 100 * 1e18);

        // repay partially debt w/ 10_000 DAI
        skip(8200);
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(_borrower), address(_pool), 10_000 * 1e18);
        vm.expectEmit(true, true, false, true);
        emit Repay(address(_borrower), priceMid, 10_000 * 1e18);
        _borrower.repay(_pool, 10_000 * 1e18);

        assertEq(_pool.hpb(), priceHigh);
        assertEq(_pool.lup(), priceMid);

        assertEq(_pool.totalDebt(),       15_000.325989031377467940 * 1e18);
        assertEq(_pool.totalQuoteToken(), 15_000 * 1e18);
        assertEq(_pool.totalCollateral(), 100 * 1e18);
        assertEq(_pool.pdAccumulator(),   50_113_493.305152931876960224 * 1e18);

        assertEq(_pool.getPoolCollateralization(), 26.672271532673012057 * 1e18);
        assertEq(_pool.getPoolActualUtilization(), 0.544955243212798984 * 1e18);
        assertEq(_pool.getPendingPoolInterest(),   0);

        assertEq(_pool.getEncumberedCollateral(_pool.totalDebt()), 3.749211981345569001524851620 * 1e27);

        // check balances
        assertEq(_quote.balanceOf(address(_borrower)), 25_000 * 1e18);
        assertEq(_quote.balanceOf(address(_pool)),     15_000 * 1e18);

        // check borrower debt
        (borrowerDebt, depositedCollateral, ) = _pool.borrowers(address(_borrower));
        assertEq(borrowerDebt,        15_000.325989031377467940 * 1e18);
        assertEq(borrowerDebt,        _pool.totalDebt());
        assertEq(depositedCollateral, 100 * 1e18);

        // overpay debt w/ repay 16_000 DAI
        skip(8200);
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(_borrower), address(_pool), 15_000.521009757842131923 * 1e18);
        vm.expectEmit(true, true, false, true);
        emit Repay(address(_borrower), 0, 15_000.521009757842131923 * 1e18);
        _borrower.repay(_pool, 16_000 * 1e18);

        assertEq(_pool.hpb(), priceHigh);
        assertEq(_pool.lup(), 0);

        assertEq(_pool.totalDebt(),       0);
        assertEq(_pool.totalQuoteToken(), 30_000.521009757842131923 * 1e18);
        assertEq(_pool.totalCollateral(), 100 * 1e18);
        assertEq(_pool.pdAccumulator(),   120_196_921.839645522983871485 * 1e18);

        assertEq(_pool.getPoolCollateralization(), Maths.ONE_WAD);
        assertEq(_pool.getPoolActualUtilization(), 0);
        assertEq(_pool.getPendingPoolInterest(),   0);

        assertEq(_pool.getEncumberedCollateral(_pool.totalDebt()), 0);

        // check balances
        assertEq(_quote.balanceOf(address(_borrower)), 9_999.478990242157868077 * 1e18);
        assertEq(_quote.balanceOf(address(_pool)),     30_000.521009757842131923 * 1e18);

        // check borrower debt
        (borrowerDebt, borrowerPendingDebt, depositedCollateral, , , , ) = _pool.getBorrowerInfo(address(_borrower));
        assertEq(borrowerDebt,        0);
        assertEq(depositedCollateral, 100 * 1e18);
        assertEq(borrowerPendingDebt, 0);
    }

    /**
     *  @notice 1 lender 2 borrowers deposits quote token, borrows, repays, withdraws collateral
     *          Borrower reverts:
     *              attempts to repay with no debt.
     *              attempts to repay with insufficent balance.
     */
    function testRepayTwoBorrower() external {
        uint256 priceHigh = _p5007;
        uint256 priceMid = _p4000;
        uint256 priceLow = _p3010;

        // lender deposits 10000 DAI in 3 buckets each
        _lender.addQuoteToken(_pool, address(_lender), 10_000 * 1e18, priceHigh);
        _lender.addQuoteToken(_pool, address(_lender), 10_000 * 1e18, priceMid);
        _lender.addQuoteToken(_pool, address(_lender), 10_600 * 1e18, priceLow);

        // borrower starts with 10_000 DAI and deposit 100 collateral
        _quote.mint(address(_borrower), 10_000 * 1e18);
        _borrower.approveToken(_quote, address(_pool), 100_000 * 1e18);
        _borrower.addCollateral(_pool, 100 * 1e18);

        // borrower2 starts with 10_000 DAI and deposit 100 collateral
        _quote.mint(address(_borrower2), 10_000 * 1e18);
        _borrower2.approveToken(_quote, address(_pool), 100_000 * 1e18);
        _borrower2.addCollateral(_pool, 100 * 1e18);

        assertEq(_pool.hpb(), priceHigh);
        assertEq(_pool.lup(), 0);

        assertEq(_pool.totalDebt(),       0);
        assertEq(_pool.totalQuoteToken(), 30_600 * 1e18);
        assertEq(_pool.totalCollateral(), 200 * 1e18);
        assertEq(_pool.pdAccumulator(),   122_001_176.070154734609667000 * 1e18);

        assertEq(_pool.getPoolCollateralization(), Maths.ONE_WAD);
        assertEq(_pool.getPoolActualUtilization(), 0);
        assertEq(_pool.getPendingPoolInterest(),   0);

        assertEq(_pool.getEncumberedCollateral(_pool.totalDebt()), 0);

        // check balances
        assertEq(_collateral.balanceOf(address(_borrower)),  0);
        assertEq(_collateral.balanceOf(address(_borrower2)), 0);
        assertEq(_collateral.balanceOf(address(_pool)),      200 * 1e18);

        // repay should revert if no debt
        vm.expectRevert("P:R:NO_DEBT");
        _borrower.repay(_pool, 10_000 * 1e18);

        // borrower takes loan of 25_000 DAI from 3 buckets
        _borrower.borrow(_pool, 25_000 * 1e18, 2_500 * 1e18);
        // borrower2 takes loan of 2_600 DAI from 3 buckets
        _borrower2.borrow(_pool, 2_600 * 1e18, 1 * 1e18);

        assertEq(_pool.hpb(), priceHigh);
        assertEq(_pool.lup(), priceLow);

        assertEq(_pool.totalDebt(),       27_600.001923076923076924 * 1e18);
        assertEq(_pool.totalQuoteToken(), 3_000 * 1e18);
        assertEq(_pool.totalCollateral(), 200 * 1e18);
        assertEq(_pool.pdAccumulator(),   9_032_676.066593644673535000 * 1e18);

        assertEq(_pool.getPoolCollateralization(), 21.818056611658519395 * 1e18);
        assertEq(_pool.getPoolActualUtilization(), 0.901960790475063444 * 1e18);
        assertEq(_pool.getPendingPoolInterest(),   0);

        assertEq(_pool.getEncumberedCollateral(_pool.totalDebt()), 9.166719271098124550157421829 * 1e27);

        // check balances
        assertEq(_quote.balanceOf(address(_borrower)),  35_000 * 1e18);
        assertEq(_quote.balanceOf(address(_borrower2)), 12_600.000000000000000000 * 1e18);
        assertEq(_quote.balanceOf(address(_pool)),      3_000 * 1e18);

        // check buckets
        (, , , uint256 deposit, uint256 debt, , , ) = _pool.bucketAt(priceHigh);
        assertEq(deposit, 0);
        assertEq(debt,    10_000 * 1e18);

        (, , , deposit, debt, , , ) = _pool.bucketAt(priceMid);
        assertEq(deposit, 0);
        assertEq(debt,    10_000 * 1e18);

        (, , , deposit, debt, , , ) = _pool.bucketAt(priceLow);
        assertEq(deposit, 3_000 * 1e18);
        assertEq(debt,    7_600.001923076923076924 * 1e18);

        // check borrower
        (   uint256 borrowerDebt,
            uint256 borrowerPendingDebt,
            uint256 depositedCollateral,
            , , , ) = _pool.getBorrowerInfo(address(_borrower));
        assertEq(borrowerDebt,        25_000.000961538461538462 * 1e18);
        assertEq(borrowerPendingDebt, 25_000.000961538461538462 * 1e18);
        assertEq(depositedCollateral, 100 * 1e18);

        // check borrower2
        (borrowerDebt, , depositedCollateral, , , ,) = _pool.getBorrowerInfo(address(_borrower2));
        assertEq(borrowerDebt,        2_600.000961538461538462 * 1e18);
        assertEq(depositedCollateral, 100 * 1e18);
        // repay should revert if amount not available
        vm.expectRevert("P:R:INSUF_BAL");
        _borrower.repay(_pool, 50_000 * 1e18);

        // repay debt partially 10_000 DAI
        skip(8200);
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(_borrower), address(_pool), 10_000 * 1e18);
        vm.expectEmit(true, true, false, true);
        emit Repay(address(_borrower), priceMid, 10_000 * 1e18);
        _borrower.repay(_pool, 10_000 * 1e18);

        assertEq(_pool.hpb(), priceHigh);
        assertEq(_pool.lup(), priceMid);

        assertEq(_pool.totalDebt(),       17_600.360753440303210085 * 1e18);
        assertEq(_pool.totalQuoteToken(), 13_000 * 1e18);
        assertEq(_pool.totalCollateral(), 200 * 1e18);
        assertEq(_pool.pdAccumulator(),   41_517_582.136157775661278731 * 1e18);

        assertEq(_pool.getPoolCollateralization(), 45.464155361685017044 * 1e18);
        assertEq(_pool.getPoolActualUtilization(), 0.629093211737283901 * 1e18);
        assertEq(_pool.getPendingPoolInterest(),   0);

        assertEq(_pool.getEncumberedCollateral(_pool.totalDebt()), 4.399069957616551047809769188 * 1e27);

        // check balances
        assertEq(_quote.balanceOf(address(_borrower)), 25_000 * 1e18);
        assertEq(_quote.balanceOf(address(_pool)),     13_000 * 1e18);

        // check buckets
        (, , , deposit, debt, , , ) = _pool.bucketAt(priceHigh);
        assertEq(deposit, 0);
        assertEq(debt,    10_000 * 1e18);

        (, , , deposit, debt, , , ) = _pool.bucketAt(priceMid);
        assertEq(deposit, 2_399.899268544028687947 * 1e18);
        assertEq(debt,    7_600.230742448137261068 * 1e18);

        (, , , deposit, debt, , , ) = _pool.bucketAt(priceLow);
        assertEq(deposit, 10_600.100731455971312053 * 1e18);
        assertEq(debt,    0);

        // check borrower debt
        (borrowerDebt, depositedCollateral, ) = _pool.borrowers(address(_borrower));
        assertEq(borrowerDebt,        15_000.325989031377467940 * 1e18);
        assertEq(depositedCollateral, 100 * 1e18);

        // borrower attempts to overpay to cover 15_000 DAI plus accumulated debt
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(_borrower), address(_pool), 15_000.325989031377467940 * 1e18);
        vm.expectEmit(true, true, false, true);
        emit Repay(address(_borrower), priceHigh, 15_000.325989031377467940 * 1e18);
        _borrower.repay(_pool, 15_001 * 1e18);

        assertEq(_pool.hpb(), priceHigh);
        assertEq(_pool.lup(), priceHigh);

        assertEq(_pool.totalDebt(),       2_600.034764408925742145 * 1e18);
        assertEq(_pool.totalQuoteToken(), 28_000.325989031377467940 * 1e18);
        assertEq(_pool.totalCollateral(), 200 * 1e18);
        assertEq(_pool.pdAccumulator(),   108_982_601.086533329872145304 * 1e18);

        assertEq(_pool.getPoolCollateralization(), 385.198263765796636315 * 1e18);
        assertEq(_pool.getPoolActualUtilization(), 0.106719398530916665 * 1e18);
        assertEq(_pool.getPendingPoolInterest(),   0);

        assertEq(_pool.getEncumberedCollateral(_pool.totalDebt()), 0.519213139863998618191100060 * 1e27);

        // check balances
        assertEq(_quote.balanceOf(address(_borrower)), 9_999.674010968622532060 * 1e18);
        assertEq(_quote.balanceOf(address(_pool)),     28_000.325989031377467940 * 1e18);

        (borrowerDebt, borrowerPendingDebt, depositedCollateral, , , ,) = _pool.getBorrowerInfo(address(_borrower));

        assertEq(borrowerDebt,        0);
        assertEq(depositedCollateral, 100 * 1e18);
        assertEq(borrowerPendingDebt, 0);

        // determine pending debt across all buckets
        uint256 bucketPendingDebt = 0;
        (, , , , debt, , , ) = _pool.bucketAt(priceHigh);
        bucketPendingDebt += debt;
        bucketPendingDebt += _pool.getPendingBucketInterest(priceHigh);

        (, , , , debt, , , ) = _pool.bucketAt(priceMid);
        bucketPendingDebt += debt;
        bucketPendingDebt += _pool.getPendingBucketInterest(priceMid);

        (, , , , debt, , , ) = _pool.bucketAt(priceLow);
        bucketPendingDebt += debt;
        bucketPendingDebt += _pool.getPendingBucketInterest(priceLow);

        // first borrower repaid; tie out pending debt second borrower debt to reasonable percentage
        uint256 poolPendingDebt = _pool.totalDebt() + _pool.getPendingPoolInterest();
        (, borrowerPendingDebt, , , , , ) = _pool.getBorrowerInfo(address(_borrower2));

        assertEq(borrowerPendingDebt, poolPendingDebt);
        assertLt(wadPercentDifference(bucketPendingDebt, borrowerPendingDebt), 0.000000000000000001 * 1e18);
        assertLt(wadPercentDifference(bucketPendingDebt, poolPendingDebt),     0.000000000000000001 * 1e18);

        // borrower2 attempts to repay 2_000 DAI plus accumulated debt
        (borrowerDebt, depositedCollateral, ) = _pool.borrowers(address(_borrower2));
        assertEq(borrowerDebt,        2_600.000961538461538462 * 1e18);
        assertEq(depositedCollateral, 100 * 1e18);

        // repay entire debt
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(_borrower2), address(_pool), 2_600.034764408925742145 * 1e18);
        vm.expectEmit(true, true, false, true);
        emit Repay(address(_borrower2), 0, 2_600.034764408925742145 * 1e18);
        _borrower2.repay(_pool, 2_700 * 1e18);

        assertEq(_pool.hpb(), priceHigh);
        assertEq(_pool.lup(), 0);

        assertEq(_pool.totalDebt(),       0);
        assertEq(_pool.totalQuoteToken(), 30_600.360753440303210085 * 1e18);
        assertEq(_pool.totalCollateral(), 200 * 1e18);
        assertEq(_pool.pdAccumulator(),   122_002_650.575083875239252452 * 1e18);

        assertEq(_pool.getPoolCollateralization(), Maths.ONE_WAD);
        assertEq(_pool.getPoolActualUtilization(), 0);
        assertEq(_pool.getPendingPoolInterest(),   0);

        assertEq(_pool.getEncumberedCollateral(_pool.totalDebt()), 0);

        // check balances
        assertEq(_quote.balanceOf(address(_borrower2)), 9_999.965235591074257855 * 1e18);
        assertEq(_quote.balanceOf(address(_pool)),      30_600.360753440303210085 * 1e18);

        (, , , deposit, debt, , , ) = _pool.bucketAt(priceHigh);
        assertEq(deposit, 10_000.130010992165949015 * 1e18);
        assertEq(debt,    0);

        assertEq(_pool.getPendingBucketInterest(priceHigh), 0);

        (, , , deposit, debt, , , ) = _pool.bucketAt(priceMid);
        assertEq(deposit, 10_000.130010992165949015 * 1e18);
        assertEq(debt,    0);

        assertEq(_pool.getPendingBucketInterest(priceMid), 0);

        (, , , deposit, debt, , , ) = _pool.bucketAt(priceLow);
        assertEq(deposit, 10_600.100731455971312053 * 1e18);
        assertEq(debt,    0);

        assertEq(_pool.getPendingBucketInterest(priceLow), 0);

        (borrowerDebt, depositedCollateral, ) = _pool.borrowers(address(_borrower2));
        assertEq(borrowerDebt, 0);

        (, borrowerPendingDebt, , , , , ) = _pool.getBorrowerInfo(address(_borrower2));
        assertEq(borrowerPendingDebt, 0);
        assertEq(depositedCollateral, 100 * 1e18);

        // remove deposited collateral
        _borrower.removeCollateral(_pool, 100 * 1e18);
        assertEq(_collateral.balanceOf(address(_borrower)), 100 * 1e18);

        _borrower2.removeCollateral(_pool, 100 * 1e18);
        assertEq(_collateral.balanceOf(address(_borrower2)), 100 * 1e18);
    }

}
