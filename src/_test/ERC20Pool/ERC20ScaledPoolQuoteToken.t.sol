// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.14;

import { ERC20Pool }        from "../../erc20/ERC20Pool.sol";
import { ERC20PoolFactory } from "../../erc20/ERC20PoolFactory.sol";

import { BucketMath } from "../../libraries/BucketMath.sol";
import { Maths }      from "../../libraries/Maths.sol";

import { DSTestPlus }                  from "../utils/DSTestPlus.sol";
import { CollateralToken, QuoteToken } from "../utils/Tokens.sol";

contract ERC20ScaledQuoteTokenTest is DSTestPlus {

    uint256 public constant LARGEST_AMOUNT = type(uint256).max / 10**27;

    address internal _borrower;
    address internal _borrower2;
    address internal _lender;
    address internal _lender1;

    CollateralToken internal _collateral;
    QuoteToken      internal _quote;
    ERC20Pool       internal _pool;

    function setUp() external {
        _collateral = new CollateralToken();
        _quote      = new QuoteToken();
        _pool       = ERC20Pool(new ERC20PoolFactory().deployPool(address(_collateral), address(_quote), 0.05 * 10**18));

        _borrower  = makeAddr("borrower");
        _borrower2 = makeAddr("borrower2");
        _lender    = makeAddr("lender");
        _lender1   = makeAddr("bidder");

        deal(address(_collateral), _borrower,  100 * 1e18);
        deal(address(_collateral), _borrower2, 200 * 1e18);

        deal(address(_quote), _lender,  200_000 * 1e18);
        deal(address(_quote), _lender1, 200_000 * 1e18);

        vm.startPrank(_borrower);
        _collateral.approve(address(_pool), 100 * 1e18);
        _quote.approve(address(_pool), 200_000 * 1e18);

        changePrank(_borrower2);
        _collateral.approve(address(_pool), 200 * 1e18);
        _quote.approve(address(_pool), 200_000 * 1e18);

        changePrank(_lender);
        _quote.approve(address(_pool), 200_000 * 1e18);

        changePrank(_lender1);
        _quote.approve(address(_pool), 200_000 * 1e18);
    }

    /**
     *  @notice 1 lender tests adding quote token.
     *          Lender reverts:
     *              attempts to addQuoteToken at invalid price.
     */
    function testScaledPoolDepositQuoteToken() external {

        // test 10_000 DAI deposit at price of 1 MKR = 3_010.892022197881557845 DAI
        changePrank(_lender);
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(_lender), address(_pool), 10_000 * 1e18);
        vm.expectEmit(true, true, false, true);
        emit AddQuoteToken(address(_lender), _p3010, 10_000 * 1e18, BucketMath.MAX_PRICE);
        _pool.addQuoteToken(10_000 * 1e18, 2550);

        assertEq(_pool.htp(), 0);
        assertEq(_pool.lup(), BucketMath.MAX_PRICE);

        (uint256 lpBalance, ) = _pool.bucketLenders(2550, address(_lender));
        assertEq(_pool.poolSize(),         10_000 * 1e18);
        assertEq(lpBalance,                10_000 * 1e27);
        assertEq(_pool.exchangeRate(2550), 1 * 1e27);

        // check balances
        assertEq(_quote.balanceOf(address(_pool)),   10_000 * 1e18);
        assertEq(_quote.balanceOf(address(_lender)), 190_000 * 1e18);

        // check bucket balance
        (uint256 lpAccumulator, uint256 availableCollateral) = _pool.buckets(2550);
        assertEq(lpAccumulator,       10_000 * 1e27);
        assertEq(availableCollateral, 0);

        // test 20_000 DAI deposit at price of 1 MKR = 2_995.912459898389633881 DAI
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(_lender), address(_pool), 20_000 * 1e18);
        vm.expectEmit(true, true, false, true);
        emit AddQuoteToken(address(_lender), 2_995.912459898389633881 * 1e18, 20_000 * 1e18, BucketMath.MAX_PRICE);
        _pool.addQuoteToken(20_000 * 1e18, 2551);

        assertEq(_pool.htp(), 0);
        assertEq(_pool.lup(), BucketMath.MAX_PRICE);

        (lpBalance, ) = _pool.bucketLenders(2551, address(_lender));
        assertEq(_pool.poolSize(), 30_000 * 1e18);
        assertEq(lpBalance,        20_000 * 1e27);

        // check balances
        assertEq(_quote.balanceOf(address(_pool)),   30_000 * 1e18);
        assertEq(_quote.balanceOf(address(_lender)), 170_000 * 1e18);

        // check bucket balance
        (lpAccumulator, availableCollateral) = _pool.buckets(2551);
        assertEq(lpAccumulator,       20_000 * 1e27);
        assertEq(availableCollateral, 0);

        // test 40_000 DAI deposit at price of 1 MKR = 3_025.946482308870940904 DAI
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(_lender), address(_pool), 40_000 * 1e18);
        vm.expectEmit(true, true, false, true);
        emit AddQuoteToken(address(_lender), 3_025.946482308870940904 * 1e18, 40_000 * 1e18, BucketMath.MAX_PRICE);
        _pool.addQuoteToken(40_000 * 1e18, 2549);

        assertEq(_pool.htp(), 0);
        assertEq(_pool.lup(), BucketMath.MAX_PRICE);

        (lpBalance, ) = _pool.bucketLenders(2549, address(_lender));
        assertEq(_pool.poolSize(), 70_000 * 1e18);
        assertEq(lpBalance,        40_000 * 1e27);

        // check balances
        assertEq(_quote.balanceOf(address(_pool)),   70_000 * 1e18);
        assertEq(_quote.balanceOf(address(_lender)), 130_000 * 1e18);

        // check bucket balance
        (lpAccumulator, availableCollateral) = _pool.buckets(2549);
        assertEq(lpAccumulator,       40_000 * 1e27);
        assertEq(availableCollateral, 0);
    }

    function testScaledPoolRemoveQuoteToken() external {
        assertEq(_quote.balanceOf(address(_pool)),   0);
        assertEq(_quote.balanceOf(address(_lender)), 200_000 * 1e18);

        changePrank(_lender);
        _pool.addQuoteToken(40_000 * 1e18, 2549);
        _pool.addQuoteToken(10_000 * 1e18, 2550);
        _pool.addQuoteToken(20_000 * 1e18, 2551);

        (uint256 lpBalance, ) = _pool.bucketLenders(2549, address(_lender));
        assertEq(lpBalance, 40_000 * 1e27);

        assertEq(_quote.balanceOf(address(_pool)),   70_000 * 1e18);
        assertEq(_quote.balanceOf(address(_lender)), 130_000 * 1e18);

        vm.expectEmit(true, true, false, true);
        emit RemoveQuoteToken(address(_lender), 3_025.946482308870940904 * 1e18, 5_000 * 1e18, BucketMath.MAX_PRICE);
        uint256 lpRedeemed = _pool.removeQuoteToken(5_000 * 1e18, 2549);
        assertEq(lpRedeemed, 5_000 * 1e27);

        (lpBalance, ) = _pool.bucketLenders(2549, address(_lender));
        assertEq(lpBalance, 35_000 * 1e27);

        assertEq(_quote.balanceOf(address(_pool)),   65_000 * 1e18);
        assertEq(_quote.balanceOf(address(_lender)), 135_000 * 1e18);

        vm.expectEmit(true, true, false, true);
        emit RemoveQuoteToken(address(_lender), 3_025.946482308870940904 * 1e18, 35_000 * 1e18, BucketMath.MAX_PRICE);
        uint256 removed;
        (removed, lpRedeemed) = _pool.removeAllQuoteToken(2549);
        assertEq(removed, 35_000 * 1e18);
        assertEq(lpRedeemed, 35_000 * 1e27);
    }

    /**
     *  @notice 1 lender tests reverts in removeQuoteToken.
     *          Reverts:
     *              Attempts to remove more quote tokens than available from lpBalance.
     *              Attempts to remove quote token when doing so would drive lup below htp.
     */
    function testScaledPoolRemoveQuoteTokenRequireChecks() external {
        // lender adds initial quote token
        changePrank(_lender);
        _pool.addQuoteToken(40_000 * 1e18, 4549);
        _pool.addQuoteToken(10_000 * 1e18, 4550);
        _pool.addQuoteToken(20_000 * 1e18, 4551);

        // add collateral and borrow all available quote in the higher priced original 3 buckets
        _pool.addQuoteToken(30_000 * 1e18, 4990);

        changePrank(_borrower);
        deal(address(_collateral), _borrower,  _collateral.balanceOf(_borrower) + 3_500_000 * 1e18);
        _collateral.approve(address(_pool), 3_500_000 * 1e18);
        _pool.pledgeCollateral(3_500_000 * 1e18, address(0), address(0));
        _pool.borrow(70_000 * 1e18, 4551, address(0), address(0));

        // ensure lender cannot withdraw from a bucket with no deposit
        changePrank(_lender1);
        vm.expectRevert("S:RAQT:NO_QT");
        _pool.removeAllQuoteToken(1776);
        // ensure lender with no LP cannot remove anything
        (uint256 lpBalance, ) = _pool.bucketLenders(4550, address(_lender1));
        assertEq(0, lpBalance);
        vm.expectRevert("S:RAQT:NO_CLAIM");
        _pool.removeAllQuoteToken(4550);

        // should revert if insufficient quote token
        changePrank(_lender);
        vm.expectRevert("S:RQT:INSUF_QT");
        _pool.removeQuoteToken(20_000 * 1e18, 4550);

        // should revert if removing quote token from higher price buckets would drive lup below htp
        vm.expectRevert("S:RQT:BAD_LUP");
        _pool.removeQuoteToken(20_000 * 1e18, 4551);

        // should revert if bucket has enough quote token, but lender has insufficient LP
        changePrank(_lender1);
        _pool.addQuoteToken(20_000 * 1e18, 4550);
        changePrank(_lender);
        vm.expectRevert("S:RQT:INSUF_LPS");
        _pool.removeQuoteToken(15_000 * 1e18, 4550);

        // should be able to removeQuoteToken if quote tokens haven't been encumbered by a borrower
        emit RemoveQuoteToken(address(_lender), _pool.indexToPrice(4990), 10_000 * 1e18, _pool.indexToPrice(4551));
        _pool.removeQuoteToken(10_000 * 1e18, 4990);
    }

    function testScaledPoolRemoveQuoteTokenWithDebt() external {
        // lender adds initial quote token
        skip(60);  // prevent deposit from having a zero timestamp
        changePrank(_lender);
        _pool.addQuoteToken(3_400 * 1e18, 1606);
        _pool.addQuoteToken(3_400 * 1e18, 1663);
        (uint256 lpBalance, uint256 lastQuoteDeposit) = _pool.bucketLenders(1606, address(_lender));
        uint256 lpb_before = lpBalance;
        assertEq(lastQuoteDeposit, 60);
        uint256 exchangeRateBefore = _pool.exchangeRate(1606);
        skip(3540);
        (lpBalance, ) = _pool.bucketLenders(1606, address(_lender));
        assertEq(lpb_before, lpBalance);
        assertEq(exchangeRateBefore, _pool.exchangeRate(1606));
        uint256 lenderBalanceBefore = _quote.balanceOf(address(_lender));

        // borrower takes a loan of 3000 quote token
        changePrank(_borrower);
        deal(address(_collateral), _borrower, _collateral.balanceOf(_borrower) + 100 * 1e18);
        _collateral.approve(address(_pool), 100 * 1e18);
        _pool.pledgeCollateral(100 * 1e18, address(0), address(0));
        uint256 limitPrice = _pool.priceToIndex(4_000 * 1e18);
        assertGt(limitPrice, 1663);
        _pool.borrow(3_000 * 1e18, limitPrice, address(0), address(0));
        skip(7200);
        (lpBalance, lastQuoteDeposit) = _pool.bucketLenders(1606, address(_lender));
        assertEq(lpb_before, lpBalance);
        assertEq(lastQuoteDeposit, 60);
        assertEq(exchangeRateBefore, _pool.exchangeRate(1606));

        // lender makes a partial withdrawal, paying an early withdrawal penalty
        changePrank(_lender);
        uint256 penalty = Maths.WAD - Maths.wdiv(_pool.interestRate(), _pool.WAD_WEEKS_PER_YEAR());
        assertLt(penalty, Maths.WAD);
        uint256 expectedWithdrawal1 = Maths.wmul(1_700 * 1e18, penalty);
        vm.expectEmit(true, true, false, true);
        emit RemoveQuoteToken(address(_lender), _pool.indexToPrice(1606), expectedWithdrawal1, _pool.indexToPrice(1663));
        uint lpRedeemed = _pool.removeQuoteToken(1_700 * 1e18, 1606);
        assertEq(lpRedeemed, 1_699.988430646833722457777450974 * 1e27);

        // lender removes all quote token, including interest, from the bucket
        skip(1 days);
        assertGt(_pool.indexToPrice(1606), _pool.htp());
        uint256 expectedWithdrawal2 = 1_700.146556206950492732 * 1e18;
        vm.expectEmit(true, true, false, true);
        emit RemoveQuoteToken(address(_lender), _pool.indexToPrice(1606), expectedWithdrawal2, _pool.indexToPrice(1663));
        uint256 removed;
        (removed, lpRedeemed) = _pool.removeAllQuoteToken(1606);
        assertEq(removed, expectedWithdrawal2);
        assertEq(lpRedeemed, 1_700.011569353166277542222549026 * 1e27);
        assertEq(_quote.balanceOf(address(_lender)), lenderBalanceBefore + expectedWithdrawal1 + expectedWithdrawal2);
        (lpBalance, ) = _pool.bucketLenders(1606, address(_lender));
        assertEq(lpBalance, 0);

        // ensure bucket is empty
        (uint256 quote, uint256 collateral, uint256 lpb, ) = _pool.bucketAt(1606);
        assertEq(quote, 0);
        assertEq(collateral, 0);
        assertEq(lpb, 0);
    }

    function testScaledPoolMoveQuoteToken() external {
        changePrank(_lender);
        _pool.addQuoteToken(40_000 * 1e18, 2549);
        _pool.addQuoteToken(10_000 * 1e18, 2550);
        _pool.addQuoteToken(20_000 * 1e18, 2551);

        (uint256 lpBalance, ) = _pool.bucketLenders(2549, address(_lender));
        assertEq(lpBalance, 40_000 * 1e27);
        (lpBalance, ) = _pool.bucketLenders(2552, address(_lender));
        assertEq(lpBalance, 0);

        vm.expectEmit(true, true, false, true);
        emit MoveQuoteToken(address(_lender), 2549, 2552, 5_000 * 1e18, BucketMath.MAX_PRICE);
        _pool.moveQuoteToken(5_000 * 1e18, 2549, 2552);

        (lpBalance, ) = _pool.bucketLenders(2549, address(_lender));
        assertEq(lpBalance, 35_000 * 1e27);
        (lpBalance, ) = _pool.bucketLenders(2552, address(_lender));
        assertEq(lpBalance, 5_000 * 1e27);

        vm.expectEmit(true, true, false, true);
        emit MoveQuoteToken(address(_lender), 2549, 2540, 5_000 * 1e18, BucketMath.MAX_PRICE);
        _pool.moveQuoteToken(5_000 * 1e18, 2549, 2540);

        (lpBalance, ) = _pool.bucketLenders(2549, address(_lender));
        assertEq(lpBalance, 30_000 * 1e27);
        (lpBalance, ) = _pool.bucketLenders(2540, address(_lender));
        assertEq(lpBalance, 5_000 * 1e27);

        vm.expectEmit(true, true, false, true);
        emit MoveQuoteToken(address(_lender), 2551, 2777, 15_000 * 1e18, BucketMath.MAX_PRICE);
        _pool.moveQuoteToken(15_000 * 1e18, 2551, 2777);

        (lpBalance, ) = _pool.bucketLenders(2551, address(_lender));
        assertEq(lpBalance, 5_000 * 1e27);
        (lpBalance, ) = _pool.bucketLenders(2777, address(_lender));
        assertEq(lpBalance, 15_000 * 1e27);
    }

    /**
     *  @notice 1 lender, 1 bidder, 1 borrower tests reverts in moveQuoteToken.
     *          Reverts:
     *              Attempts to move quote token to the same price.
     *              Attempts to move quote token from bucket with available collateral.
     *              Attempts to move quote token when doing so would drive lup below htp.
     */
    function testScaledPoolMoveQuoteTokenRequireChecks() external {
        // test setup
        deal(address(_collateral), _lender1, _collateral.balanceOf(_lender1) + 100_000 * 1e18);
        _collateral.approve(address(_pool), 100_000 * 1e18);

        // lender adds initial quote token
        changePrank(_lender);
        _pool.addQuoteToken(40_000 * 1e18, 4549);
        _pool.addQuoteToken(10_000 * 1e18, 4550);
        _pool.addQuoteToken(20_000 * 1e18, 4551);

        // should revert if moving quote token to the existing price
        vm.expectRevert("S:MQT:SAME_PRICE");
        _pool.moveQuoteToken(5_000 * 1e18, 4549, 4549);

        // add collateral and borrow all available quote in the higher priced original 3 buckets, as well as some of the new lowest price bucket
        _pool.addQuoteToken(30_000 * 1e18, 4651);
        changePrank(_borrower);
        deal(address(_collateral), _borrower, _collateral.balanceOf(_borrower) + 1_500_000 * 1e18);
        _collateral.approve(address(_pool), 1_500_000 * 1e18);
        _pool.pledgeCollateral(1500000 * 1e18, address(0), address(0));
        _pool.borrow(60000.1 * 1e18, 4651, address(0), address(0));

        // should revert if movement would drive lup below htp
        changePrank(_lender);
        vm.expectRevert("S:MQT:LUP_BELOW_HTP");
        _pool.moveQuoteToken(40_000 * 1e18, 4549, 6000);

        // should be able to moveQuoteToken if properly specified
        vm.expectEmit(true, true, false, true);
        emit MoveQuoteToken(address(_lender), 4549, 4550, 10_000 * 1e18, _pool.indexToPrice(4551));
        _pool.moveQuoteToken(10_000 * 1e18, 4549, 4550);
    }

    // TODO: test moving quote token with debt on the book and skips to accumulate interest
}
