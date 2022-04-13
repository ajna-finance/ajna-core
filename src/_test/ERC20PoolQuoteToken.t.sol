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
    ERC20Pool internal pool;
    CollateralToken internal collateral;
    QuoteToken internal quote;

    UserWithCollateral internal borrower;
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

        lender = new UserWithQuoteToken();
        quote.mint(address(lender), 200_000 * 1e18);
        lender.approveToken(quote, address(pool), 200_000 * 1e18);

        lender1 = new UserWithQuoteToken();
        quote.mint(address(lender1), 200_000 * 1e18);
        lender1.approveToken(quote, address(pool), 200_000 * 1e18);
    }

    function testDepositQuoteToken() public {
        // should revert when depositing at invalid price
        vm.expectRevert(ERC20Pool.InvalidPrice.selector);
        lender.addQuoteToken(
            pool,
            address(lender),
            10_000 * 1e18,
            10_049.48314 * 1e18
        );

        assertEq(pool.hdp(), 0);
        // test 10000 DAI deposit at price of 1 MKR = 4000 DAI
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(lender), address(pool), 10_000 * 1e18);
        vm.expectEmit(true, true, false, true);
        emit AddQuoteToken(
            address(lender),
            4_000.927678580567537368 * 1e18,
            10_000 * 1e45,
            0
        );
        lender.addQuoteToken(
            pool,
            address(lender),
            10_000 * 1e18,
            4_000.927678580567537368 * 1e18
        );
        // check pool hdp and balances
        assertEq(pool.hdp(), 4_000.927678580567537368 * 1e18);
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
        assertEq(
            pool.lpBalance(address(lender), 4_000.927678580567537368 * 1e18),
            10_000 * 1e27
        );
        (uint256 collateralTokens, uint256 quoteTokens) = pool
            .getLPTokenExchangeValue(
                10_000 * 1e27,
                4_000.927678580567537368 * 1e18
            );
        assertEq(collateralTokens, 0);
        assertEq(quoteTokens, 10_000 * 1e45);

        // test 20000 DAI deposit at price of 1 MKR = 2000.221618840727700609 DAI
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(lender), address(pool), 20_000 * 1e18);
        vm.expectEmit(true, true, false, true);
        emit AddQuoteToken(
            address(lender),
            2000.221618840727700609 * 1e18,
            20_000 * 1e45,
            0
        );
        lender.addQuoteToken(
            pool,
            address(lender),
            20_000 * 1e18,
            2000.221618840727700609 * 1e18
        );
        // check pool hdp and balances
        assertEq(pool.hdp(), 4_000.927678580567537368 * 1e18);
        assertEq(pool.totalQuoteToken(), 30_000 * 1e45);
        assertEq(quote.balanceOf(address(pool)), 30_000 * 1e18);
        assertEq(quote.balanceOf(address(lender)), 170_000 * 1e18);
        // check bucket balance
        (
            price,
            upPrice,
            downPrice,
            deposit,
            debt,
            snapshot,
            lpOutstanding,

        ) = pool.bucketAt(2000.221618840727700609 * 1e18);
        assertEq(price, 2000.221618840727700609 * 1e18);
        assertEq(upPrice, 4_000.927678580567537368 * 1e18);
        assertEq(downPrice, 0);
        assertEq(deposit, 20_000 * 1e45);
        assertEq(debt, 0);
        assertEq(snapshot, 1 * 1e18);
        assertEq(lpOutstanding, 20_000 * 1e27);
        assertEq(
            pool.lpBalance(address(lender), 2000.221618840727700609 * 1e18),
            20_000 * 1e27
        );
        // check hdp down price pointer updated
        (, upPrice, downPrice, , , , , ) = pool.bucketAt(
            4_000.927678580567537368 * 1e18
        );
        assertEq(upPrice, 4_000.927678580567537368 * 1e18);
        assertEq(downPrice, 2_000.221618840727700609 * 1e18);

        // test 30000 DAI deposit at price of 1 MKR = 3010.892022197881557845 DAI
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(lender), address(pool), 30_000 * 1e18);
        vm.expectEmit(true, true, false, true);
        emit AddQuoteToken(
            address(lender),
            3010.892022197881557845 * 1e18,
            30_000 * 1e45,
            0
        );
        lender.addQuoteToken(
            pool,
            address(lender),
            30_000 * 1e18,
            3010.892022197881557845 * 1e18
        );
        // check pool hdp and balances
        assertEq(pool.hdp(), 4_000.927678580567537368 * 1e18);
        assertEq(pool.totalQuoteToken(), 60_000 * 1e45);
        assertEq(quote.balanceOf(address(pool)), 60_000 * 1e18);
        assertEq(quote.balanceOf(address(lender)), 140_000 * 1e18);
        // check bucket balance
        (
            price,
            upPrice,
            downPrice,
            deposit,
            debt,
            snapshot,
            lpOutstanding,

        ) = pool.bucketAt(3010.892022197881557845 * 1e18);
        assertEq(price, 3010.892022197881557845 * 1e18);
        assertEq(upPrice, 4_000.927678580567537368 * 1e18);
        assertEq(downPrice, 2_000.221618840727700609 * 1e18);
        assertEq(deposit, 30_000 * 1e45);
        assertEq(debt, 0);
        assertEq(snapshot, 1 * 1e18);
        assertEq(lpOutstanding, 30_000 * 1e27);
        assertEq(
            pool.lpBalance(address(lender), 3010.892022197881557845 * 1e18),
            30_000 * 1e27
        );
        // check hdp down price pointer updated
        (, upPrice, downPrice, , , , , ) = pool.bucketAt(
            4_000.927678580567537368 * 1e18
        );
        assertEq(upPrice, 4_000.927678580567537368 * 1e18);
        assertEq(downPrice, 3010.892022197881557845 * 1e18);
        // check 2000 down price pointer updated
        (, upPrice, downPrice, , , , , ) = pool.bucketAt(
            2_000.221618840727700609 * 1e18
        );
        assertEq(upPrice, 3010.892022197881557845 * 1e18);
        assertEq(downPrice, 0);

        // test 40000 DAI deposit at price of 1 MKR = 5000 DAI
        // hdp should be updated to 5000 DAI and hdp next price should be 4000 DAI
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(lender), address(pool), 40_000 * 1e18);
        vm.expectEmit(true, true, false, true);
        emit AddQuoteToken(
            address(lender),
            5_007.644384905151472283 * 1e18,
            40_000 * 1e45,
            0
        );
        lender.addQuoteToken(
            pool,
            address(lender),
            40_000 * 1e18,
            5_007.644384905151472283 * 1e18
        );
        // check pool hdp and balances
        assertEq(pool.hdp(), 5_007.644384905151472283 * 1e18);
        assertEq(pool.totalQuoteToken(), 100_000 * 1e45);
        assertEq(quote.balanceOf(address(pool)), 100_000 * 1e18);
        assertEq(quote.balanceOf(address(lender)), 100_000 * 1e18);
        // check bucket balance
        (
            price,
            upPrice,
            downPrice,
            deposit,
            debt,
            snapshot,
            lpOutstanding,

        ) = pool.bucketAt(5_007.644384905151472283 * 1e18);
        assertEq(price, 5_007.644384905151472283 * 1e18);
        assertEq(upPrice, 5_007.644384905151472283 * 1e18);
        assertEq(downPrice, 4_000.927678580567537368 * 1e18);
        assertEq(deposit, 40_000 * 1e45);
        assertEq(debt, 0);
        assertEq(snapshot, 1 * 1e18);
        assertEq(lpOutstanding, 40_000 * 1e27);
        assertEq(
            pool.lpBalance(address(lender), 5_007.644384905151472283 * 1e18),
            40_000 * 1e27
        );
    }

    function testDepositQuoteTokenWithReallocation() public {
        // Lender deposits into three buckets
        lender.addQuoteToken(
            pool,
            address(lender),
            1_000 * 1e18,
            4_000.927678580567537368 * 1e18
        );
        lender.addQuoteToken(
            pool,
            address(lender),
            1_000 * 1e18,
            3_010.892022197881557845 * 1e18
        );
        lender.addQuoteToken(
            pool,
            address(lender),
            1_000 * 1e18,
            2_000.221618840727700609 * 1e18
        );

        // Borrower draws debt from all three
        borrower.addCollateral(pool, 10 * 1e18);
        borrower.borrow(pool, 2_400 * 1e18, 0);
        (, , , uint256 deposit, uint256 debt, , , ) = pool.bucketAt(
            4_000.927678580567537368 * 1e18
        );
        assertEq(deposit, 0);
        assertEq(debt, 1_000 * 1e45);
        (, , , deposit, debt, , , ) = pool.bucketAt(
            3_010.892022197881557845 * 1e18
        );
        assertEq(deposit, 0);
        assertEq(debt, 1_000 * 1e45);
        (, , , deposit, debt, , , ) = pool.bucketAt(
            2_000.221618840727700609 * 1e18
        );
        assertEq(deposit, 600 * 1e45);
        assertEq(debt, 400 * 1e45);

        // Lender deposits more into the middle bucket, causing reallocation
        lender.addQuoteToken(
            pool,
            address(lender),
            2_000 * 1e18,
            3_010.892022197881557845 * 1e18
        );
        (, , , deposit, debt, , , ) = pool.bucketAt(
            4_000.927678580567537368 * 1e18
        );
        assertEq(deposit, 0);
        assertEq(debt, 1_000 * 1e45);
        (, , , deposit, debt, , , ) = pool.bucketAt(
            3_010.892022197881557845 * 1e18
        );
        assertEq(deposit, 1_600 * 1e45);
        assertEq(debt, 1_400 * 1e45);
        (, , , deposit, debt, , , ) = pool.bucketAt(
            2_000.221618840727700609 * 1e18
        );
        assertEq(deposit, 1_000 * 1e45);
        assertEq(debt, 0);

        // Lender deposits in the top bucket, causing another reallocation
        lender.addQuoteToken(
            pool,
            address(lender),
            3_000 * 1e18,
            4_000.927678580567537368 * 1e18
        );
        (, , , deposit, debt, , , ) = pool.bucketAt(
            4_000.927678580567537368 * 1e18
        );
        assertEq(deposit, 1600 * 1e45);
        assertEq(debt, 2_400 * 1e45);
        (, , , deposit, debt, , , ) = pool.bucketAt(
            3_010.892022197881557845 * 1e18
        );
        assertEq(deposit, 3_000 * 1e45);
        assertEq(debt, 0);
        (, , , deposit, debt, , , ) = pool.bucketAt(
            2_000.221618840727700609 * 1e18
        );
        assertEq(deposit, 1_000 * 1e45);
        assertEq(debt, 0);
    }

    function testDepositQuoteTokenAtLup() public {
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

    function testRemoveQuoteTokenNoLoan() public {
        // lender deposit 10000 DAI at price 4000
        lender.addQuoteToken(
            pool,
            address(lender),
            10_000 * 1e18,
            4_000.927678580567537368 * 1e18
        );

        // should revert if trying to remove more than lended
        vm.expectRevert(
            abi.encodeWithSelector(
                Buckets.AmountExceedsClaimable.selector,
                10_000 * 1e45
            )
        );
        lender.removeQuoteToken(
            pool,
            address(lender),
            20_000 * 1e18,
            4_000.927678580567537368 * 1e18
        );

        skip(8200);

        // check balances before removal
        assertEq(pool.totalDebt(), 0);
        assertEq(pool.totalQuoteToken(), 10_000 * 1e45);

        (, , , uint256 deposit, uint256 debt, , uint256 lpOutstanding, ) = pool
            .bucketAt(4_000.927678580567537368 * 1e18);
        assertEq(deposit, 10_000 * 1e45);
        assertEq(debt, 0);
        assertEq(lpOutstanding, 10_000 * 1e27);
        assertEq(
            pool.lpBalance(address(lender), 4_000.927678580567537368 * 1e18),
            10_000 * 1e27
        );

        // remove 10000 DAI at price of 1 MKR = 4_000.927678580567537368 DAI
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(pool), address(lender), 10_000 * 1e18);
        vm.expectEmit(true, true, false, true);
        emit RemoveQuoteToken(
            address(lender),
            4_000.927678580567537368 * 1e18,
            10_000 * 1e45,
            0
        );
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
        (, , , deposit, debt, , lpOutstanding, ) = pool.bucketAt(
            4_000.927678580567537368 * 1e18
        );
        assertEq(deposit, 0 * 1e18);
        assertEq(debt, 0);
        assertEq(lpOutstanding, 0);
        assertEq(
            pool.lpBalance(address(lender), 4_000.927678580567537368 * 1e18),
            0
        );
    }

    function testRemoveQuoteTokenUnpaidLoan() public {
        // lender deposit 10000 DAI at price 4_000.927678580567537368
        lender.addQuoteToken(
            pool,
            address(lender),
            10_000 * 1e18,
            4_000.927678580567537368 * 1e18
        );
        assertEq(quote.balanceOf(address(lender)), 190_000 * 1e18);

        // check balances
        assertEq(quote.balanceOf(address(pool)), 10_000 * 1e18);
        assertEq(pool.totalQuoteToken(), 10_000 * 1e45);
        assertEq(quote.balanceOf(address(lender)), 190_000 * 1e18);
        assertEq(
            pool.lpBalance(address(lender), 4_000.927678580567537368 * 1e18),
            10_000 * 1e27
        );

        // borrower takes a loan of 5_000 DAI
        borrower.addCollateral(pool, 100 * 1e18);
        borrower.borrow(pool, 5_000 * 1e18, 4_000 * 1e18);

        // should revert if trying to remove entire amount lended
        vm.expectRevert(Buckets.NoDepositToReallocateTo.selector);
        lender.removeQuoteToken(
            pool,
            address(lender),
            10_000 * 1e18,
            4_000.927678580567537368 * 1e18
        );

        // confirm our LP balance still entitles us to our share of the utilized bucket
        assertEq(
            pool.lpBalance(address(lender), 4_000.927678580567537368 * 1e18),
            10_000 * 1e27
        );
        (uint256 collateralTokens, uint256 quoteTokens) = pool
            .getLPTokenExchangeValue(
                10_000 * 1e27,
                4_000.927678580567537368 * 1e18
            );
        assertEq(collateralTokens, 0);
        assertEq(quoteTokens, 10_000 * 1e45);

        // remove 4000 DAI at price of 1 MKR = 4_000.927678580567537368 DAI
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(pool), address(lender), 4_000 * 1e18);
        vm.expectEmit(true, true, false, true);
        emit RemoveQuoteToken(
            address(lender),
            4_000.927678580567537368 * 1e18,
            4_000 * 1e45,
            4_000.927678580567537368 * 1e18
        );
        lender.removeQuoteToken(
            pool,
            address(lender),
            4_000 * 1e18,
            4_000.927678580567537368 * 1e18
        );

        // check pool balances
        assertEq(pool.totalQuoteToken(), 1_000 * 1e45);
        assertEq(quote.balanceOf(address(pool)), 1_000 * 1e18);
        // check lender balance
        assertEq(quote.balanceOf(address(lender)), 194_000 * 1e18);

        // check 4000 bucket balance
        (, , , uint256 deposit, uint256 debt, , uint256 lpOutstanding, ) = pool
            .bucketAt(4_000.927678580567537368 * 1e18);
        assertEq(deposit, 1_000 * 1e45);
        assertEq(debt, 5_000 * 1e45);
        assertEq(lpOutstanding, 6_000 * 1e27);
        assertEq(
            pool.lpBalance(address(lender), 4_000.927678580567537368 * 1e18),
            6_000 * 1e27
        );
    }

    function testRemoveQuoteTokenPaidLoan() public {
        // lender deposit 10000 DAI at price 4000
        lender.addQuoteToken(
            pool,
            address(lender),
            10_000 * 1e18,
            4_000.927678580567537368 * 1e18
        );
        assertEq(quote.balanceOf(address(lender)), 190_000 * 1e18);

        // lender1 deposit 10000 DAI at price 4000:
        lender1.addQuoteToken(
            pool,
            address(lender1),
            10_000 * 1e18,
            4_000.927678580567537368 * 1e18
        );
        assertEq(quote.balanceOf(address(lender1)), 190_000 * 1e18);

        // borrower takes a loan of 10_000 DAI
        borrower.addCollateral(pool, 100 * 1e18);
        borrower.borrow(pool, 10_000 * 1e18, 4_000 * 1e18);
        assertEq(pool.lup(), 4_000.927678580567537368 * 1e18);

        // borrower repay entire loan
        quote.mint(address(borrower), 1 * 1e18);
        borrower.approveToken(quote, address(pool), 100_000 * 1e18);

        borrower.repay(pool, 10_001 * 1e18);

        skip(8200);

        //exchange rate
        //TODO: Get the exchange rate and calculate automatically
        vm.expectRevert(
            abi.encodeWithSelector(
                Buckets.AmountExceedsClaimable.selector,
                10_000 * 1e45
            )
        );
        lender1.removeQuoteToken(
            pool,
            address(lender1),
            15_000 * 1e18,
            4_000.927678580567537368 * 1e18
        );

        lender1.removeQuoteToken(
            pool,
            address(lender1),
            10_000 * 1e18,
            4_000.927678580567537368 * 1e18
        );

        // lender removes entire amount lended
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(pool), address(lender), 10_000 * 1e18);
        vm.expectEmit(true, true, false, true);
        emit RemoveQuoteToken(
            address(lender),
            4_000.927678580567537368 * 1e18,
            10_000 * 1e45,
            4_000.927678580567537368 * 1e18
        );
        lender.removeQuoteToken(
            pool,
            address(lender),
            10_000 * 1e18,
            4_000.927678580567537368 * 1e18
        );

        // check pool balances
        assertEq(pool.totalQuoteToken(), 0);
        assertEq(quote.balanceOf(address(pool)), 0);
        // check lender balance
        assertEq(quote.balanceOf(address(lender)), 200_000 * 1e18);

        // check 4000 bucket balance
        (, , , uint256 deposit, uint256 debt, , , ) = pool.bucketAt(
            4_000.927678580567537368 * 1e18
        );
        assertEq(deposit, 0);
        assertEq(debt, 0);
    }

    function testRemoveQuoteTokenWithDebtReallocation() public {
        // lender deposit 3_400 DAI in 2 buckets
        lender.addQuoteToken(
            pool,
            address(lender),
            3_400 * 1e18,
            4_000.927678580567537368 * 1e18
        );
        lender.addQuoteToken(
            pool,
            address(lender),
            3_400 * 1e18,
            3_010.892022197881557845 * 1e18
        );

        // borrower takes a loan of 3000 DAI
        borrower.addCollateral(pool, 100 * 1e18);
        borrower.borrow(pool, 3_000 * 1e18, 4_000 * 1e18);
        assertEq(pool.lup(), 4_000.927678580567537368 * 1e18);
        (, , , uint256 deposit, uint256 debt, , uint256 lpOutstanding, ) = pool
            .bucketAt(4_000.927678580567537368 * 1e18);
        assertEq(deposit, 400 * 1e45);
        assertEq(debt, 3_000 * 1e45);
        (, , , deposit, debt, , , ) = pool.bucketAt(
            3_010.892022197881557845 * 1e18
        );
        assertEq(deposit, 3_400 * 1e45);
        assertEq(debt, 0);

        // lender removes 1000 DAI from lup
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(pool), address(lender), 1_000 * 1e18);
        vm.expectEmit(true, true, false, true);
        emit RemoveQuoteToken(
            address(lender),
            4_000.927678580567537368 * 1e18,
            1_000 * 1e45,
            3_010.892022197881557845 * 1e18
        );
        lender.removeQuoteToken(
            pool,
            address(lender),
            1_000 * 1e18,
            4_000.927678580567537368 * 1e18
        );

        // check lup moved down to 3000
        assertEq(pool.lup(), 3_010.892022197881557845 * 1e18);
        // check pool balances
        assertEq(pool.totalQuoteToken(), 2_800 * 1e45);
        assertEq(pool.totalDebt(), 3_000 * 1e45);
        assertEq(quote.balanceOf(address(pool)), 2_800 * 1e18);
        // check lender balance
        assertEq(quote.balanceOf(address(lender)), 194_200 * 1e18);

        // check 4000 bucket balance
        (, , , deposit, debt, , lpOutstanding, ) = pool.bucketAt(
            4_000.927678580567537368 * 1e18
        );
        assertEq(deposit, 0);
        assertEq(debt, 2_400 * 1e45);
        assertEq(lpOutstanding, 2_400 * 1e27);
        assertEq(
            pool.lpBalance(address(lender), 4_000.927678580567537368 * 1e18),
            2_400 * 1e27
        );

        // check 3_010.892022197881557845 bucket balance
        (, , , deposit, debt, , lpOutstanding, ) = pool.bucketAt(
            3_010.892022197881557845 * 1e18
        );
        assertEq(deposit, 2_800 * 1e45);
        assertEq(debt, 600 * 1e45);
        assertEq(lpOutstanding, 3_400 * 1e27);
        assertEq(
            pool.lpBalance(address(lender), 3_010.892022197881557845 * 1e18),
            3_400 * 1e27
        );
    }

    function testRemoveQuoteTokenEntirelyWithDebt() public {
        // lender deposit into 2 buckets
        lender.addQuoteToken(
            pool,
            address(lender),
            1_000 * 1e18,
            4_000.927678580567537368 * 1e18
        );
        lender.addQuoteToken(
            pool,
            address(lender),
            2_000 * 1e18,
            4_000.927678580567537368 * 1e18
        );
        skip(14);
        lender.addQuoteToken(
            pool,
            address(lender),
            6_000 * 1e18,
            3_010.892022197881557845 * 1e18
        );
        skip(1340);

        // borrower takes a loan of 4000 DAI
        borrower.addCollateral(pool, 100 * 1e18);
        borrower.borrow(pool, 4_000 * 1e18, 0);
        (, , , uint256 deposit, uint256 debt, , uint256 lpOutstanding, ) = pool
            .bucketAt(4_000.927678580567537368 * 1e18);
        assertEq(deposit, 0);
        assertEq(debt, 3_000 * 1e45);
        assertEq(lpOutstanding, 3_000 * 1e27);
        (, , , deposit, debt, , lpOutstanding, ) = pool.bucketAt(
            3_010.892022197881557845 * 1e18
        );
        assertEq(deposit, 5_000 * 1e45);
        assertEq(debt, 1_000 * 1e45);
        assertEq(lpOutstanding, 6_000 * 1e27);
        skip(1340);

        // lender removes entire bid from 4_000.927678580567537368 bucket
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(pool), address(lender), 3_000 * 1e18);
        emit RemoveQuoteToken(
            address(lender),
            4_000.927678580567537368 * 1e18,
            3_000 * 1e45,
            4_000.927678580567537368 * 1e18
        );
        lender.removeQuoteToken(
            pool,
            address(lender),
            3_000 * 1e18,
            4_000.927678580567537368 * 1e18
        );

        // confirm debt was reallocated
        (, , , deposit, debt, , lpOutstanding, ) = pool.bucketAt(
            3_010.892022197881557845 * 1e18
        );
        assertEq(deposit, 2_000 * 1e45);
        // some debt accumulated between loan and reallocation
        assertEq(debt, 4_000.002124558305730000 * 1e45);
    }

    function testRemoveQuoteTokenBelowLup() public {
        // lender deposit 5000 DAI in 3 buckets
        lender.addQuoteToken(
            pool,
            address(lender),
            5_000 * 1e18,
            4_000.927678580567537368 * 1e18
        );
        lender.addQuoteToken(
            pool,
            address(lender),
            5_000 * 1e18,
            3_010.892022197881557845 * 1e18
        );
        lender.addQuoteToken(
            pool,
            address(lender),
            5_000 * 1e18,
            2_000.221618840727700609 * 1e18
        );

        // borrower takes a loan of 3000 DAI
        borrower.addCollateral(pool, 100 * 1e18);
        borrower.borrow(pool, 3_010.892022197881557845 * 1e18, 4_000 * 1e18);
        assertEq(pool.lup(), 4_000.927678580567537368 * 1e18);

        // lender removes 1000 DAI under the lup - from bucket 3000
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(pool), address(lender), 1_000 * 1e18);
        vm.expectEmit(true, true, false, true);
        emit RemoveQuoteToken(
            address(lender),
            3_010.892022197881557845 * 1e18,
            1_000 * 1e45,
            4_000.927678580567537368 * 1e18
        );
        lender.removeQuoteToken(
            pool,
            address(lender),
            1_000 * 1e18,
            3_010.892022197881557845 * 1e18
        );

        // check same lup
        assertEq(pool.lup(), 4_000.927678580567537368 * 1e18);
        // check pool balances
        assertEq(pool.totalQuoteToken(), 10_989.107977802118442155 * 1e45);
        assertEq(
            quote.balanceOf(address(pool)),
            10_989.107977802118442155 * 1e18
        );

        // check 4000 bucket balance
        (, , , uint256 deposit, uint256 debt, , uint256 lpOutstanding, ) = pool
            .bucketAt(4_000.927678580567537368 * 1e18);
        assertEq(deposit, 1_989.107977802118442155 * 1e45);
        assertEq(debt, 3_010.892022197881557845 * 1e45);
        assertEq(lpOutstanding, 5_000 * 1e27);
        assertEq(
            pool.lpBalance(address(lender), 4_000.927678580567537368 * 1e18),
            5_000 * 1e27
        );

        // check 3_010.892022197881557845 bucket balance, should have less 1000 DAI and lp token
        (, , , deposit, debt, , lpOutstanding, ) = pool.bucketAt(
            3_010.892022197881557845 * 1e18
        );
        assertEq(deposit, 4_000 * 1e45);
        assertEq(debt, 0);
        assertEq(lpOutstanding, 4_000 * 1e27);
        assertEq(
            pool.lpBalance(address(lender), 3_010.892022197881557845 * 1e18),
            4_000 * 1e27
        );
    }

    function testRemoveQuoteUndercollateralizedPool() public {
        // lender deposit 5000 DAI in 2 spaced buckets
        lender.addQuoteToken(
            pool,
            address(lender),
            5_000 * 1e18,
            1_004.989662429170775094 * 1e18
        );
        lender.addQuoteToken(
            pool,
            address(lender),
            5_000 * 1e18,
            100.332368143282009890 * 1e18
        );

        // borrower takes a loan of 4000 DAI
        borrower.addCollateral(pool, 5.1 * 1e18);
        borrower.borrow(pool, 4_000 * 1e18, 1_000 * 1e18);
        assertEq(pool.lup(), 1_004.989662429170775094 * 1e18);

        // removal should revert if pool remains undercollateralized
        vm.expectRevert(
            abi.encodeWithSelector(
                ERC20Pool.PoolUndercollateralized.selector,
                0.127923769382684562609750000 * 1e27
            )
        );
        lender.removeQuoteToken(
            pool,
            address(lender),
            2_000 * 1e18,
            1_004.989662429170775094 * 1e18
        );
    }

    function testRemoveQuoteMultipleLenders() public {
        assertEq(quote.balanceOf(address(lender)), 200_000 * 1e18);
        assertEq(quote.balanceOf(address(lender1)), 200_000 * 1e18);
        assertEq(quote.balanceOf(address(pool)), 0);

        (, , , , , , uint256 lpOutstanding, ) = pool.bucketAt(
            1_004.989662429170775094 * 1e18
        );
        assertEq(lpOutstanding, 0);

        assertEq(
            pool.lpBalance(address(lender), 1_004.989662429170775094 * 1e18),
            0
        );
        assertEq(
            pool.lpBalance(address(lender1), 1_004.989662429170775094 * 1e18),
            0
        );

        // lender1 deposit 10000 DAI
        lender.addQuoteToken(
            pool,
            address(lender),
            10_000 * 1e18,
            1_004.989662429170775094 * 1e18
        );
        // lender1 deposit 10000 DAI in same bucket
        lender1.addQuoteToken(
            pool,
            address(lender1),
            10_000 * 1e18,
            1_004.989662429170775094 * 1e18
        );

        assertEq(quote.balanceOf(address(lender)), 190_000 * 1e18);
        assertEq(quote.balanceOf(address(lender1)), 190_000 * 1e18);
        assertEq(quote.balanceOf(address(pool)), 20_000 * 1e18);

        assertEq(
            pool.lpBalance(address(lender), 1_004.989662429170775094 * 1e18),
            10_000 * 1e27
        );
        assertEq(
            pool.lpBalance(address(lender1), 1_004.989662429170775094 * 1e18),
            10_000 * 1e27
        );

        (, , , , , , lpOutstanding, ) = pool.bucketAt(
            1_004.989662429170775094 * 1e18
        );
        assertEq(lpOutstanding, 20_000 * 1e27);

        skip(8200);

        lender.removeQuoteToken(
            pool,
            address(lender),
            10_000 * 1e18,
            1_004.989662429170775094 * 1e18
        );
        assertEq(
            pool.lpBalance(address(lender), 1_004.989662429170775094 * 1e18),
            0
        );
        assertEq(
            pool.lpBalance(address(lender1), 1_004.989662429170775094 * 1e18),
            10_000 * 1e27
        );
        (, , , , , , lpOutstanding, ) = pool.bucketAt(
            1_004.989662429170775094 * 1e18
        );
        assertEq(lpOutstanding, 10_000 * 1e27);

        lender1.removeQuoteToken(
            pool,
            address(lender1),
            10_000 * 1e18,
            1_004.989662429170775094 * 1e18
        );

        assertEq(quote.balanceOf(address(lender)), 200_000 * 1e18);
        assertEq(quote.balanceOf(address(lender1)), 200_000 * 1e18);
        assertEq(quote.balanceOf(address(pool)), 0);

        assertEq(
            pool.lpBalance(address(lender), 1_004.989662429170775094 * 1e18),
            0
        );
        assertEq(
            pool.lpBalance(address(lender1), 1_004.989662429170775094 * 1e18),
            0
        );
        (, , , , , , lpOutstanding, ) = pool.bucketAt(
            1_004.989662429170775094 * 1e18
        );
        assertEq(lpOutstanding, 0);
    }
}
