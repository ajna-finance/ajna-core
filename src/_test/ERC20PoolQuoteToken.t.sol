// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.11;

import {DSTestPlus} from "./utils/DSTestPlus.sol";
import {UserWithCollateral, UserWithQuoteToken} from "./utils/Users.sol";
import {CollateralToken, QuoteToken} from "./utils/Tokens.sol";
import "../libraries/BucketMath.sol";

import {ERC20Pool} from "../ERC20Pool.sol";
import {ERC20PoolFactory} from "../ERC20PoolFactory.sol";

import "../libraries/Maths.sol";
import "../libraries/Buckets.sol";

contract ERC20PoolQuoteTokenTest is DSTestPlus {
    uint256 public constant MAX_INT = 2**256 - 1;
    uint256 public constant LARGEST_AMOUNT = MAX_INT / 10**27;

    ERC20Pool internal pool;
    CollateralToken internal collateral;
    QuoteToken internal quote;

    UserWithCollateral internal borrower;
    UserWithCollateral internal borrower2;
    UserWithQuoteToken internal lender;
    UserWithQuoteToken internal lender1;

    function setUp() public {
        collateral = new CollateralToken();
        quote = new QuoteToken();

        ERC20PoolFactory factory = new ERC20PoolFactory();
        pool = factory.deployPool(address(collateral), address(quote));

        borrower = new UserWithCollateral();
        collateral.mint(address(borrower), 100 * 1e18);
        borrower.approveToken(collateral, address(pool), 100 * 1e18);
        borrower.approveToken(quote, address(pool), 200_000 * 1e18);

        borrower2 = new UserWithCollateral();
        collateral.mint(address(borrower2), 200 * 1e18);
        borrower2.approveToken(collateral, address(pool), 200 * 1e18);
        borrower2.approveToken(quote, address(pool), 200_000 * 1e18);

        lender = new UserWithQuoteToken();
        quote.mint(address(lender), 200_000 * 1e18);
        lender.approveToken(quote, address(pool), 200_000 * 1e18);

        lender1 = new UserWithQuoteToken();
        quote.mint(address(lender1), 200_000 * 1e18);
        lender1.approveToken(quote, address(pool), 200_000 * 1e18);
    }

    // TODO: Review each test and validate HPB and LUP are correct where appropriate.

    // @notice: 1 lender tests adding quote token
    // @notice: lender Reverts:
    // @notice:     attempts to addQuoteToken at invalid price
    function testDepositQuoteToken() public {
        // should revert when depositing at invalid price
        vm.expectRevert(ERC20Pool.InvalidPrice.selector);
        lender.addQuoteToken(pool, address(lender), 10_000 * 1e18, 10_049.48314 * 1e18);

        assertEq(pool.hpb(), 0);
        // test 10000 DAI deposit at price of 1 MKR = 4000 DAI
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(lender), address(pool), 10_000 * 1e18);
        vm.expectEmit(true, true, false, true);
        emit AddQuoteToken(address(lender), 4_000.927678580567537368 * 1e18, 10_000 * 1e45, 0);
        lender.addQuoteToken(pool, address(lender), 10_000 * 1e18, 4_000.927678580567537368 * 1e18);
        // check pool hbp and balances
        assertEq(pool.hpb(), 4_000.927678580567537368 * 1e18);
        assertEq(pool.totalQuoteToken(), 10_000 * 1e45);
        assertEq(quote.balanceOf(address(pool)), 10_000 * 1e18);
        assertEq(quote.balanceOf(address(lender)), 190_000 * 1e18);
        // check bucket balance
        (
            uint256 price,
            uint256 upPrice,
            uint256 downPrice,
            uint256 deposit,
            uint256 debt,
            uint256 snapshot,
            uint256 lpOutstanding,

        ) = pool.bucketAt(4_000.927678580567537368 * 1e18);
        assertEq(price, 4_000.927678580567537368 * 1e18);
        assertEq(upPrice, 4_000.927678580567537368 * 1e18);
        assertEq(downPrice, 0);
        assertEq(deposit, 10_000 * 1e45);
        assertEq(debt, 0);
        assertEq(snapshot, 1 * 1e18);
        assertEq(lpOutstanding, 10_000 * 1e27);
        // check lender's LP amount can be redeemed for correct amount of quote token
        assertEq(pool.lpBalance(address(lender), 4_000.927678580567537368 * 1e18), 10_000 * 1e27);
        (uint256 collateralTokens, uint256 quoteTokens) = pool.getLPTokenExchangeValue(
            10_000 * 1e27,
            4_000.927678580567537368 * 1e18
        );
        assertEq(collateralTokens, 0);
        assertEq(quoteTokens, 10_000 * 1e45);

        // test 20000 DAI deposit at price of 1 MKR = 2000.221618840727700609 DAI
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(lender), address(pool), 20_000 * 1e18);
        vm.expectEmit(true, true, false, true);
        emit AddQuoteToken(address(lender), 2000.221618840727700609 * 1e18, 20_000 * 1e45, 0);
        lender.addQuoteToken(pool, address(lender), 20_000 * 1e18, 2000.221618840727700609 * 1e18);
        // check pool hbp and balances
        assertEq(pool.hpb(), 4_000.927678580567537368 * 1e18);
        assertEq(pool.totalQuoteToken(), 30_000 * 1e45);
        assertEq(quote.balanceOf(address(pool)), 30_000 * 1e18);
        assertEq(quote.balanceOf(address(lender)), 170_000 * 1e18);
        // check bucket balance
        (price, upPrice, downPrice, deposit, debt, snapshot, lpOutstanding, ) = pool.bucketAt(
            2000.221618840727700609 * 1e18
        );
        assertEq(price, 2000.221618840727700609 * 1e18);
        assertEq(upPrice, 4_000.927678580567537368 * 1e18);
        assertEq(downPrice, 0);
        assertEq(deposit, 20_000 * 1e45);
        assertEq(debt, 0);
        assertEq(snapshot, 1 * 1e18);
        assertEq(lpOutstanding, 20_000 * 1e27);
        assertEq(pool.lpBalance(address(lender), 2000.221618840727700609 * 1e18), 20_000 * 1e27);
        // check hdp down price pointer updated
        (, upPrice, downPrice, , , , , ) = pool.bucketAt(4_000.927678580567537368 * 1e18);
        assertEq(upPrice, 4_000.927678580567537368 * 1e18);
        assertEq(downPrice, 2_000.221618840727700609 * 1e18);

        // test 30000 DAI deposit at price of 1 MKR = 3010.892022197881557845 DAI
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(lender), address(pool), 30_000 * 1e18);
        vm.expectEmit(true, true, false, true);
        emit AddQuoteToken(address(lender), 3010.892022197881557845 * 1e18, 30_000 * 1e45, 0);
        lender.addQuoteToken(pool, address(lender), 30_000 * 1e18, 3010.892022197881557845 * 1e18);
        // check pool hbp and balances
        assertEq(pool.hpb(), 4_000.927678580567537368 * 1e18);
        assertEq(pool.totalQuoteToken(), 60_000 * 1e45);
        assertEq(quote.balanceOf(address(pool)), 60_000 * 1e18);
        assertEq(quote.balanceOf(address(lender)), 140_000 * 1e18);
        // check bucket balance
        (price, upPrice, downPrice, deposit, debt, snapshot, lpOutstanding, ) = pool.bucketAt(
            3010.892022197881557845 * 1e18
        );
        assertEq(price, 3010.892022197881557845 * 1e18);
        assertEq(upPrice, 4_000.927678580567537368 * 1e18);
        assertEq(downPrice, 2_000.221618840727700609 * 1e18);
        assertEq(deposit, 30_000 * 1e45);
        assertEq(debt, 0);
        assertEq(snapshot, 1 * 1e18);
        assertEq(lpOutstanding, 30_000 * 1e27);
        assertEq(pool.lpBalance(address(lender), 3010.892022197881557845 * 1e18), 30_000 * 1e27);
        // check hdp down price pointer updated
        (, upPrice, downPrice, , , , , ) = pool.bucketAt(4_000.927678580567537368 * 1e18);
        assertEq(upPrice, 4_000.927678580567537368 * 1e18);
        assertEq(downPrice, 3010.892022197881557845 * 1e18);
        // check 2000 down price pointer updated
        (, upPrice, downPrice, , , , , ) = pool.bucketAt(2_000.221618840727700609 * 1e18);
        assertEq(upPrice, 3010.892022197881557845 * 1e18);
        assertEq(downPrice, 0);

        // test 40000 DAI deposit at price of 1 MKR = 5000 DAI
        // hbp should be updated to 5000 DAI and hbp next price should be 4000 DAI
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(lender), address(pool), 40_000 * 1e18);
        vm.expectEmit(true, true, false, true);
        emit AddQuoteToken(address(lender), 5_007.644384905151472283 * 1e18, 40_000 * 1e45, 0);
        lender.addQuoteToken(pool, address(lender), 40_000 * 1e18, 5_007.644384905151472283 * 1e18);
        // check pool hbp and balances
        assertEq(pool.hpb(), 5_007.644384905151472283 * 1e18);
        assertEq(pool.totalQuoteToken(), 100_000 * 1e45);
        assertEq(quote.balanceOf(address(pool)), 100_000 * 1e18);
        assertEq(quote.balanceOf(address(lender)), 100_000 * 1e18);
        // check bucket balance
        (price, upPrice, downPrice, deposit, debt, snapshot, lpOutstanding, ) = pool.bucketAt(
            5_007.644384905151472283 * 1e18
        );
        assertEq(price, 5_007.644384905151472283 * 1e18);
        assertEq(upPrice, 5_007.644384905151472283 * 1e18);
        assertEq(downPrice, 4_000.927678580567537368 * 1e18);
        assertEq(deposit, 40_000 * 1e45);
        assertEq(debt, 0);
        assertEq(snapshot, 1 * 1e18);
        assertEq(lpOutstanding, 40_000 * 1e27);
        assertEq(pool.lpBalance(address(lender), 5_007.644384905151472283 * 1e18), 40_000 * 1e27);
    }

    // @notice: 1 lender and 1 borrower test adding quote token
    // @notice: borrowing then reallocating twice by depositing above the lup
    function testDepositQuoteTokenWithReallocation() public {
        uint256 p4000 = 4_000.927678580567537368 * 1e18;
        uint256 p3000 = 3_010.892022197881557845 * 1e18;
        uint256 p2000 = 2_000.221618840727700609 * 1e18;

        // Lender deposits into three buckets
        lender.addQuoteToken(pool, address(lender), 1_000 * 1e18, p4000);
        lender.addQuoteToken(pool, address(lender), 1_000 * 1e18, p3000);
        lender.addQuoteToken(pool, address(lender), 1_000 * 1e18, p2000);

        // Borrower draws debt from all three
        borrower.addCollateral(pool, 10 * 1e18);
        borrower.borrow(pool, 2_400 * 1e18, 0);
        (, , , uint256 deposit, uint256 debt, , , ) = pool.bucketAt(p4000);
        assertEq(deposit, 0);
        assertEq(debt, 1_000 * 1e45);
        (, , , deposit, debt, , , ) = pool.bucketAt(p3000);
        assertEq(deposit, 0);
        assertEq(debt, 1_000 * 1e45);
        (, , , deposit, debt, , , ) = pool.bucketAt(p2000);
        assertEq(deposit, 600 * 1e45);
        assertEq(debt, 400 * 1e45);
        assertEq(pool.lup(), p2000);

        // Lender deposits more into the middle bucket, causing reallocation
        lender.addQuoteToken(pool, address(lender), 2_000 * 1e18, p3000);
        (, , , deposit, debt, , , ) = pool.bucketAt(p4000);
        assertEq(deposit, 0);
        assertEq(debt, 1_000 * 1e45);
        (, , , deposit, debt, , , ) = pool.bucketAt(p3000);
        assertEq(deposit, 1_600 * 1e45);
        assertEq(debt, 1_400 * 1e45);
        (, , , deposit, debt, , , ) = pool.bucketAt(p2000);
        assertEq(deposit, 1_000 * 1e45);
        assertEq(debt, 0);
        assertEq(pool.lup(), p3000);

        // Lender deposits in the top bucket, causing another reallocation
        lender.addQuoteToken(pool, address(lender), 3_000 * 1e18, p4000);
        (, , , deposit, debt, , , ) = pool.bucketAt(p4000);
        assertEq(deposit, 1600 * 1e45);
        assertEq(debt, 2_400 * 1e45);
        (, , , deposit, debt, , , ) = pool.bucketAt(p3000);
        assertEq(deposit, 3_000 * 1e45);
        assertEq(debt, 0);
        (, , , deposit, debt, , , ) = pool.bucketAt(p2000);
        assertEq(deposit, 1_000 * 1e45);
        assertEq(debt, 0);
        assertEq(pool.lup(), p4000);
    }

    // @notice: 1 lender and 1 borrower test adding quote token,
    // @notice: borowing all liquidity then adding quote token above the lup
    function testDepositAboveLupWithLiquidityGapBetweenLupAndNextUnutilizedBucket() public {
        // When a user deposits above the LUP, debt is reallocated upward.
        // LUP should update when debt is reallocated upward such that the new
        // LUP has jumped across a liquidity gap.

        uint256 p2821 = 2_821.865943149948749647 * 1e18; // index 1593
        uint256 p2807 = 2_807.826809104426639178 * 1e18; // index 1592
        uint256 p2793 = 2_793.857521496941952028 * 1e18; // index 1591
        uint256 p2779 = 2_779.957732832778084277 * 1e18; // index 1590

        // Lender deposits in three of the four buckets, leaving a liquidity gap
        lender.addQuoteToken(pool, address(lender), 1_000 * 1e18, p2821);
        lender.addQuoteToken(pool, address(lender), 1_000 * 1e18, p2807);
        lender.addQuoteToken(pool, address(lender), 1_000 * 1e18, p2779);

        // Borrower draws debt utilizing all buckets with liquidity
        borrower.addCollateral(pool, 10 * 1e18);
        borrower.borrow(pool, 2_100 * 1e18, 0);
        (, , , uint256 deposit, uint256 debt, , , ) = pool.bucketAt(p2779);
        assertEq(deposit, 900 * 1e45);
        assertEq(debt, 100 * 1e45);
        assertEq(pool.lup(), p2779);

        // Lender deposits above the gap, pushing up the LUP
        lender.addQuoteToken(pool, address(lender), 500 * 1e18, p2807);
        (, , , deposit, debt, , , ) = pool.bucketAt(p2821);
        assertEq(deposit, 0);
        assertEq(debt, 1_000 * 1e45);
        (, , , deposit, debt, , , ) = pool.bucketAt(p2807);
        assertEq(deposit, 400 * 1e45);
        assertEq(debt, 1_100 * 1e45);
        (, , , deposit, debt, , , ) = pool.bucketAt(p2793);
        assertEq(deposit, 0);
        assertEq(debt, 0);
        (, , , deposit, debt, , , ) = pool.bucketAt(p2779);
        assertEq(deposit, 1_000 * 1e45);
        assertEq(debt, 0);
        assertEq(pool.lup(), p2807);
    }

    // @notice: 1 lender and 1 borrower test adding quote token,
    // @notice: borowing all liquidity at LUP then adding quote token at the LUP
    function testDepositQuoteTokenAtLup() public {
        // Adjacent prices
        uint256 p2850 = 2_850.155149230026939621 * 1e18; // index 1595
        uint256 p2835 = 2_835.975272865698470386 * 1e18; // index 1594
        uint256 p2821 = 2_821.865943149948749647 * 1e18; // index 1593
        uint256 p2807 = 2_807.826809104426639178 * 1e18; // index 1592

        // Lender deposits 1000 in each bucket
        lender.addQuoteToken(pool, address(lender), 1_000 * 1e18, p2850);
        lender.addQuoteToken(pool, address(lender), 1_000 * 1e18, p2835);
        lender.addQuoteToken(pool, address(lender), 1_000 * 1e18, p2821);
        lender.addQuoteToken(pool, address(lender), 1_000 * 1e18, p2807);

        // Borrower draws 2000 debt fully utilizing the LUP
        borrower.addCollateral(pool, 10 * 1e18);
        borrower.borrow(pool, 2_000 * 1e18, 0);
        (, , , uint256 deposit, uint256 debt, , , ) = pool.bucketAt(p2850);
        assertEq(deposit, 0);
        assertEq(debt, 1_000 * 1e45);
        (, , , deposit, debt, , , ) = pool.bucketAt(p2835);
        assertEq(deposit, 0);
        assertEq(debt, 1_000 * 1e45);
        (, , , deposit, debt, , , ) = pool.bucketAt(p2821);
        assertEq(deposit, 1_000 * 1e45);
        assertEq(debt, 0);
        (, , , deposit, debt, , , ) = pool.bucketAt(p2807);
        assertEq(deposit, 1_000 * 1e45);
        assertEq(debt, 0);
        assertEq(pool.lup(), p2835);

        // Lender deposits 1400 at LUP
        lender.addQuoteToken(pool, address(lender1), 1_400 * 1e18, p2835);
        (, , , deposit, debt, , , ) = pool.bucketAt(p2850);
        assertEq(deposit, 0);
        assertEq(debt, 1_000 * 1e45);
        (, , , deposit, debt, , , ) = pool.bucketAt(p2835);
        assertEq(deposit, 1_400 * 1e45);
        assertEq(debt, 1_000 * 1e45);
        (, , , deposit, debt, , , ) = pool.bucketAt(p2821);
        assertEq(deposit, 1_000 * 1e45);
        assertEq(debt, 0);
        (, , , deposit, debt, , , ) = pool.bucketAt(p2807);
        assertEq(deposit, 1_000 * 1e45);
        assertEq(debt, 0);
        assertEq(pool.lup(), p2835);
    }

    // @notice: 1 lender deposits quote token then removes quote token
    // @notice: with no loans outstanding
    function testRemoveQuoteTokenNoLoan() public {
        // lender deposit 10000 DAI at price 4000
        lender.addQuoteToken(pool, address(lender), 10_000 * 1e18, 4_000.927678580567537368 * 1e18);
        skip(8200);

        // check balances before removal
        assertEq(pool.totalDebt(), 0);
        assertEq(pool.totalQuoteToken(), 10_000 * 1e45);

        (, , , uint256 deposit, uint256 debt, , uint256 lpOutstanding, ) = pool.bucketAt(
            4_000.927678580567537368 * 1e18
        );
        assertEq(deposit, 10_000 * 1e45);
        assertEq(debt, 0);
        assertEq(lpOutstanding, 10_000 * 1e27);
        assertEq(pool.lpBalance(address(lender), 4_000.927678580567537368 * 1e18), 10_000 * 1e27);

        // remove 10000 DAI at price of 1 MKR = 4_000.927678580567537368 DAI
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(pool), address(lender), 10_000 * 1e18);
        vm.expectEmit(true, true, false, true);
        emit RemoveQuoteToken(address(lender), 4_000.927678580567537368 * 1e18, 10_000 * 1e45, 0);
        lender.removeQuoteToken(
            pool,
            address(lender),
            10_000 * 1e18,
            4_000.927678580567537368 * 1e18
        );

        // check balances after removal
        assertEq(pool.totalDebt(), 0);
        assertEq(pool.totalQuoteToken(), 0);
        // check 4000 bucket balance
        (, , , deposit, debt, , lpOutstanding, ) = pool.bucketAt(4_000.927678580567537368 * 1e18);
        assertEq(deposit, 0 * 1e18);
        assertEq(debt, 0);
        assertEq(lpOutstanding, 0);
        assertEq(pool.lpBalance(address(lender), 4_000.927678580567537368 * 1e18), 0);
    }

    // @notice: 1 lender deposits quote token then removes quote token
    // @notice: with an unpaid loan outstanding
    // @notice: lender reverts:
    // @notice:         attempts to remove more quote token then lent out
    function testRemoveQuoteTokenUnpaidLoan() public {
        uint256 priceMed = 4_000.927678580567537368 * 1e18;

        // lender deposit 10000 DAI at price 4_000.927678580567537368
        lender.addQuoteToken(pool, address(lender), 10_000 * 1e18, priceMed);
        assertEq(quote.balanceOf(address(lender)), 190_000 * 1e18);

        // check balances
        assertEq(quote.balanceOf(address(pool)), 10_000 * 1e18);
        assertEq(pool.totalQuoteToken(), 10_000 * 1e45);
        assertEq(quote.balanceOf(address(lender)), 190_000 * 1e18);
        assertEq(pool.lpBalance(address(lender), priceMed), 10_000 * 1e27);

        // borrower takes a loan of 5_000 DAI
        borrower.addCollateral(pool, 100 * 1e18);
        borrower.borrow(pool, 5_000 * 1e18, 4_000 * 1e18);

        // should revert if trying to remove entire amount lended
        vm.expectRevert(Buckets.NoDepositToReallocateTo.selector);
        lender.removeQuoteToken(pool, address(lender), 10_000 * 1e18, priceMed);

        // confirm our LP balance still entitles us to our share of the utilized bucket
        assertEq(pool.lpBalance(address(lender), priceMed), 10_000 * 1e27);
        (uint256 collateralTokens, uint256 quoteTokens) = pool.getLPTokenExchangeValue(
            10_000 * 1e27,
            priceMed
        );
        assertEq(collateralTokens, 0);
        assertEq(quoteTokens, 10_000 * 1e45);

        // check price pointers
        assertEq(pool.hpb(), priceMed);
        assertEq(pool.lup(), priceMed);

        // remove 4000 DAI at price of 1 MKR = 4_000.927678580567537368 DAI
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(pool), address(lender), 4_000 * 1e18);
        vm.expectEmit(true, true, false, true);
        emit RemoveQuoteToken(address(lender), priceMed, 4_000 * 1e45, priceMed);
        lender.removeQuoteToken(pool, address(lender), 4_000 * 1e18, priceMed);

        // check pool balances
        assertEq(pool.totalQuoteToken(), 1_000 * 1e45);
        assertEq(quote.balanceOf(address(pool)), 1_000 * 1e18);
        // check lender balance
        assertEq(quote.balanceOf(address(lender)), 194_000 * 1e18);

        // check 4000 bucket balance
        (, , , uint256 deposit, uint256 debt, , uint256 lpOutstanding, ) = pool.bucketAt(priceMed);
        assertEq(deposit, 1_000 * 1e45);
        assertEq(debt, 5_000 * 1e45);
        assertEq(lpOutstanding, 6_000 * 1e27);
        assertEq(pool.lpBalance(address(lender), priceMed), 6_000 * 1e27);
    }

    // @notice: 1 lender and 1 borrower deposits quote token
    // @notice: borrows, repays then time passes and
    // @notice: quote token is removed
    function testRemoveQuoteTokenPaidLoan() public {
        uint256 priceMed = 4_000.927678580567537368 * 1e18;
        // lender deposit 10000 DAI at price 4000
        lender.addQuoteToken(pool, address(lender), 10_000 * 1e18, priceMed);
        assertEq(quote.balanceOf(address(lender)), 190_000 * 1e18);

        // lender1 deposit 10000 DAI at price 4000:
        lender1.addQuoteToken(pool, address(lender1), 10_000 * 1e18, priceMed);
        assertEq(quote.balanceOf(address(lender1)), 190_000 * 1e18);

        // borrower takes a loan of 10_000 DAI
        borrower.addCollateral(pool, 100 * 1e18);
        borrower.borrow(pool, 10_000 * 1e18, 4_000 * 1e18);
        assertEq(pool.lup(), priceMed);

        // borrower repay entire loan
        quote.mint(address(borrower), 1 * 1e18);
        borrower.approveToken(quote, address(pool), 100_000 * 1e18);

        borrower.repay(pool, 10_001 * 1e18);

        skip(8200);

        //exchange rate
        //TODO: Get the exchange rate and calculate automatically
        lender1.removeQuoteToken(pool, address(lender1), 10_000 * 1e18, priceMed);

        // lender removes entire amount lended
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(pool), address(lender), 10_000 * 1e18);
        vm.expectEmit(true, true, false, true);
        emit RemoveQuoteToken(address(lender), priceMed, 10_000 * 1e45, priceMed);
        lender.removeQuoteToken(pool, address(lender), 10_000 * 1e18, priceMed);

        // check pool balances
        assertEq(pool.totalQuoteToken(), 0);
        assertEq(quote.balanceOf(address(pool)), 0);
        // check lender balance
        assertEq(quote.balanceOf(address(lender)), 200_000 * 1e18);

        // check 4000 bucket balance
        (, , , uint256 deposit, uint256 debt, , , ) = pool.bucketAt(priceMed);
        assertEq(deposit, 0);
        assertEq(debt, 0);
    }

    // @notice: 1 lender and 1 borrower deposits quote token
    // @notice: borrows, then lender removes quote token
    function testRemoveQuoteTokenWithDebtReallocation() public {
        // lender deposit 3_400 DAI in 2 buckets
        uint256 priceMed = 4_000.927678580567537368 * 1e18;
        uint256 priceLow = 3_010.892022197881557845 * 1e18;

        lender.addQuoteToken(pool, address(lender), 3_400 * 1e18, priceMed);
        lender.addQuoteToken(pool, address(lender), 3_400 * 1e18, priceLow);

        // borrower takes a loan of 3000 DAI
        borrower.addCollateral(pool, 100 * 1e18);
        borrower.borrow(pool, 3_000 * 1e18, 4_000 * 1e18);
        assertEq(pool.lup(), priceMed);
        (, , , uint256 deposit, uint256 debt, , uint256 lpOutstanding, ) = pool.bucketAt(priceMed);
        assertEq(deposit, 400 * 1e45);
        assertEq(debt, 3_000 * 1e45);
        (, , , deposit, debt, , , ) = pool.bucketAt(priceLow);
        assertEq(deposit, 3_400 * 1e45);
        assertEq(debt, 0);
        uint256 poolCollateralizationAfterBorrow = pool.getPoolCollateralization();
        uint256 targetUtilizationAfterBorrow = pool.getPoolTargetUtilization();
        uint256 actualUtilizationAfterBorrow = pool.getPoolActualUtilization();
        assertEq(poolCollateralizationAfterBorrow, 133.364255952685584578933333386 * 1e27);
        assertGt(actualUtilizationAfterBorrow, targetUtilizationAfterBorrow);

        // lender removes 1000 DAI from LUP
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(pool), address(lender), 1_000 * 1e18);
        vm.expectEmit(true, true, false, true);
        emit RemoveQuoteToken(address(lender), priceMed, 1_000 * 1e45, priceLow);
        lender.removeQuoteToken(pool, address(lender), 1_000 * 1e18, priceMed);

        // check that utilization increased following the removal of deposit
        uint256 poolCollateralizationAfterRemove = pool.getPoolCollateralization();
        uint256 targetUtilizationAfterRemove = pool.getPoolTargetUtilization();
        uint256 actualUtilizationAfterRemove = pool.getPoolActualUtilization();
        assertLt(poolCollateralizationAfterRemove, poolCollateralizationAfterBorrow);
        assertGt(actualUtilizationAfterRemove, targetUtilizationAfterRemove);
        assertGt(actualUtilizationAfterRemove, actualUtilizationAfterBorrow);
        assertGt(targetUtilizationAfterRemove, targetUtilizationAfterBorrow);

        // check lup moved down to 3000
        assertEq(pool.lup(), priceLow);
        // check pool balances
        assertEq(pool.totalQuoteToken(), 2_800 * 1e45);
        assertEq(pool.totalDebt(), 3_000 * 1e45);
        assertEq(quote.balanceOf(address(pool)), 2_800 * 1e18);
        // check lender balance
        assertEq(quote.balanceOf(address(lender)), 194_200 * 1e18);

        // check 4000 bucket balance
        (, , , deposit, debt, , lpOutstanding, ) = pool.bucketAt(priceMed);
        assertEq(deposit, 0);
        assertEq(debt, 2_400 * 1e45);
        assertEq(lpOutstanding, 2_400 * 1e27);
        assertEq(pool.lpBalance(address(lender), priceMed), 2_400 * 1e27);

        // check 3_010.892022197881557845 bucket balance
        (, , , deposit, debt, , lpOutstanding, ) = pool.bucketAt(priceLow);
        assertEq(deposit, 2_800 * 1e45);
        assertEq(debt, 600 * 1e45);
        assertEq(lpOutstanding, 3_400 * 1e27);
        assertEq(pool.lpBalance(address(lender), priceLow), 3_400 * 1e27);
    }

    // @notice: 1 lender and 1 borrower deposits quote token
    // @notice: over time, borrows, then lender removes
    // @notice: quote token causing reallocation
    function testRemoveQuoteTokenOverTimeWithDebt() public {
        uint256 priceMed = 4_000.927678580567537368 * 1e18;
        uint256 priceLow = 3_010.892022197881557845 * 1e18;
        // lender deposit into 2 buckets
        lender.addQuoteToken(pool, address(lender), 1_000 * 1e18, priceMed);
        lender.addQuoteToken(pool, address(lender), 2_000 * 1e18, priceMed);
        skip(14);
        lender.addQuoteToken(pool, address(lender), 6_000 * 1e18, priceLow);
        skip(1340);

        // borrower takes a loan of 4000 DAI
        borrower.addCollateral(pool, 100 * 1e18);
        borrower.borrow(pool, 4_000 * 1e18, 0);
        (, , , uint256 deposit, uint256 debt, , uint256 lpOutstanding, ) = pool.bucketAt(priceMed);
        assertEq(deposit, 0);
        assertEq(debt, 3_000 * 1e45);
        assertEq(lpOutstanding, 3_000 * 1e27);
        (, , , deposit, debt, , lpOutstanding, ) = pool.bucketAt(priceLow);
        assertEq(deposit, 5_000 * 1e45);
        assertEq(debt, 1_000 * 1e45);
        assertEq(lpOutstanding, 6_000 * 1e27);
        assertEq(pool.hpb(), priceMed);
        assertEq(pool.lup(), priceLow);
        skip(1340);

        // lender removes entire bid from 4_000.927678580567537368 bucket
        // FIXME: need a way to remove the entire bid
        // uint256 withdrawalAmount = 3_000.006373674954296470378557 * 1e45;
        uint256 withdrawalAmount = 3_000 * 1e45;
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(pool), address(lender), withdrawalAmount / 1e27);
        emit RemoveQuoteToken(address(lender), priceMed, withdrawalAmount, priceMed);
        lender.removeQuoteToken(pool, address(lender), withdrawalAmount / 1e27, priceMed);

        // confirm entire bid was removed
        (, , , deposit, debt, , lpOutstanding, ) = pool.bucketAt(priceMed);
        assertEq(deposit, 0);
        // assertEq(debt, 0);  // FIXME: debt should be zero here
        // assertEq(lpOutstanding, 0);

        // confirm debt was reallocated
        (, , , deposit, debt, , lpOutstanding, ) = pool.bucketAt(priceLow);
        assertEq(deposit, 2_000 * 1e45);
        // some debt accumulated between loan and reallocation
        assertEq(debt, 4_000.002124558318098823459519 * 1e45);
        // assertEq(pool.hbp(), priceLow);  // FIXME: once all debt is reallocated, HPB should move
        assertEq(pool.lup(), priceLow);
    }

    // @notice: 1 lender and 1 borrower deposits quote token, borrow
    // @notice: then lender withdraws quote token above LUP
    function testRemoveQuoteTokenAboveLup() public {
        // Adjacent prices
        uint256 p2850 = 2850.155149230026939621 * 1e18; // index 1595
        uint256 p2835 = 2835.975272865698470386 * 1e18; // index 1594
        uint256 p2821 = 2821.865943149948749647 * 1e18; // index 1593
        uint256 p2807 = 2807.826809104426639178 * 1e18; // index 1592

        // Lender deposits 1000 in each bucket
        lender.addQuoteToken(pool, address(lender), 1_000 * 1e18, p2850);
        lender.addQuoteToken(pool, address(lender), 1_000 * 1e18, p2835);
        lender.addQuoteToken(pool, address(lender), 1_000 * 1e18, p2821);
        lender.addQuoteToken(pool, address(lender), 1_000 * 1e18, p2807);

        // check initial utilization after depositing but not borrowing
        assertEq(pool.getPoolCollateralization(), Maths.ONE_RAY);
        assertEq(pool.getPoolActualUtilization(), 0);
        assertEq(pool.getPoolTargetUtilization(), Maths.ONE_RAY);

        // Borrower draws 2400 debt partially utilizing the LUP
        borrower.addCollateral(pool, 10 * 1e18);
        borrower.borrow(pool, 2_400 * 1e18, 0);
        (, , , uint256 deposit, uint256 debt, , , ) = pool.bucketAt(p2850);
        assertEq(deposit, 0);
        assertEq(debt, 1_000 * 1e45);
        (, , , deposit, debt, , , ) = pool.bucketAt(p2835);
        assertEq(deposit, 0);
        assertEq(debt, 1_000 * 1e45);
        (, , , deposit, debt, , , ) = pool.bucketAt(p2821);
        assertEq(deposit, 600 * 1e45);
        assertEq(debt, 400 * 1e45);
        (, , , deposit, debt, , , ) = pool.bucketAt(p2807);
        assertEq(deposit, 1_000 * 1e45);
        assertEq(debt, 0);
        assertEq(pool.lup(), p2821);
        uint256 poolCollateralizationAfterBorrow = pool.getPoolCollateralization();
        uint256 targetUtilizationAfterBorrow = pool.getPoolTargetUtilization();
        uint256 actualUtilizationAfterBorrow = pool.getPoolActualUtilization();
        assertEq(poolCollateralizationAfterBorrow, 11.757774763124786456862499999 * 1e27);
        assertGt(actualUtilizationAfterBorrow, targetUtilizationAfterBorrow);

        // Lender withdraws above LUP
        lender.removeQuoteToken(pool, address(lender), 1_000 * 1e18, p2850);
        (, , , deposit, debt, , , ) = pool.bucketAt(p2850);
        assertEq(deposit, 0);
        assertEq(debt, 0);
        (, , , deposit, debt, , , ) = pool.bucketAt(p2835);
        assertEq(deposit, 0);
        assertEq(debt, 1_000 * 1e45);
        (, , , deposit, debt, , , ) = pool.bucketAt(p2821);
        assertEq(deposit, 0);
        assertEq(debt, 1_000 * 1e45);
        (, , , deposit, debt, , , ) = pool.bucketAt(p2807);
        assertEq(deposit, 600 * 1e45);
        assertEq(debt, 400 * 1e45);
        assertEq(pool.lup(), p2807);

        // check that utilization increased following the removal of deposit
        uint256 poolCollateralizationAfterRemove = pool.getPoolCollateralization();
        uint256 targetUtilizationAfterRemove = pool.getPoolTargetUtilization();
        uint256 actualUtilizationAfterRemove = pool.getPoolActualUtilization();
        assertLt(poolCollateralizationAfterRemove, poolCollateralizationAfterBorrow);
        assertGt(actualUtilizationAfterRemove, targetUtilizationAfterRemove);
        assertGt(actualUtilizationAfterRemove, actualUtilizationAfterBorrow);
        assertGt(targetUtilizationAfterRemove, targetUtilizationAfterBorrow);
    }

    // @notice: 1 lender and 1 borrower deposits quote token
    // @notice: borrows, then lender removes quote token under the LUP
    function testRemoveQuoteTokenBelowLup() public {
        uint256 priceHigh = 4_000.927678580567537368 * 1e18;
        uint256 priceMed = 3_010.892022197881557845 * 1e18;
        uint256 priceLow = 2_000.221618840727700609 * 1e18;
        // lender deposit 5000 DAI in 3 buckets
        lender.addQuoteToken(pool, address(lender), 5_000 * 1e18, priceHigh);
        lender.addQuoteToken(pool, address(lender), 5_000 * 1e18, priceMed);
        lender.addQuoteToken(pool, address(lender), 5_000 * 1e18, priceLow);

        // check initial utilization after depositing but not borrowing
        uint256 collateralization = pool.getPoolCollateralization();
        uint256 targetUtilization = pool.getPoolTargetUtilization();
        uint256 actualUtilization = pool.getPoolActualUtilization();
        assertEq(collateralization, Maths.ONE_RAY);
        assertEq(actualUtilization, 0);
        assertEq(targetUtilization, Maths.ONE_RAY);

        // borrower takes a loan of 3000 DAI
        borrower.addCollateral(pool, 100 * 1e18);
        borrower.borrow(pool, priceMed, 4_000 * 1e18);
        assertEq(pool.lup(), priceHigh);

        // lender removes 1000 DAI under the lup - from bucket 3000
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(pool), address(lender), 1_000 * 1e18);
        vm.expectEmit(true, true, false, true);
        emit RemoveQuoteToken(address(lender), priceMed, 1_000 * 1e45, priceHigh);
        lender.removeQuoteToken(pool, address(lender), 1_000 * 1e18, priceMed);

        // check same lup
        assertEq(pool.lup(), priceHigh);
        // check pool balances
        assertEq(pool.totalQuoteToken(), 10_989.107977802118442155 * 1e45);
        assertEq(quote.balanceOf(address(pool)), 10_989.107977802118442155 * 1e18);

        // check pool collateralization
        collateralization = pool.getPoolCollateralization();
        assertEq(collateralization, 132.881805427880566840691179328 * 1e27);

        // check pool is still overcollateralized
        targetUtilization = pool.getPoolTargetUtilization();
        actualUtilization = pool.getPoolActualUtilization();
        assertGt(actualUtilization, targetUtilization);

        // check 4000 bucket balance
        (, , , uint256 deposit, uint256 debt, , uint256 lpOutstanding, ) = pool.bucketAt(priceHigh);
        assertEq(deposit, 1_989.107977802118442155 * 1e45);
        assertEq(debt, 3_010.892022197881557845 * 1e45);
        assertEq(lpOutstanding, 5_000 * 1e27);
        assertEq(pool.lpBalance(address(lender), priceHigh), 5_000 * 1e27);

        // check 3_010.892022197881557845 bucket balance, should have less 1000 DAI and lp token
        (, , , deposit, debt, , lpOutstanding, ) = pool.bucketAt(priceMed);
        assertEq(deposit, 4_000 * 1e45);
        assertEq(debt, 0);
        assertEq(lpOutstanding, 4_000 * 1e27);
        assertEq(pool.lpBalance(address(lender), priceMed), 4_000 * 1e27);
    }

    // @notice: 1 lender and 1 borrower deposits quote token
    // @notice: borrows, then lender removes quote token in under collateralized pool
    function testRemoveQuoteUndercollateralizedPool() public {
        uint256 priceLow = 1_004.989662429170775094 * 1e18;
        uint256 priceLowest = 100.332368143282009890 * 1e18;
        // lender deposit 5000 DAI in 2 spaced buckets
        lender.addQuoteToken(pool, address(lender), 5_000 * 1e18, priceLow);
        lender.addQuoteToken(pool, address(lender), 5_000 * 1e18, priceLowest);

        // check initial utilization after depositing but not borrowing
        uint256 targetUtilization = pool.getPoolTargetUtilization();
        uint256 actualUtilization = pool.getPoolActualUtilization();
        assertEq(actualUtilization, 0);
        assertEq(targetUtilization, Maths.ONE_RAY);

        // borrower takes a loan of 4000 DAI at priceLow
        uint256 borrowAmount = 4_000 * 1e18;
        borrower.addCollateral(pool, 5.1 * 1e18);
        borrower.borrow(pool, borrowAmount, 1_000 * 1e18);
        assertEq(pool.lup(), priceLow);

        // removal should revert if pool remains undercollateralized
        vm.expectRevert(
            abi.encodeWithSelector(
                ERC20Pool.PoolUndercollateralized.selector,
                0.127923769382684562609750000 * 1e27
            )
        );
        lender.removeQuoteToken(pool, address(lender), 2_000 * 1e18, priceLow);

        // check pool collateralization after borrowing
        uint256 collateralization = pool.getPoolCollateralization();
        assertEq(collateralization, 1.281361819597192738244850000 * 1e27);

        // check pool utilization after borrowing
        targetUtilization = pool.getPoolTargetUtilization();
        actualUtilization = pool.getPoolActualUtilization();
        assertEq(actualUtilization, Maths.wadToRay(Maths.wdiv(borrowAmount, (10_000 * 1e18))));

        // since pool is undercollateralized actualUtilization should be < targetUtilization
        assertLt(actualUtilization, targetUtilization);
    }

    // @notice: 2 lenders both deposit then remove quote token
    function testRemoveQuoteMultipleLenders() public {
        uint256 priceLow = 1_004.989662429170775094 * 1e18;

        assertEq(quote.balanceOf(address(lender)), 200_000 * 1e18);
        assertEq(quote.balanceOf(address(lender1)), 200_000 * 1e18);
        assertEq(quote.balanceOf(address(pool)), 0);

        (, , , , , , uint256 lpOutstanding, ) = pool.bucketAt(priceLow);
        assertEq(lpOutstanding, 0);

        assertEq(pool.lpBalance(address(lender), priceLow), 0);
        assertEq(pool.lpBalance(address(lender1), priceLow), 0);

        // lender1 deposit 10000 DAI
        lender.addQuoteToken(pool, address(lender), 10_000 * 1e18, priceLow);
        // lender1 deposit 10000 DAI in same bucket
        lender1.addQuoteToken(pool, address(lender1), 10_000 * 1e18, priceLow);

        assertEq(quote.balanceOf(address(lender)), 190_000 * 1e18);
        assertEq(quote.balanceOf(address(lender1)), 190_000 * 1e18);
        assertEq(quote.balanceOf(address(pool)), 20_000 * 1e18);

        assertEq(pool.lpBalance(address(lender), priceLow), 10_000 * 1e27);
        assertEq(pool.lpBalance(address(lender1), priceLow), 10_000 * 1e27);

        (, , , , , , lpOutstanding, ) = pool.bucketAt(priceLow);
        assertEq(lpOutstanding, 20_000 * 1e27);

        skip(8200);

        lender.removeQuoteToken(pool, address(lender), 10_000 * 1e18, priceLow);
        assertEq(pool.lpBalance(address(lender), priceLow), 0);
        assertEq(pool.lpBalance(address(lender1), priceLow), 10_000 * 1e27);
        (, , , , , , lpOutstanding, ) = pool.bucketAt(priceLow);
        assertEq(lpOutstanding, 10_000 * 1e27);

        lender1.removeQuoteToken(pool, address(lender1), 10_000 * 1e18, priceLow);

        assertEq(quote.balanceOf(address(lender)), 200_000 * 1e18);
        assertEq(quote.balanceOf(address(lender1)), 200_000 * 1e18);
        assertEq(quote.balanceOf(address(pool)), 0);

        assertEq(pool.lpBalance(address(lender), priceLow), 0);
        assertEq(pool.lpBalance(address(lender1), priceLow), 0);
        (, , , , , , lpOutstanding, ) = pool.bucketAt(priceLow);
        assertEq(lpOutstanding, 0);
    }

    // @notice: 1 lender and 2 borrowers deposit quote token
    // @notice: remove quote token borrow, update interest rate
    // @notice: then remove quote token with interest
    // @notice: lender reverts: attempts to removeQuoteToken when not enough quote token in pool
    function testRemoveQuoteTokenWithInterest() public {
        // lender deposit in 3 buckets, price spaced
        uint256 p10016 = 10_016.501589292607751220 * 1e18;
        uint256 p9020 = 9_020.461710444470171420 * 1e18;
        uint256 p8002 = 8_002.824356287850613262 * 1e18;
        uint256 p100 = 100.332368143282009890 * 1e18;
        lender.addQuoteToken(pool, address(lender), 10_000 * 1e18, p10016);
        lender.addQuoteToken(pool, address(lender), 1_000 * 1e18, p9020);
        lender.addQuoteToken(pool, address(lender), 1_000 * 1e18, p8002);
        lender.addQuoteToken(pool, address(lender), 1_000 * 1e18, p100);

        // borrowers deposit collateral
        borrower.addCollateral(pool, 2 * 1e18);
        borrower2.addCollateral(pool, 200 * 1e18);
        assertEq(pool.getPoolCollateralization(), Maths.ONE_RAY);

        // first borrower takes a loan of 12_000 DAI, pushing lup to 8_002.824356287850613262
        borrower.borrow(pool, 12_000 * 1e18, 8_000 * 1e18);

        skip(5000);
        pool.updateInterestRate();
        skip(5000);
        // 2nd borrower takes a loan of 1_000 DAI, pushing lup to 100.332368143282009890
        borrower2.borrow(pool, 1_000 * 1e18, 100 * 1e18);

        skip(5000);
        pool.updateInterestRate();
        skip(5000);

        (uint256 col, uint256 quoteLPValue) = pool.getLPTokenExchangeValue(
            pool.getLPTokenBalance(address(lender), p8002),
            p8002
        );
        assertEq(quoteLPValue, 1_000.023113960510762449249703 * 1e45);

        // check pool state following borrows
        uint256 poolCollateralizationAfterBorrow = pool.getPoolCollateralization();
        uint256 targetUtilizationAfterBorrow = pool.getPoolTargetUtilization();
        uint256 actualUtilizationAfterBorrow = pool.getPoolActualUtilization();
        assertEq(poolCollateralizationAfterBorrow, 1.558858827078768654127776949 * 1e27);
        assertGt(actualUtilizationAfterBorrow, targetUtilizationAfterBorrow);

        // should revert if not enough funds in pool
        assertEq(pool.totalQuoteToken(), 0);
        vm.expectRevert(abi.encodeWithSelector(Buckets.NoDepositToReallocateTo.selector));
        lender.removeQuoteToken(pool, address(lender), 1_000.023113960510762449 * 1e18, p8002);

        // borrower repays their initial loan principal
        borrower.repay(pool, 12_000 * 1e18);
        (col, quoteLPValue) = pool.getLPTokenExchangeValue(
            pool.getLPTokenBalance(address(lender), p8002),
            p8002
        );
        assertEq(quoteLPValue, 1_000.058932266911224024728608229 * 1e45);

        // check that utilization decreased following repayment
        uint256 poolCollateralizationAfterRepay = pool.getPoolCollateralization();
        uint256 targetUtilizationAfterRepay = pool.getPoolTargetUtilization();
        uint256 actualUtilizationAfterRepay = pool.getPoolActualUtilization();
        assertGt(poolCollateralizationAfterRepay, poolCollateralizationAfterBorrow);
        assertGt(actualUtilizationAfterRepay, targetUtilizationAfterRepay);
        assertLt(actualUtilizationAfterRepay, actualUtilizationAfterBorrow);
        assertLt(targetUtilizationAfterRepay, targetUtilizationAfterBorrow);

        // should revert if trying to remove more than was lent
        vm.expectRevert(
            abi.encodeWithSelector(
                Buckets.AmountExceedsClaimable.selector,
                1_000.058932266911224024728608 * 1e45
            )
        );
        lender.removeQuoteToken(pool, address(lender), 1_001 * 1e18, p8002);

        // lender should be able to remove lent quote tokens + interest
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(pool), address(lender), 1_000.053487614594018248 * 1e18);
        vm.expectEmit(true, true, false, true);
        emit RemoveQuoteToken(address(lender), p8002, 1_000.053487614594018248 * 1e45, p10016);
        lender.removeQuoteToken(pool, address(lender), 1_000.053487614594018248 * 1e18, p8002);

        assertEq(pool.lup(), p10016);
    }

    // @notice: 1 lender removes more quote token than their claim
    function testRemoveMoreThanClaim() public {
        uint256 price = 4_000.927678580567537368 * 1e18;

        // lender deposit 4000 DAI at price 4000
        lender.addQuoteToken(pool, address(lender), 4_000 * 1e18, price);
        skip(14);

        // remove max 5000 DAI at price of 1 MKR = 4_000.927678580567537368 DAI
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(pool), address(lender), 4_000 * 1e18);
        vm.expectEmit(true, true, false, true);
        emit RemoveQuoteToken(address(lender), price, 4_000 * 1e45, 0);
        lender.removeQuoteToken(pool, address(lender), 5_000 * 1e18, price);
        // check balances
        assertEq(pool.totalQuoteToken(), 0);
        assertEq(quote.balanceOf(address(pool)), 0);
        skip(14);

        // lender deposit 2000 DAI at price 4000
        lender.addQuoteToken(pool, address(lender), 2_000 * 1e18, price);
        skip(14);

        // remove uint256.max at price of 1 MKR = 4_000.927678580567537368 DAI
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(pool), address(lender), 2_000 * 1e18);
        vm.expectEmit(true, true, false, true);
        emit RemoveQuoteToken(address(lender), price, 2_000 * 1e45, 0);
        lender.removeQuoteToken(pool, address(lender), LARGEST_AMOUNT, price);
        // check balances
        assertEq(pool.totalQuoteToken(), 0);
        assertEq(quote.balanceOf(address(pool)), 0);
    }
}
