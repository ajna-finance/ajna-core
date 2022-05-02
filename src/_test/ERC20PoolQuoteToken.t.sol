// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.11;

import { ERC20Pool }        from "../ERC20Pool.sol";
import { ERC20PoolFactory } from "../ERC20PoolFactory.sol";

import { IPool } from "../interfaces/IPool.sol";

import "../libraries/Buckets.sol";

import { DSTestPlus }                             from "./utils/DSTestPlus.sol";
import { CollateralToken, QuoteToken }            from "./utils/Tokens.sol";
import { UserWithCollateral, UserWithQuoteToken } from "./utils/Users.sol";

contract ERC20PoolQuoteTokenTest is DSTestPlus {

    uint256 public constant LARGEST_AMOUNT = type(uint256).max / 10**27;

    CollateralToken    internal _collateral;
    ERC20Pool          internal _pool;
    QuoteToken         internal _quote;
    UserWithCollateral internal _borrower;
    UserWithCollateral internal _borrower2;
    UserWithQuoteToken internal _lender;
    UserWithQuoteToken internal _lender1;

    function setUp() external {
        _collateral = new CollateralToken();
        _quote      = new QuoteToken();
        _pool       = new ERC20PoolFactory().deployPool(address(_collateral), address(_quote));
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

    // TODO: Review each test and validate HPB and LUP are correct where appropriate.

    // @notice: 1 lender tests adding quote token
    // @notice: lender Reverts:
    // @notice:     attempts to addQuoteToken at invalid price
    function testDepositQuoteToken() external {
        // should revert when depositing at invalid price
        vm.expectRevert(IPool.InvalidPrice.selector);
        _lender.addQuoteToken(_pool, address(_lender), 10_000 * 1e18, 10_049.48314 * 1e18);

        assertEq(_pool.hpb(), 0);
        assertEq(_pool.lup(), 0);

        // test 10000 DAI deposit at price of 1 MKR = 4000 DAI
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(_lender), address(_pool), 10_000 * 1e18);
        vm.expectEmit(true, true, false, true);
        emit AddQuoteToken(address(_lender), _p4000, 10_000 * 1e45, 0);
        _lender.addQuoteToken(_pool, address(_lender), 10_000 * 1e18, _p4000);

        // check pool prices and balances
        assertEq(_pool.hpb(),                        _p4000);
        assertEq(_pool.lup(),                        0);
        assertEq(_pool.totalQuoteToken(),            10_000 * 1e45);
        assertEq(_quote.balanceOf(address(_pool)),   10_000 * 1e18);
        assertEq(_quote.balanceOf(address(_lender)), 190_000 * 1e18);

        // check bucket balance
        (
            uint256 price,
            uint256 upPrice,
            uint256 downPrice,
            uint256 deposit,
            uint256 debt,
            uint256 snapshot,
            uint256 lpOutstanding,

        ) = _pool.bucketAt(_p4000);
        assertEq(price,         _p4000);
        assertEq(upPrice,       _p4000);
        assertEq(downPrice,     0);
        assertEq(deposit,       10_000 * 1e45);
        assertEq(debt,          0);
        assertEq(snapshot,      1 * 1e27);
        assertEq(lpOutstanding, 10_000 * 1e27);

        // check lender's LP amount can be redeemed for correct amount of quote token
        assertEq(_pool.lpBalance(address(_lender), _p4000), 10_000 * 1e27);
        (uint256 collateralTokens, uint256 quoteTokens) = _pool.getLPTokenExchangeValue(
            10_000 * 1e27,
            _p4000
        );
        assertEq(collateralTokens,  0);
        assertEq(quoteTokens,       10_000 * 1e45);

        // test 20000 DAI deposit at price of 1 MKR = 2000.221618840727700609 DAI
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(_lender), address(_pool), 20_000 * 1e18);
        vm.expectEmit(true, true, false, true);
        emit AddQuoteToken(address(_lender), _p2000, 20_000 * 1e45, 0);
        _lender.addQuoteToken(_pool, address(_lender), 20_000 * 1e18, _p2000);

        // check pool hbp and balances
        assertEq(_pool.hpb(),                        _p4000);
        assertEq(_pool.totalQuoteToken(),            30_000 * 1e45);
        assertEq(_quote.balanceOf(address(_pool)),   30_000 * 1e18);
        assertEq(_quote.balanceOf(address(_lender)), 170_000 * 1e18);

        // check bucket balance
        (price, upPrice, downPrice, deposit, debt, snapshot, lpOutstanding, ) = _pool.bucketAt(_p2000);
        assertEq(price,         _p2000);
        assertEq(upPrice,       _p4000);
        assertEq(downPrice,     0);
        assertEq(deposit,       20_000 * 1e45);
        assertEq(debt,          0);
        assertEq(snapshot,      1 * 1e27);
        assertEq(lpOutstanding, 20_000 * 1e27);

        assertEq(_pool.lpBalance(address(_lender), _p2000), 20_000 * 1e27);

        // check hpb down price pointer updated
        (, upPrice, downPrice, , , , , ) = _pool.bucketAt(_p4000);
        assertEq(upPrice,   _p4000);
        assertEq(downPrice, _p2000);

        // test 30000 DAI deposit at price of 1 MKR = 3010.892022197881557845 DAI
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(_lender), address(_pool), 30_000 * 1e18);
        vm.expectEmit(true, true, false, true);
        emit AddQuoteToken(address(_lender), _p3010, 30_000 * 1e45, 0);
        _lender.addQuoteToken(_pool, address(_lender), 30_000 * 1e18, _p3010);

        // check pool hbp and balances
        assertEq(_pool.hpb(),                        _p4000);
        assertEq(_pool.totalQuoteToken(),            60_000 * 1e45);
        assertEq(_quote.balanceOf(address(_pool)),   60_000 * 1e18);
        assertEq(_quote.balanceOf(address(_lender)), 140_000 * 1e18);

        // check bucket balance
        (price, upPrice, downPrice, deposit, debt, snapshot, lpOutstanding, ) = _pool.bucketAt(_p3010);
        assertEq(price,         _p3010);
        assertEq(upPrice,       _p4000);
        assertEq(downPrice,     _p2000);
        assertEq(deposit,       30_000 * 1e45);
        assertEq(debt,          0);
        assertEq(snapshot,      1 * 1e27);
        assertEq(lpOutstanding, 30_000 * 1e27);

        assertEq(_pool.lpBalance(address(_lender), _p3010), 30_000 * 1e27);

        // check hdp down price pointer updated
        (, upPrice, downPrice, , , , , ) = _pool.bucketAt(_p4000);
        assertEq(upPrice,   _p4000);
        assertEq(downPrice, _p3010);

        // check 2000 down price pointer updated
        (, upPrice, downPrice, , , , , ) = _pool.bucketAt(_p2000);
        assertEq(upPrice,   3010.892022197881557845 * 1e18);
        assertEq(downPrice, 0);

        // test 40000 DAI deposit at price of 1 MKR = 5000 DAI
        // hbp should be updated to 5000 DAI and hbp next price should be 4000 DAI
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(_lender), address(_pool), 40_000 * 1e18);
        vm.expectEmit(true, true, false, true);
        emit AddQuoteToken(address(_lender), _p5007, 40_000 * 1e45, 0);
        _lender.addQuoteToken(_pool, address(_lender), 40_000 * 1e18, _p5007);

        // check pool hbp and balances
        assertEq(_pool.hpb(),             _p5007);
        assertEq(_pool.lup(),             0);
        assertEq(_pool.totalQuoteToken(), 100_000 * 1e45);

        assertEq(_quote.balanceOf(address(_pool)),   100_000 * 1e18);
        assertEq(_quote.balanceOf(address(_lender)), 100_000 * 1e18);

        // check bucket balance
        (price, upPrice, downPrice, deposit, debt, snapshot, lpOutstanding, ) = _pool.bucketAt(_p5007);
        assertEq(price,         _p5007);
        assertEq(upPrice,       _p5007);
        assertEq(downPrice,     _p4000);
        assertEq(deposit,       40_000 * 1e45);
        assertEq(debt,          0);
        assertEq(snapshot,      1 * 1e27);
        assertEq(lpOutstanding, 40_000 * 1e27);

        assertEq(_pool.lpBalance(address(_lender), _p5007), 40_000 * 1e27);
    }

    // @notice: 1 lender and 1 borrower test adding quote token
    // @notice: borrowing then reallocating twice by depositing above the lup
    function testDepositQuoteTokenWithReallocation() external {
        // Lender deposits into three buckets
        _lender.addQuoteToken(_pool, address(_lender), 1_000 * 1e18, _p4000);
        _lender.addQuoteToken(_pool, address(_lender), 1_000 * 1e18, _p3010);
        _lender.addQuoteToken(_pool, address(_lender), 1_000 * 1e18, _p2000);

        // Borrower draws debt from all three
        _borrower.addCollateral(_pool, 10 * 1e18);
        _borrower.borrow(_pool, 2_400 * 1e18, 0);
        (, , , uint256 deposit, uint256 debt, , , ) = _pool.bucketAt(_p4000);
        assertEq(deposit, 0);
        assertEq(debt,    1_000 * 1e45);
        (, , , deposit, debt, , , ) = _pool.bucketAt(_p3010);
        assertEq(deposit, 0);
        assertEq(debt,    1_000 * 1e45);
        (, , , deposit, debt, , , ) = _pool.bucketAt(_p2000);
        assertEq(deposit, 600 * 1e45);
        assertEq(debt,    400 * 1e45);

        assertEq(_pool.hpb(), _p4000);
        assertEq(_pool.lup(), _p2000);

        uint256 collateralizationBeforeAdd = _pool.getPoolCollateralization();
        uint256 targetUtilizationBeforeAdd = _pool.getPoolTargetUtilization();
        uint256 actualUtilizationBeforeAdd = _pool.getPoolActualUtilization();

        // Lender deposits more into the middle bucket, causing reallocation
        _lender.addQuoteToken(_pool, address(_lender), 2_000 * 1e18, _p3010);
        (, , , deposit, debt, , , ) = _pool.bucketAt(_p4000);
        assertEq(deposit, 0);
        assertEq(debt,    1_000 * 1e45);

        (, , , deposit, debt, , , ) = _pool.bucketAt(_p3010);
        assertEq(deposit, 1_600 * 1e45);
        assertEq(debt,    1_400 * 1e45);

        (, , , deposit, debt, , , ) = _pool.bucketAt(_p2000);
        assertEq(deposit, 1_000 * 1e45);
        assertEq(debt,    0);

        assertEq(_pool.hpb(), _p4000);
        assertEq(_pool.lup(), _p3010);

        assertGt(_pool.getPoolCollateralization(), collateralizationBeforeAdd);
        assertLt(_pool.getPoolTargetUtilization(), targetUtilizationBeforeAdd);
        assertLt(_pool.getPoolActualUtilization(), actualUtilizationBeforeAdd);

        // Lender deposits in the top bucket, causing another reallocation
        collateralizationBeforeAdd = _pool.getPoolCollateralization();
        targetUtilizationBeforeAdd = _pool.getPoolTargetUtilization();
        actualUtilizationBeforeAdd = _pool.getPoolActualUtilization();

        _lender.addQuoteToken(_pool, address(_lender), 3_000 * 1e18, _p4000);
        (, , , deposit, debt, , , ) = _pool.bucketAt(_p4000);
        assertEq(deposit, 1600 * 1e45);
        assertEq(debt,    2_400 * 1e45);

        (, , , deposit, debt, , , ) = _pool.bucketAt(_p3010);
        assertEq(deposit, 3_000 * 1e45);
        assertEq(debt,    0);

        (, , , deposit, debt, , , ) = _pool.bucketAt(_p2000);
        assertEq(deposit, 1_000 * 1e45);
        assertEq(debt,    0);

        assertEq(_pool.hpb(), _p4000);
        assertEq(_pool.lup(), _p4000);

        assertGt(_pool.getPoolCollateralization(), collateralizationBeforeAdd);
        assertLt(_pool.getPoolTargetUtilization(), targetUtilizationBeforeAdd);
        assertLt(_pool.getPoolActualUtilization(), actualUtilizationBeforeAdd);
    }

    // @notice: 1 lender and 1 borrower test adding quote token,
    // @notice: borowing all liquidity then adding quote token above the lup
    function testDepositAboveLupWithLiquidityGapBetweenLupAndNextUnutilizedBucket() external {
        // When a user deposits above the LUP, debt is reallocated upward.
        // LUP should update when debt is reallocated upward such that the new
        // LUP has jumped across a liquidity gap.

        // Lender deposits in three of the four buckets, leaving a liquidity gap
        _lender.addQuoteToken(_pool, address(_lender), 1_000 * 1e18, _p2821);
        _lender.addQuoteToken(_pool, address(_lender), 1_000 * 1e18, _p2807);
        _lender.addQuoteToken(_pool, address(_lender), 1_000 * 1e18, _p2779);

        // Borrower draws debt utilizing all buckets with liquidity
        _borrower.addCollateral(_pool, 10 * 1e18);
        _borrower.borrow(_pool, 2_100 * 1e18, 0);
        (, , , uint256 deposit, uint256 debt, , , ) = _pool.bucketAt(_p2779);
        assertEq(deposit, 900 * 1e45);
        assertEq(debt,    100 * 1e45);

        assertEq(_pool.hpb(), _p2821);
        assertEq(_pool.lup(), _p2779);

        // Lender deposits above the gap, pushing up the LUP
        _lender.addQuoteToken(_pool, address(_lender), 500 * 1e18, _p2807);
        (, , , deposit, debt, , , ) = _pool.bucketAt(_p2821);
        assertEq(deposit, 0);
        assertEq(debt,    1_000 * 1e45);

        (, , , deposit, debt, , , ) = _pool.bucketAt(_p2807);
        assertEq(deposit, 400 * 1e45);
        assertEq(debt,    1_100 * 1e45);

        (, , , deposit, debt, , , ) = _pool.bucketAt(_p2793);
        assertEq(deposit, 0);
        assertEq(debt,    0);

        (, , , deposit, debt, , , ) = _pool.bucketAt(_p2779);
        assertEq(deposit, 1_000 * 1e45);
        assertEq(debt,    0);

        assertEq(_pool.hpb(), _p2821);
        assertEq(_pool.lup(), _p2807);
    }

    // @notice: 1 lender and 1 borrower test adding quote token,
    // @notice: borowing all liquidity at LUP then adding quote token at the LUP
    function testDepositQuoteTokenAtLup() external {
         // Lender deposits 1000 in each bucket
        _lender.addQuoteToken(_pool, address(_lender), 1_000 * 1e18, _p2850);
        _lender.addQuoteToken(_pool, address(_lender), 1_000 * 1e18, _p2835);
        _lender.addQuoteToken(_pool, address(_lender), 1_000 * 1e18, _p2821);
        _lender.addQuoteToken(_pool, address(_lender), 1_000 * 1e18, _p2807);

        // Borrower draws 2000 debt fully utilizing the LUP
        _borrower.addCollateral(_pool, 10 * 1e18);
        _borrower.borrow(_pool, 2_000 * 1e18, 0);
        (, , , uint256 deposit, uint256 debt, , , ) = _pool.bucketAt(_p2850);
        assertEq(deposit, 0);
        assertEq(debt,    1_000 * 1e45);

        (, , , deposit, debt, , , ) = _pool.bucketAt(_p2835);
        assertEq(deposit, 0);
        assertEq(debt,    1_000 * 1e45);

        (, , , deposit, debt, , , ) = _pool.bucketAt(_p2821);
        assertEq(deposit, 1_000 * 1e45);
        assertEq(debt,    0);

        (, , , deposit, debt, , , ) = _pool.bucketAt(_p2807);
        assertEq(deposit, 1_000 * 1e45);
        assertEq(debt,    0);

        assertEq(_pool.hpb(), _p2850);
        assertEq(_pool.lup(), _p2835);

        // Lender deposits 1400 at LUP
        _lender.addQuoteToken(_pool, address(_lender1), 1_400 * 1e18, _p2835);
        (, , , deposit, debt, , , ) = _pool.bucketAt(_p2850);
        assertEq(deposit, 0);
        assertEq(debt,    1_000 * 1e45);

        (, , , deposit, debt, , , ) = _pool.bucketAt(_p2835);
        assertEq(deposit, 1_400 * 1e45);
        assertEq(debt,    1_000 * 1e45);

        (, , , deposit, debt, , , ) = _pool.bucketAt(_p2821);
        assertEq(deposit, 1_000 * 1e45);
        assertEq(debt,    0);

        (, , , deposit, debt, , , ) = _pool.bucketAt(_p2807);
        assertEq(deposit, 1_000 * 1e45);
        assertEq(debt,    0);

        assertEq(_pool.hpb(), _p2850);
        assertEq(_pool.lup(), _p2835);
    }

    // @notice: 1 lender deposits quote token then removes quote token
    // @notice: with no loans outstanding
    function testRemoveQuoteTokenNoLoan() external {
        // lender deposit 10000 DAI at price 4000
        _lender.addQuoteToken(_pool, address(_lender), 10_000 * 1e18, _p4000);
        skip(8200);

        // check balances before removal
        assertEq(_pool.totalDebt(),       0);
        assertEq(_pool.totalQuoteToken(), 10_000 * 1e45);

        (, , , uint256 deposit, uint256 debt, , uint256 lpOutstanding, ) = _pool.bucketAt(_p4000);
        assertEq(deposit,       10_000 * 1e45);
        assertEq(debt,          0);
        assertEq(lpOutstanding, 10_000 * 1e27);

        assertEq(_pool.lpBalance(address(_lender), _p4000), 10_000 * 1e27);

        assertEq(_pool.hpb(), _p4000);
        assertEq(_pool.lup(), 0);

        // remove 10000 DAI at price of 1 MKR = 4_000.927678580567537368 DAI
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(_pool), address(_lender), 10_000 * 1e18);
        vm.expectEmit(true, true, false, true);
        emit RemoveQuoteToken(address(_lender), _p4000, 10_000 * 1e45, 0);
        _lender.removeQuoteToken(_pool, address(_lender), 10_000 * 1e18, _p4000);

        // check balances after removal
        assertEq(_pool.totalDebt(),       0);
        assertEq(_pool.totalQuoteToken(), 0);

        // check 4000 bucket balance
        (, , , deposit, debt, , lpOutstanding, ) = _pool.bucketAt(_p4000);
        assertEq(deposit,       0 * 1e18);
        assertEq(debt,          0);
        assertEq(lpOutstanding, 0);

        assertEq(_pool.lpBalance(address(_lender), _p4000), 0);

        assertEq(_pool.hpb(), 0);
        assertEq(_pool.lup(), 0);
    }

    // @notice: 1 lender deposits quote token then removes quote token
    // @notice: with an unpaid loan outstanding
    // @notice: lender reverts:
    // @notice:         attempts to remove more quote token then lent out
    function testRemoveQuoteTokenUnpaidLoan() external {
        // lender deposit 10000 DAI at price 4_000.927678580567537368
        _lender.addQuoteToken(_pool, address(_lender), 10_000 * 1e18, _p4000);

        // check balances
        assertEq(_quote.balanceOf(address(_pool)),          10_000 * 1e18);
        assertEq(_pool.totalQuoteToken(),                   10_000 * 1e45);
        assertEq(_quote.balanceOf(address(_lender)),        190_000 * 1e18);
        assertEq(_pool.lpBalance(address(_lender), _p4000), 10_000 * 1e27);

        // borrower takes a loan of 5_000 DAI
        _borrower.addCollateral(_pool, 100 * 1e18);
        _borrower.borrow(_pool, 5_000 * 1e18, 4_000 * 1e18);

        // should revert if trying to remove entire amount lended
        vm.expectRevert(Buckets.NoDepositToReallocateTo.selector);
        _lender.removeQuoteToken(_pool, address(_lender), 10_000 * 1e18, _p4000);

        // confirm our LP balance still entitles us to our share of the utilized bucket
        assertEq(_pool.lpBalance(address(_lender), _p4000), 10_000 * 1e27);
        (uint256 collateralTokens, uint256 quoteTokens) = _pool.getLPTokenExchangeValue(
            10_000 * 1e27,
            _p4000
        );
        assertEq(collateralTokens, 0);
        assertEq(quoteTokens,      10_000 * 1e45);

        // check price pointers
        assertEq(_pool.hpb(), _p4000);
        assertEq(_pool.lup(), _p4000);

        // remove 4000 DAI at price of 1 MKR = 4_000.927678580567537368 DAI
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(_pool), address(_lender), 4_000 * 1e18);
        vm.expectEmit(true, true, false, true);
        emit RemoveQuoteToken(address(_lender), _p4000, 4_000 * 1e45, _p4000);
        _lender.removeQuoteToken(_pool, address(_lender), 4_000 * 1e18, _p4000);

        // check pool balances
        assertEq(_pool.totalQuoteToken(),          1_000 * 1e45);
        assertEq(_quote.balanceOf(address(_pool)), 1_000 * 1e18);

        // check lender balance
        assertEq(_quote.balanceOf(address(_lender)), 194_000 * 1e18);

        // check 4000 bucket balance
        (, , , uint256 deposit, uint256 debt, , uint256 lpOutstanding, ) = _pool.bucketAt(_p4000);
        assertEq(deposit,       1_000 * 1e45);
        assertEq(debt,          5_000 * 1e45);
        assertEq(lpOutstanding, 6_000 * 1e27);

        assertEq(_pool.lpBalance(address(_lender), _p4000), 6_000 * 1e27);
    }

    // @notice: 1 lender and 1 borrower deposits quote token
    // @notice: borrows, repays then time passes and
    // @notice: quote token is removed
    function testRemoveQuoteTokenPaidLoan() public {
        // lender deposit 10000 DAI at price 4000
        _lender.addQuoteToken(_pool, address(_lender), 10_000 * 1e18, _p4000);
        assertEq(_quote.balanceOf(address(_lender)), 190_000 * 1e18);

        // lender1 deposit 10000 DAI at price 4000:
        _lender1.addQuoteToken(_pool, address(_lender1), 10_000 * 1e18, _p4000);
        assertEq(_quote.balanceOf(address(_lender1)), 190_000 * 1e18);

        // borrower takes a loan of 10_000 DAI
        _borrower.addCollateral(_pool, 100 * 1e18);
        _borrower.borrow(_pool, 10_000 * 1e18, 4_000 * 1e18);
        assertEq(_pool.hpb(), _p4000);
        assertEq(_pool.lup(), _p4000);

        // borrower repay entire loan
        _quote.mint(address(_borrower), 1 * 1e18);
        _borrower.approveToken(_quote, address(_pool), 100_000 * 1e18);
        _borrower.repay(_pool, 10_001 * 1e18);
        assertEq(_pool.totalDebt(), 0);
        assertEq(_pool.lup(),       0);

        skip(8200);

        _lender1.removeQuoteToken(_pool, address(_lender1), 10_001 * 1e18, _p4000);

        // lender removes entire amount lended
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(_pool), address(_lender), 10_000 * 1e18);
        vm.expectEmit(true, true, false, true);
        emit RemoveQuoteToken(address(_lender), _p4000, 10_000 * 1e45, 0);
        _lender.removeQuoteToken(_pool, address(_lender), 10_001 * 1e18, _p4000);

        // check pool balances and prices
        assertEq(_pool.totalQuoteToken(),          0);
        assertEq(_quote.balanceOf(address(_pool)), 0);

        assertEq(_pool.hpb(), 0);
        assertEq(_pool.lup(), 0);

        // check lender balance
        assertEq(_quote.balanceOf(address(_lender)), 200_000 * 1e18);

        // check 4000 bucket balance
        (, , , uint256 deposit, uint256 debt, , , ) = _pool.bucketAt(_p4000);
        assertEq(deposit, 0);
        assertEq(debt,    0);
    }

    // @notice: 1 lender and 1 borrower deposits quote token
    // @notice: borrows, then lender removes quote token
    function testRemoveQuoteTokenWithDebtReallocation() external {
        // lender deposit 3_400 DAI in 2 buckets
        uint256 priceMed = _p4000;
        uint256 priceLow = _p3010;

        _lender.addQuoteToken(_pool, address(_lender), 3_400 * 1e18, priceMed);
        _lender.addQuoteToken(_pool, address(_lender), 3_400 * 1e18, priceLow);

        // borrower takes a loan of 3000 DAI
        _borrower.addCollateral(_pool, 100 * 1e18);
        _borrower.borrow(_pool, 3_000 * 1e18, 4_000 * 1e18);
        assertEq(_pool.lup(), priceMed);

        (, , , uint256 deposit, uint256 debt, , uint256 lpOutstanding, ) = _pool.bucketAt(priceMed);
        assertEq(deposit, 400 * 1e45);
        assertEq(debt,    3_000 * 1e45);

        (, , , deposit, debt, , , ) = _pool.bucketAt(priceLow);
        assertEq(deposit, 3_400 * 1e45);
        assertEq(debt,    0);

        uint256 poolCollateralizationAfterBorrow = _pool.getPoolCollateralization();
        uint256 targetUtilizationAfterBorrow     = _pool.getPoolTargetUtilization();
        uint256 actualUtilizationAfterBorrow     = _pool.getPoolActualUtilization();
        assertEq(poolCollateralizationAfterBorrow, 133.364255952685584578933333386 * 1e27);
        assertGt(actualUtilizationAfterBorrow,     targetUtilizationAfterBorrow);

        // lender removes 1000 DAI from LUP
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(_pool), address(_lender), 1_000 * 1e18);
        vm.expectEmit(true, true, false, true);
        emit RemoveQuoteToken(address(_lender), priceMed, 1_000 * 1e45, priceLow);
        _lender.removeQuoteToken(_pool, address(_lender), 1_000 * 1e18, priceMed);

        // check that utilization increased following the removal of deposit
        uint256 poolCollateralizationAfterRemove = _pool.getPoolCollateralization();
        uint256 targetUtilizationAfterRemove     = _pool.getPoolTargetUtilization();
        uint256 actualUtilizationAfterRemove     = _pool.getPoolActualUtilization();

        assertLt(poolCollateralizationAfterRemove, poolCollateralizationAfterBorrow);
        assertGt(actualUtilizationAfterRemove,     targetUtilizationAfterRemove);
        assertGt(actualUtilizationAfterRemove,     actualUtilizationAfterBorrow);
        assertGt(targetUtilizationAfterRemove,     targetUtilizationAfterBorrow);

        // check lup moved down to 3000
        assertEq(_pool.hpb(), priceMed);
        assertEq(_pool.lup(), priceLow);

        // check pool balances
        assertEq(_pool.totalQuoteToken(),          2_800 * 1e45);
        assertEq(_pool.totalDebt(),                3_000 * 1e45);
        assertEq(_quote.balanceOf(address(_pool)), 2_800 * 1e18);

        // check lender balance
        assertEq(_quote.balanceOf(address(_lender)), 194_200 * 1e18);

        // check 4000 bucket balance
        (, , , deposit, debt, , lpOutstanding, ) = _pool.bucketAt(priceMed);
        assertEq(deposit,       0);
        assertEq(debt,          2_400 * 1e45);
        assertEq(lpOutstanding, 2_400 * 1e27);

        assertEq(_pool.lpBalance(address(_lender), priceMed), 2_400 * 1e27);

        // check 3_010.892022197881557845 bucket balance
        (, , , deposit, debt, , lpOutstanding, ) = _pool.bucketAt(priceLow);
        assertEq(deposit,       2_800 * 1e45);
        assertEq(debt,          600 * 1e45);
        assertEq(lpOutstanding, 3_400 * 1e27);

        assertEq(_pool.lpBalance(address(_lender), priceLow), 3_400 * 1e27);
    }

    // @notice: 1 lender and 1 borrower deposits quote token
    // @notice: over time, borrows, then lender removes
    // @notice: quote token causing reallocation
    function testRemoveQuoteTokenOverTimeWithDebt() external {
        uint256 priceMed = _p4000;
        uint256 priceLow = _p3010;

        // lender deposit into 2 buckets
        _lender.addQuoteToken(_pool, address(_lender), 1_000 * 1e18, priceMed);
        _lender.addQuoteToken(_pool, address(_lender), 2_000 * 1e18, priceMed);
        skip(14);
        _lender.addQuoteToken(_pool, address(_lender), 6_000 * 1e18, priceLow);
        skip(1340);

        // borrower takes a loan of 4000 DAI
        _borrower.addCollateral(_pool, 100 * 1e18);
        _borrower.borrow(_pool, 4_000 * 1e18, 0);

        (, , , uint256 deposit, uint256 debt, , uint256 lpOutstanding, ) = _pool.bucketAt(priceMed);
        assertEq(deposit,       0);
        assertEq(debt,          3_000 * 1e45);
        assertEq(lpOutstanding, 3_000 * 1e27);

        (, , , deposit, debt, , lpOutstanding, ) = _pool.bucketAt(priceLow);
        assertEq(deposit,       5_000 * 1e45);
        assertEq(debt,          1_000 * 1e45);
        assertEq(lpOutstanding, 6_000 * 1e27);

        assertEq(_pool.hpb(), priceMed);
        assertEq(_pool.lup(), priceLow);

        skip(1340);

        // lender removes entire bid from 4_000.927678580567537368 bucket
        uint256 withdrawalAmount = 3_001 * 1e45;
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(_pool), address(_lender), 3_000.006373674954296470 * 1e18);
        vm.expectEmit(true, true, false, true);
        emit RemoveQuoteToken(address(_lender), priceMed,
            3_000.006373674954296470378557 * 1e45, priceLow);
        _lender.removeQuoteToken(_pool, address(_lender), withdrawalAmount / 1e27, priceMed);

        // confirm entire bid was removed
        (, , , deposit, debt, , lpOutstanding, ) = _pool.bucketAt(priceMed);
        assertEq(deposit,       0);
        assertEq(debt,          0);
        assertEq(lpOutstanding, 0);

        // confirm debt was reallocated
        (, , , deposit, debt, , lpOutstanding, ) = _pool.bucketAt(priceLow);
        assertEq(deposit, 1_999.993626325045703529621443 * 1e45);

        // some debt accumulated between loan and reallocation
        assertEq(debt, 4_000.008498233272395293838076 * 1e45);

        assertEq(_pool.hpb(), priceLow);
        assertEq(_pool.lup(), priceLow);
    }

    // @notice: 1 lender and 1 borrower deposits quote token, borrow
    // @notice: then lender withdraws quote token above LUP
    function testRemoveQuoteTokenAboveLup() external {
        // Lender deposits 1000 in each bucket
        _lender.addQuoteToken(_pool, address(_lender), 1_000 * 1e18, _p2850);
        _lender.addQuoteToken(_pool, address(_lender), 1_000 * 1e18, _p2835);
        _lender.addQuoteToken(_pool, address(_lender), 1_000 * 1e18, _p2821);
        _lender.addQuoteToken(_pool, address(_lender), 1_000 * 1e18, _p2807);

        // check initial utilization after depositing but not borrowing
        assertEq(_pool.getPoolCollateralization(), Maths.ONE_RAY);
        assertEq(_pool.getPoolActualUtilization(), 0);
        assertEq(_pool.getPoolTargetUtilization(), Maths.ONE_RAY);

        // Borrower draws 2400 debt partially utilizing the LUP
        _borrower.addCollateral(_pool, 10 * 1e18);
        _borrower.borrow(_pool, 2_400 * 1e18, 0);
        (, , , uint256 deposit, uint256 debt, , , ) = _pool.bucketAt(_p2850);
        assertEq(deposit, 0);
        assertEq(debt,    1_000 * 1e45);

        (, , , deposit, debt, , , ) = _pool.bucketAt(_p2835);
        assertEq(deposit, 0);
        assertEq(debt,    1_000 * 1e45);

        (, , , deposit, debt, , , ) = _pool.bucketAt(_p2821);
        assertEq(deposit, 600 * 1e45);
        assertEq(debt,    400 * 1e45);

        (, , , deposit, debt, , , ) = _pool.bucketAt(_p2807);
        assertEq(deposit, 1_000 * 1e45);
        assertEq(debt,    0);

        assertEq(_pool.hpb(), _p2850);
        assertEq(_pool.lup(), _p2821);
        uint256 poolCollateralizationAfterBorrow  = _pool.getPoolCollateralization();
        uint256 targetUtilizationAfterBorrow      = _pool.getPoolTargetUtilization();
        uint256 actualUtilizationAfterBorrow      = _pool.getPoolActualUtilization();

        assertEq(poolCollateralizationAfterBorrow, 11.757774763124786456862499999 * 1e27);
        assertGt(actualUtilizationAfterBorrow,     targetUtilizationAfterBorrow);

        // Lender withdraws above LUP
        _lender.removeQuoteToken(_pool, address(_lender), 1_000 * 1e18, _p2850);
        (, , , deposit, debt, , , ) = _pool.bucketAt(_p2850);
        assertEq(deposit, 0);
        assertEq(debt,    0);

        (, , , deposit, debt, , , ) = _pool.bucketAt(_p2835);
        assertEq(deposit, 0);
        assertEq(debt,    1_000 * 1e45);

        (, , , deposit, debt, , , ) = _pool.bucketAt(_p2821);
        assertEq(deposit, 0);
        assertEq(debt,    1_000 * 1e45);

        (, , , deposit, debt, , , ) = _pool.bucketAt(_p2807);
        assertEq(deposit, 600 * 1e45);
        assertEq(debt,    400 * 1e45);

        assertEq(_pool.hpb(), _p2835);
        assertEq(_pool.lup(), _p2807);

        // check that utilization increased following the removal of deposit
        uint256 poolCollateralizationAfterRemove = _pool.getPoolCollateralization();
        uint256 targetUtilizationAfterRemove     = _pool.getPoolTargetUtilization();
        uint256 actualUtilizationAfterRemove     = _pool.getPoolActualUtilization();

        assertLt(poolCollateralizationAfterRemove, poolCollateralizationAfterBorrow);
        assertGt(actualUtilizationAfterRemove,     targetUtilizationAfterRemove);
        assertGt(actualUtilizationAfterRemove,     actualUtilizationAfterBorrow);
        assertGt(targetUtilizationAfterRemove,     targetUtilizationAfterBorrow);
    }

    function testRemoveQuoteTokenAtLup() public {
        uint256 priceHigh = 4_000.927678580567537368 * 1e18;
        uint256 priceMed = 3_010.892022197881557845 * 1e18;
        uint256 priceLow = 2_000.221618840727700609 * 1e18;
        // lender deposit 5000 DAI in 3 buckets
        lender.addQuoteToken(pool, address(lender), 1_000 * 1e18, priceHigh);
        lender.addQuoteToken(pool, address(lender), 1_000 * 1e18, priceMed);
        lender.addQuoteToken(pool, address(lender), 3_000 * 1e18, priceLow);
        skip(60);

        // borrower takes a loan which partially utilizes the middle bucket
        borrower.addCollateral(pool, 100 * 1e18);
        borrower.borrow(pool, 1_000 * 1e18, priceMed);
        skip(60); // fragment the inflator
        borrower.borrow(pool, 400 * 1e18, priceMed);
        (, , , uint256 deposit, uint256 debt, , uint256 lpOutstanding,) = pool.bucketAt(priceHigh);
        assertEq(deposit, 0);
        assertEq(debt, 1_000.000095129380400679662239 * 1e45);
        (, , , deposit, debt, , ,) = pool.bucketAt(priceMed);
        assertEq(deposit, 600 * 1e45);
        assertEq(debt, 400 * 1e45);
        (, , , deposit, debt, , ,) = pool.bucketAt(priceLow);
        assertEq(deposit, 3_000 * 1e45);
        assertEq(debt, 0 * 1e45);
        assertEq(pool.hpb(), priceHigh);
        assertEq(pool.lup(), priceMed);
        skip(60);

        // lender removes 500 DAI from the lup
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(pool), address(lender), 500 * 1e18);
        vm.expectEmit(true, true, false, true);
        emit RemoveQuoteToken(address(lender), priceMed, 500 * 1e45, priceMed);
        lender.removeQuoteToken(pool, address(lender), 500 * 1e18, priceMed);
        (, , , deposit, debt, , ,) = pool.bucketAt(priceHigh);
        assertEq(deposit, 0);
        assertEq(debt, 1_000.000095129380400679662239 * 1e45);
        (, , , deposit, debt, , ,) = pool.bucketAt(priceMed);
        assertEq(deposit, 100 * 1e45);
        assertEq(debt, 400.0000380517521602718648956 * 1e45);
        (, , , deposit, debt, , ,) = pool.bucketAt(priceLow);
        assertEq(deposit, 3_000 * 1e45);
        assertEq(debt, 0 * 1e45);
        assertEq(pool.hpb(), priceHigh);
        assertEq(pool.lup(), priceMed);
        skip(60);

        // lender removes remaining DAI, including interest earned, from the lup
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(pool), address(lender), 500.000076103507940383 * 1e18);
        vm.expectEmit(true, true, false, true);
        emit RemoveQuoteToken(address(lender), priceMed, 500.000076103507940383335958001 * 1e45, priceLow);
        lender.removeQuoteToken(pool, address(lender), 501 * 1e18, priceMed);
        (, , , deposit, debt, , ,) = pool.bucketAt(priceHigh);
        assertEq(deposit, 0);
        assertEq(debt, 1_000.000095129380400679662239 * 1e45);
        (, , , deposit, debt, , lpOutstanding,) = pool.bucketAt(priceMed);
        assertEq(deposit, 0);
        assertEq(debt, 0); // FIXME: shows dusty debt amount remaining
        assertEq(lpOutstanding, 0);
        (, , , deposit, debt, , ,) = pool.bucketAt(priceLow);  // nothing else can be removed
        assertEq(deposit, 2_599.999923896492059616664041999 * 1e45);
        assertEq(debt, 400.000076103507940383335958001 * 1e45);
        assertEq(pool.hpb(), priceHigh);
