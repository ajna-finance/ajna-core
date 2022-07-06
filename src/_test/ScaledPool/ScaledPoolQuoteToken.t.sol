// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.14;

import { ScaledPool }        from "../../ScaledPool.sol";
import { ScaledPoolFactory } from "../../ScaledPoolFactory.sol";

import { BucketMath }        from "../../libraries/BucketMath.sol";

import { DSTestPlus }                             from "../utils/DSTestPlus.sol";
import { CollateralToken, QuoteToken }            from "../utils/Tokens.sol";
import { UserWithCollateral, UserWithQuoteTokenInScaledPool } from "../utils/Users.sol";

contract ScaledQuoteTokenTest is DSTestPlus {

    uint256 public constant LARGEST_AMOUNT = type(uint256).max / 10**27;

    address                        internal _poolAddress;
    CollateralToken                internal _collateral;
    ScaledPool                     internal _pool;
    QuoteToken                     internal _quote;
    UserWithCollateral             internal _borrower;
    UserWithCollateral             internal _borrower2;
    UserWithQuoteTokenInScaledPool internal _lender;
    UserWithQuoteTokenInScaledPool internal _lender1;

    function setUp() external {
        _collateral  = new CollateralToken();
        _quote       = new QuoteToken();
        _poolAddress = new ScaledPoolFactory().deployPool(address(_collateral), address(_quote),0.05 * 10**18 );
        _pool        = ScaledPool(_poolAddress);

        _borrower   = new UserWithCollateral();
        _borrower2  = new UserWithCollateral();
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

    /**
     *  @notice 1 lender tests adding quote token.
     *          Lender reverts:
     *              attempts to addQuoteToken at invalid price.
     */
    function testScaledPoolDepositQuoteToken() external {

        // test 10_000 DAI deposit at price of 1 MKR = 4000 DAI
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(_lender), address(_pool), 10_000 * 1e18);
        vm.expectEmit(true, true, false, true);
        emit AddQuoteToken(address(_lender), 4_000.927678580567537368 * 1e18, 10_000 * 1e18, 99836282890);
        _lender.addQuoteToken(_pool, 10_000 * 1e18, 4895);

        assertEq(_pool.htp(), 0);
        assertEq(_pool.lup(), 99836282890);

        assertEq(_pool.treeSum(),                         10_000 * 1e18);
        assertEq(_pool.depositAccumulator(),              10_000 * 1e18);
        assertEq(_pool.lpBalance(4895, address(_lender)), 10_000 * 1e18);

        // check balances
        assertEq(_quote.balanceOf(address(_pool)),   10_000 * 1e18);
        assertEq(_quote.balanceOf(address(_lender)), 190_000 * 1e18);

        // check bucket balance
        (uint256 lpAccumulator, uint256 availableCollateral) = _pool.buckets(4895);
        assertEq(lpAccumulator,       10_000 * 1e18);
        assertEq(availableCollateral, 0);

        // test 20_000 DAI deposit at price of 1 MKR = 2000.221618840727700609 DAI
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(_lender), address(_pool), 20_000 * 1e18);
        vm.expectEmit(true, true, false, true);
        emit AddQuoteToken(address(_lender), 2_000.221618840727700609 * 1e18, 20_000 * 1e18, 99836282890);
        _lender.addQuoteToken(_pool, 20_000 * 1e18, 4756);

        assertEq(_pool.htp(), 0);
        assertEq(_pool.lup(), 99836282890);

        assertEq(_pool.treeSum(),                         30_000 * 1e18);
        assertEq(_pool.depositAccumulator(),              30_000 * 1e18);
        assertEq(_pool.lpBalance(4756, address(_lender)), 20_000 * 1e18);

        // check balances
        assertEq(_quote.balanceOf(address(_pool)),   30_000 * 1e18);
        assertEq(_quote.balanceOf(address(_lender)), 170_000 * 1e18);

        // check bucket balance
        (lpAccumulator, availableCollateral) = _pool.buckets(4756);
        assertEq(lpAccumulator,       20_000 * 1e18);
        assertEq(availableCollateral, 0);

        // test 40_000 DAI deposit at price of 1 MKR = 5000 DAI
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(_lender), address(_pool), 40_000 * 1e18);
        vm.expectEmit(true, true, false, true);
        emit AddQuoteToken(address(_lender), 5_007.644384905151472283 * 1e18, 40_000 * 1e18, 99836282890);
        _lender.addQuoteToken(_pool, 40_000 * 1e18, 4940);

        assertEq(_pool.htp(), 0);
        assertEq(_pool.lup(), 99836282890);

        assertEq(_pool.treeSum(),                         70_000 * 1e18);
        assertEq(_pool.depositAccumulator(),              70_000 * 1e18);
        assertEq(_pool.lpBalance(4940, address(_lender)), 40_000 * 1e18);

        // check balances
        assertEq(_quote.balanceOf(address(_pool)),   70_000 * 1e18);
        assertEq(_quote.balanceOf(address(_lender)), 130_000 * 1e18);

        // check bucket balance
        (lpAccumulator, availableCollateral) = _pool.buckets(4940);
        assertEq(lpAccumulator,       40_000 * 1e18);
        assertEq(availableCollateral, 0);
    }

}
