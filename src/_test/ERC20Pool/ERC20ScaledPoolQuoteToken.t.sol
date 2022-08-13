// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.14;

import { ERC20Pool }        from "../../erc20/ERC20Pool.sol";
import { ERC20PoolFactory } from "../../erc20/ERC20PoolFactory.sol";

import { BucketMath } from "../../libraries/BucketMath.sol";

import { DSTestPlus }                             from "../utils/DSTestPlus.sol";
import { CollateralToken, QuoteToken }            from "../utils/Tokens.sol";
import { UserWithCollateral, UserWithQuoteToken } from "../utils/Users.sol";

contract ERC20ScaledQuoteTokenTest is DSTestPlus {

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

    /**
     *  @notice 1 lender tests adding quote token.
     *          Lender reverts:
     *              attempts to addQuoteToken at invalid price.
     */
    function testScaledPoolDepositQuoteToken() external {

        // test 10_000 DAI deposit at price of 1 MKR = 3_010.892022197881557845 DAI
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(_lender), address(_pool), 10_000 * 1e18);
        vm.expectEmit(true, true, false, true);
        emit AddQuoteToken(address(_lender), _p3010, 10_000 * 1e18, BucketMath.MAX_PRICE);
        _lender.addQuoteToken(_pool, 10_000 * 1e18, 2550);

        assertEq(_pool.htp(), 0);
        assertEq(_pool.lup(), BucketMath.MAX_PRICE);

        assertEq(_pool.treeSum(),                         10_000 * 1e18);
        assertEq(_pool.lpBalance(2550, address(_lender)), 10_000 * 1e27);
        assertEq(_pool.exchangeRate(2550),                     1 * 1e27);

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
        _lender.addQuoteToken(_pool, 20_000 * 1e18, 2551);

        assertEq(_pool.htp(), 0);
        assertEq(_pool.lup(), BucketMath.MAX_PRICE);

        assertEq(_pool.treeSum(),                         30_000 * 1e18);
        assertEq(_pool.lpBalance(2551, address(_lender)), 20_000 * 1e27);

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
        _lender.addQuoteToken(_pool, 40_000 * 1e18, 2549);

        assertEq(_pool.htp(), 0);
        assertEq(_pool.lup(), BucketMath.MAX_PRICE);

        assertEq(_pool.treeSum(),                         70_000 * 1e18);
        assertEq(_pool.lpBalance(2549, address(_lender)), 40_000 * 1e27);

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

        _lender.addQuoteToken(_pool, 40_000 * 1e18, 2549);
        _lender.addQuoteToken(_pool, 10_000 * 1e18, 2550);
        _lender.addQuoteToken(_pool, 20_000 * 1e18, 2551);

        assertEq(_pool.lpBalance(2549, address(_lender)), 40_000 * 1e27);

        assertEq(_quote.balanceOf(address(_pool)),   70_000 * 1e18);
        assertEq(_quote.balanceOf(address(_lender)), 130_000 * 1e18);

        vm.expectEmit(true, true, false, true);
        emit RemoveQuoteToken(address(_lender), 3_025.946482308870940904 * 1e18, 5_000 * 1e18, BucketMath.MAX_PRICE);
        _lender.removeQuoteToken(_pool, 5_000 * 1e18, 2549);

        assertEq(_pool.lpBalance(2549, address(_lender)), 35_000 * 1e27);

        assertEq(_quote.balanceOf(address(_pool)),   65_000 * 1e18);
        assertEq(_quote.balanceOf(address(_lender)), 135_000 * 1e18);
    }

    /**
     *  @notice 1 lender tests reverts in removeQuoteToken.
     *          Reverts:
     *              Attempts to remove more quote tokens than available from lpBalance.
     *              Attempts to remove quote token when doing so would drive lup below htp.
     */
    function testScaledPoolRemoveQuoteTokenRequireChecks() external {
        // lender adds initial quote token
        _lender.addQuoteToken(_pool, 40_000 * 1e18, 4549);
        _lender.addQuoteToken(_pool, 10_000 * 1e18, 4550);
        _lender.addQuoteToken(_pool, 20_000 * 1e18, 4551);

        // add collateral and borrow all available quote in the higher priced original 3 buckets
        _lender.addQuoteToken(_pool, 30_000 * 1e18, 4990);
        _collateral.mint(address(_borrower), 3500000 * 1e18);
        _borrower.approveToken(_collateral, address(_pool), 3500000 * 1e18);
        _borrower.pledgeCollateral(_pool, 3500000 * 1e18, address(0), address(0));
        _borrower.borrow(_pool, 70000 * 1e18, 4551, address(0), address(0));

        // should revert if removing quote token from higher price buckets would drive lup below htp
        vm.expectRevert("S:RQT:BAD_LUP");
        _lender.removeQuoteToken(_pool, 20_000 * 1e18, 4551);

        // should be able to removeQuoteToken if quote tokens haven't been encumbered by a borrower
        emit RemoveQuoteToken(address(_lender), _pool.indexToPrice(4990), 10_000 * 1e18, _pool.indexToPrice(4551));
        _lender.removeQuoteToken(_pool, 10_000 * 1e18, 4990);
    }

    function testScaledPoolRemoveQuoteTokenWithDebt() external {
        // lender adds initial quote token
        _lender.addQuoteToken(_pool, 3_400 * 1e18, 1606);
        _lender.addQuoteToken(_pool, 3_400 * 1e18, 1663);
        uint256 lpb_before = _pool.lpBalance(1606, address(_lender));
        uint256 exchangeRateBefore = _pool.exchangeRate(1606);
        skip(3600);
        assertEq(lpb_before, _pool.lpBalance(1606, address(_lender)));
        assertEq(exchangeRateBefore, _pool.exchangeRate(1606));
        uint256 lenderBalanceBefore = _quote.balanceOf(address(_lender));

        // borrower takes a loan of 3000 quote token
        _collateral.mint(address(_borrower), 100 * 1e18);
        _borrower.approveToken(_collateral, address(_pool), 100 * 1e18);
        _borrower.pledgeCollateral(_pool, 100 * 1e18, address(0), address(0));
        uint256 limitPrice = _pool.priceToIndex(4_000 * 1e18);
        assertGt(limitPrice, 1663);
        _borrower.borrow(_pool, 3_000 * 1e18, limitPrice, address(0), address(0));
        skip(7200);
        assertEq(lpb_before, _pool.lpBalance(1606, address(_lender)));
        assertEq(exchangeRateBefore, _pool.exchangeRate(1606));

        // lender removes all quote token, including interest, from the bucket
        assertGt(_pool.indexToPrice(1606), _pool.htp());
        uint256 quoteWithInterest = 3_400.023138863804135800 * 1e18;
        vm.expectEmit(true, true, false, true);
        emit RemoveQuoteToken(address(_lender), _pool.indexToPrice(1606), quoteWithInterest, _pool.indexToPrice(1663));
        _lender.removeQuoteToken(_pool, 3_500 * 1e18, 1606);
        assertEq(_quote.balanceOf(address(_lender)), lenderBalanceBefore + quoteWithInterest);
        assertEq(_pool.lpBalance(1606, address(_lender)), 0);

        // ensure bucket is empty
        (uint256 quote, uint256 collateral, uint256 lpb, ) = _pool.bucketAt(1606);
        assertEq(quote, 0);
        assertEq(collateral, 0);
        assertEq(lpb, 0);
    }

    function testScaledPoolMoveQuoteToken() external {
        _lender.addQuoteToken(_pool, 40_000 * 1e18, 2549);
        _lender.addQuoteToken(_pool, 10_000 * 1e18, 2550);
        _lender.addQuoteToken(_pool, 20_000 * 1e18, 2551);

        assertEq(_pool.lpBalance(2549, address(_lender)), 40_000 * 1e27);
        assertEq(_pool.lpBalance(2552, address(_lender)), 0);

        vm.expectEmit(true, true, false, true);
        emit MoveQuoteToken(address(_lender), 2549, 2552, 5_000 * 1e18, BucketMath.MAX_PRICE);
        _lender.moveQuoteToken(_pool, 5_000 * 1e18, 2549, 2552);

        assertEq(_pool.lpBalance(2549, address(_lender)), 35_000 * 1e27);
        assertEq(_pool.lpBalance(2552, address(_lender)), 5_000 * 1e27);

        vm.expectEmit(true, true, false, true);
        emit MoveQuoteToken(address(_lender), 2549, 2540, 5_000 * 1e18, BucketMath.MAX_PRICE);
        _lender.moveQuoteToken(_pool, 5_000 * 1e18, 2549, 2540);

        assertEq(_pool.lpBalance(2549, address(_lender)), 30_000 * 1e27);
        assertEq(_pool.lpBalance(2540, address(_lender)), 5_000 * 1e27);

        vm.expectEmit(true, true, false, true);
        emit MoveQuoteToken(address(_lender), 2551, 2777, 15_000 * 1e18, BucketMath.MAX_PRICE);
        _lender.moveQuoteToken(_pool, 15_000 * 1e18, 2551, 2777);

        assertEq(_pool.lpBalance(2551, address(_lender)), 5_000 * 1e27);
        assertEq(_pool.lpBalance(2777, address(_lender)), 15_000 * 1e27);
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
        _collateral.mint(address(_lender1), 100000 * 1e18);
        _lender1.approveToken(_collateral, address(_pool), 100000 * 1e18);

        // lender adds initial quote token
        _lender.addQuoteToken(_pool, 40_000 * 1e18, 4549);
        _lender.addQuoteToken(_pool, 10_000 * 1e18, 4550);
        _lender.addQuoteToken(_pool, 20_000 * 1e18, 4551);

        // should revert if moving quote token to the existing price
        vm.expectRevert("S:MQT:SAME_PRICE");
        _lender.moveQuoteToken(_pool, 5_000 * 1e18, 4549, 4549);

        // add collateral and borrow all available quote in the higher priced original 3 buckets, as well as some of the new lowest price bucket
        _lender.addQuoteToken(_pool, 30_000 * 1e18, 4651);
        _collateral.mint(address(_borrower), 1500000 * 1e18);
        _borrower.approveToken(_collateral, address(_pool), 1500000 * 1e18);
        _borrower.pledgeCollateral(_pool, 1500000 * 1e18, address(0), address(0));
        _borrower.borrow(_pool, 60000.1 * 1e18, 4651, address(0), address(0));

        // should revert if movement would drive lup below htp
        vm.expectRevert("S:MQT:LUP_BELOW_HTP");
        _lender.moveQuoteToken(_pool, 40_000 * 1e18, 4549, 6000);

        // should be able to moveQuoteToken if properly specified
        vm.expectEmit(true, true, false, true);
        emit MoveQuoteToken(address(_lender), 4549, 4550, 10_000 * 1e18, _pool.indexToPrice(4551));
        _lender.moveQuoteToken(_pool, 10_000 * 1e18, 4549, 4550);
    }

    // TODO: test moving quote token with debt on the book and skips to accumulate interest
}