//        assertEq(pool.lup(), priceLow);
    }

    // @notice: 1 lender and 1 borrower deposits quote token
    // @notice: borrows, then lender removes quote token under the LUP
    function testRemoveQuoteTokenBelowLup() external {
        uint256 priceHigh = _p4000;
        uint256 priceMed  = _p3010;
        uint256 priceLow  = _p2000;

        // lender deposit 5000 DAI in 3 buckets
        _lender.addQuoteToken(_pool, address(_lender), 5_000 * 1e18, priceHigh);
        _lender.addQuoteToken(_pool, address(_lender), 5_000 * 1e18, priceMed);
        _lender.addQuoteToken(_pool, address(_lender), 5_000 * 1e18, priceLow);

        // check initial utilization after depositing but not borrowing
        uint256 collateralization = _pool.getPoolCollateralization();
        uint256 targetUtilization = _pool.getPoolTargetUtilization();
        uint256 actualUtilization = _pool.getPoolActualUtilization();
        assertEq(collateralization, Maths.ONE_RAY);
        assertEq(actualUtilization, 0);
        assertEq(targetUtilization, Maths.ONE_RAY);

        // borrower takes a loan of 3000 DAI
        borrower.addCollateral(_pool, 100 * 1e18);
        borrower.borrow(_pool, 3_000 * 1e18, priceHigh);
        assertEq(_pool.hpb(), priceHigh);
        assertEq(_pool.lup(), priceHigh);

        // lender removes 1000 DAI under the lup - from bucket 3000
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(_pool), address(_lender), 1_000 * 1e18);
        vm.expectEmit(true, true, false, true);
        emit RemoveQuoteToken(address(_lender), priceMed, 1_000 * 1e45, priceHigh);
        _lender.removeQuoteToken(_pool, address(_lender), 1_000 * 1e18, priceMed);

        // check same lup
        assertEq(_pool.hpb(), priceHigh);
        assertEq(_pool.lup(), priceHigh);
        // check pool balances
        assertEq(_pool.totalQuoteToken(),          11_000 * 1e45);
        assertEq(_quote.balanceOf(address(_pool)), 11_000 * 1e18);

        // check pool collateralization
        collateralization = _pool.getPoolCollateralization();
        assertEq(collateralization, 133.364255952685584578933333386 * 1e27);

        // check pool is still overcollateralized
        targetUtilization = _pool.getPoolTargetUtilization();
        actualUtilization = _pool.getPoolActualUtilization();
        assertGt(actualUtilization, targetUtilization);

        // check 4000 bucket balance
        (, , , uint256 deposit, uint256 debt, , uint256 lpOutstanding, ) = _pool.bucketAt(priceHigh);
        assertEq(deposit,       2_000 * 1e45);
        assertEq(debt,          3_000 * 1e45);
        assertEq(lpOutstanding, 5_000 * 1e27);

        assertEq(_pool.lpBalance(address(_lender), priceHigh), 5_000 * 1e27);

        // check 3_010.892022197881557845 bucket balance, should have less 1000 DAI and lp token
        (, , , deposit, debt, , lpOutstanding, ) = _pool.bucketAt(priceMed);
        assertEq(deposit,       4_000 * 1e45);
        assertEq(debt,          0);
        assertEq(lpOutstanding, 4_000 * 1e27);

        assertEq(_pool.lpBalance(address(_lender), priceMed), 4_000 * 1e27);
    }

    // @notice: 1 lender and 1 borrower deposits quote token
    // @notice: borrows, then lender removes quote token in under collateralized pool
    function testRemoveQuoteUndercollateralizedPool() external {
        uint256 priceLow    = _p1004;
        uint256 priceLowest = _p100;

        // lender deposit 5000 DAI in 2 spaced buckets
        _lender.addQuoteToken(_pool, address(_lender), 5_000 * 1e18, priceLow);
        _lender.addQuoteToken(_pool, address(_lender), 5_000 * 1e18, priceLowest);

        // check initial utilization after depositing but not borrowing
        uint256 targetUtilization = _pool.getPoolTargetUtilization();
        uint256 actualUtilization = _pool.getPoolActualUtilization();
        assertEq(actualUtilization, 0);
        assertEq(targetUtilization, Maths.ONE_RAY);

        // borrower takes a loan of 4000 DAI at priceLow
        uint256 borrowAmount = 4_000 * 1e18;
        _borrower.addCollateral(_pool, 5.1 * 1e18);
        _borrower.borrow(_pool, borrowAmount, 1_000 * 1e18);
        assertEq(_pool.hpb(), priceLow);
        assertEq(_pool.lup(), priceLow);

        // removal should revert if pool remains undercollateralized
        vm.expectRevert(
            abi.encodeWithSelector(
                IPool.PoolUndercollateralized.selector,
                0.127923769382684562609750000 * 1e27
            )
        );
        _lender.removeQuoteToken(_pool, address(_lender), 2_000 * 1e18, priceLow);

        // check pool collateralization after borrowing
        uint256 collateralization = _pool.getPoolCollateralization();
        assertEq(collateralization, 1.281361819597192738244850000 * 1e27);

        // check pool utilization after borrowing
        targetUtilization = _pool.getPoolTargetUtilization();
        actualUtilization = _pool.getPoolActualUtilization();
        assertEq(actualUtilization, Maths.wadToRay(Maths.wdiv(borrowAmount, (10_000 * 1e18))));

        // since pool is undercollateralized actualUtilization should be < targetUtilization
        assertLt(actualUtilization, targetUtilization);
    }

    // @notice: 2 lenders both deposit then remove quote token
    function testRemoveQuoteMultipleLenders() external {
        uint256 priceLow = _p1004;

        assertEq(_quote.balanceOf(address(_lender)),  200_000 * 1e18);
        assertEq(_quote.balanceOf(address(_lender1)), 200_000 * 1e18);
        assertEq(_quote.balanceOf(address(_pool)),    0);

        (, , , , , , uint256 lpOutstanding, ) = _pool.bucketAt(priceLow);
        assertEq(lpOutstanding, 0);

        assertEq(_pool.lpBalance(address(_lender), priceLow),  0);
        assertEq(_pool.lpBalance(address(_lender1), priceLow), 0);

        // lender1 deposit 10000 DAI
        _lender.addQuoteToken(_pool, address(_lender), 10_000 * 1e18, priceLow);

        // lender1 deposit 10000 DAI in same bucket
        _lender1.addQuoteToken(_pool, address(_lender1), 10_000 * 1e18, priceLow);

        assertEq(_quote.balanceOf(address(_lender)),  190_000 * 1e18);
        assertEq(_quote.balanceOf(address(_lender1)), 190_000 * 1e18);
        assertEq(_quote.balanceOf(address(_pool)),    20_000 * 1e18);

        assertEq(_pool.lpBalance(address(_lender), priceLow),  10_000 * 1e27);
        assertEq(_pool.lpBalance(address(_lender1), priceLow), 10_000 * 1e27);

        assertEq(_pool.hpb(), priceLow);
        assertEq(_pool.lup(), 0);

        (, , , , , , lpOutstanding, ) = _pool.bucketAt(priceLow);
        assertEq(lpOutstanding, 20_000 * 1e27);

        skip(8200);

        _lender.removeQuoteToken(_pool, address(_lender), 10_000 * 1e18, priceLow);

        assertEq(_pool.lpBalance(address(_lender), priceLow),  0);
        assertEq(_pool.lpBalance(address(_lender1), priceLow), 10_000 * 1e27);

        (, , , , , , lpOutstanding, ) = _pool.bucketAt(priceLow);
        assertEq(lpOutstanding, 10_000 * 1e27);

        _lender1.removeQuoteToken(_pool, address(_lender1), 10_000 * 1e18, priceLow);

        assertEq(_quote.balanceOf(address(_lender)),  200_000 * 1e18);
        assertEq(_quote.balanceOf(address(_lender1)), 200_000 * 1e18);
        assertEq(_quote.balanceOf(address(_pool)),    0);

        assertEq(_pool.lpBalance(address(_lender), priceLow),  0);
        assertEq(_pool.lpBalance(address(_lender1), priceLow), 0);

        (, , , , , , lpOutstanding, ) = _pool.bucketAt(priceLow);
        assertEq(lpOutstanding, 0);

        assertEq(_pool.hpb(), 0);
        assertEq(_pool.lup(), 0);
    }

    // @notice: 1 lender and 2 borrowers deposit quote token
    // @notice: remove quote token borrow, update interest rate
    // @notice: then remove quote token with interest
    // @notice: lender reverts: attempts to removeQuoteToken when not enough quote token in pool
    function testRemoveQuoteTokenWithInterest() external {
        // lender deposit in 3 buckets, price spaced
        _lender.addQuoteToken(_pool, address(_lender), 10_000 * 1e18, _p10016);
        _lender.addQuoteToken(_pool, address(_lender), 1_000 * 1e18, _p9020);
        _lender.addQuoteToken(_pool, address(_lender), 1_000 * 1e18, _p8002);
        _lender.addQuoteToken(_pool, address(_lender), 1_000 * 1e18, _p100);

        // borrowers deposit collateral
        _borrower.addCollateral(_pool, 2 * 1e18);
        _borrower2.addCollateral(_pool, 200 * 1e18);
        assertEq(_pool.getPoolCollateralization(), Maths.ONE_RAY);

        // first borrower takes a loan of 12_000 DAI, pushing lup to 8_002.824356287850613262
        _borrower.borrow(_pool, 12_000 * 1e18, 8_000 * 1e18);
        assertEq(_pool.lup(),                       _p8002);
        assertEq(_pool.getPoolCollateralization(), 134.714209997512151989910333326 * 1e27);

        skip(5000);
        _pool.updateInterestRate();
        skip(5000);
        // 2nd borrower takes a loan of 1_000 DAI, pushing lup to 100.332368143282009890
        _borrower2.borrow(_pool, 1_000 * 1e18, 100 * 1e18);
        assertEq(_pool.lup(),                      _p100);
        assertEq(_pool.getPoolCollateralization(), 1.558954565201166119419824603 * 1e27);

        skip(5000);
        _pool.updateInterestRate();
        skip(5000);

        (uint256 col, uint256 quoteLPValue) = _pool.getLPTokenExchangeValue(
            _pool.getLPTokenBalance(address(_lender), _p8002),
            _p8002
        );
        assertEq(quoteLPValue, 1_000.023113960510762449249703 * 1e45);

        // check pool state following borrows
        uint256 poolCollateralizationAfterBorrow = _pool.getPoolCollateralization();
        uint256 targetUtilizationAfterBorrow     = _pool.getPoolTargetUtilization();
        uint256 actualUtilizationAfterBorrow     = _pool.getPoolActualUtilization();

        assertEq(poolCollateralizationAfterBorrow, 1.558858827078768654127776949 * 1e27);
        assertGt(actualUtilizationAfterBorrow,     targetUtilizationAfterBorrow);

        // should revert if not enough funds in pool
        assertEq(_pool.totalQuoteToken(), 0);

        vm.expectRevert(abi.encodeWithSelector(Buckets.NoDepositToReallocateTo.selector));
        _lender.removeQuoteToken(_pool, address(_lender), 1_000.023113960510762449 * 1e18, _p8002);

        // borrower repays their initial loan principal
        _borrower.repay(_pool, 12_000 * 1e18);
        (col, quoteLPValue) = _pool.getLPTokenExchangeValue(
            _pool.getLPTokenBalance(address(_lender), _p8002),
            _p8002
        );
        assertEq(quoteLPValue, 1_000.058932266911224024728608229 * 1e45);

        // check that utilization decreased following repayment
        uint256 poolCollateralizationAfterRepay = _pool.getPoolCollateralization();
        uint256 targetUtilizationAfterRepay     = _pool.getPoolTargetUtilization();
        uint256 actualUtilizationAfterRepay     = _pool.getPoolActualUtilization();

        assertGt(poolCollateralizationAfterRepay, poolCollateralizationAfterBorrow);
        assertGt(actualUtilizationAfterRepay,     targetUtilizationAfterRepay);
        assertLt(actualUtilizationAfterRepay,     actualUtilizationAfterBorrow);
        assertLt(targetUtilizationAfterRepay,     targetUtilizationAfterBorrow);

        // lender should be able to remove lent quote tokens + interest
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(_pool), address(_lender), 1_000.053487614594018248 * 1e18);
        vm.expectEmit(true, true, false, true);
        emit RemoveQuoteToken(address(_lender), _p8002, 1_000.053487614594018248 * 1e45, _p10016);
        _lender.removeQuoteToken(_pool, address(_lender), 1_000.053487614594018248 * 1e18, _p8002);

        assertEq(_pool.hpb(), _p10016);
        assertEq(_pool.lup(), _p10016);
    }

    // @notice: 1 lender removes more quote token than their claim
    function testRemoveMoreThanClaim() external {
        uint256 price = _p4000;

        // lender deposit 4000 DAI at price 4000
        _lender.addQuoteToken(_pool, address(_lender), 4_000 * 1e18, price);
        skip(14);

        // remove max 5000 DAI at price of 1 MKR = 4_000.927678580567537368 DAI
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(_pool), address(_lender), 4_000 * 1e18);
        vm.expectEmit(true, true, false, true);
        emit RemoveQuoteToken(address(_lender), price, 4_000 * 1e45, 0);
        _lender.removeQuoteToken(_pool, address(_lender), 5_000 * 1e18, price);

        // check balances
        assertEq(_pool.totalQuoteToken(),          0);
        assertEq(_quote.balanceOf(address(_pool)), 0);
        skip(14);

        // lender deposit 2000 DAI at price 4000
        _lender.addQuoteToken(_pool, address(_lender), 2_000 * 1e18, price);
        skip(14);

        // remove uint256.max at price of 1 MKR = 4_000.927678580567537368 DAI
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(_pool), address(_lender), 2_000 * 1e18);
        vm.expectEmit(true, true, false, true);
        emit RemoveQuoteToken(address(_lender), price, 2_000 * 1e45, 0);
        _lender.removeQuoteToken(_pool, address(_lender), LARGEST_AMOUNT, price);

        // check balances
        assertEq(_pool.totalQuoteToken(),          0);
        assertEq(_quote.balanceOf(address(_pool)), 0);
    }

    // @notice: ensure HPB is updated when there are liquidity gaps
    function testGetHpb() external {
        uint256 priceHigh = _p2000;
        uint256 priceMed  = _p1004;
        uint256 priceLow  = _p502;

        assertEq(_pool.hpb(), 0);

        // lender deposits 150_000 DAI in 3 buckets
        _lender.addQuoteToken(_pool, address(_lender), 100 * 1e18, priceLow);
        assertEq(_pool.hpb(), priceLow);

        _lender.addQuoteToken(_pool, address(_lender), 100 * 1e18, priceHigh);
        assertEq(_pool.hpb(), priceHigh);

        _lender.addQuoteToken(_pool, address(_lender), 100 * 1e18, priceMed);
        assertEq(_pool.hpb(), priceHigh);

        // lender removes from middle bucket
        _lender.removeQuoteToken(_pool, address(_lender), 100 * 1e18, priceMed);
        assertEq(_pool.hpb(), priceHigh);

        // lender removes from high bucket
        _lender.removeQuoteToken(_pool, address(_lender), 100 * 1e18, priceHigh);
        assertEq(_pool.hpb(), priceLow);

        // lender removes all liquidity
        _lender.removeQuoteToken(_pool, address(_lender), 100 * 1e18, priceLow);
        assertEq(_pool.hpb(), 0);
    }

}
