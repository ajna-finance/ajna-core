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
        emit AddQuoteToken(address(_lender), _p4000, 10_000 * 1e18, 0.000000099836282890 * 1e18);
        _lender.addQuoteToken(_pool, 10_000 * 1e18, _p4000);

        assertEq(_pool.htp(), 0);
        assertEq(_pool.lup(), 0.000000099836282890 * 1e18);

        assertEq(_pool.sum(),                             10_000 * 1e18);
        assertEq(_pool.depositAccumulator(),              10_000 * 1e18);
        assertEq(_pool.lpBalance(1663, address(_lender)), 10_000 * 1e18);

        // check balances
        assertEq(_quote.balanceOf(address(_pool)),   10_000 * 1e18);
        assertEq(_quote.balanceOf(address(_lender)), 190_000 * 1e18);

        // check bucket balance
        (uint256 lpAccumulator, uint256 availableCollateral) = _pool.buckets(1663);
        assertEq(lpAccumulator,       10_000 * 1e18);
        assertEq(availableCollateral, 0);

        // test 20_000 DAI deposit at price of 1 MKR = 2000.221618840727700609 DAI
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(_lender), address(_pool), 20_000 * 1e18);
        vm.expectEmit(true, true, false, true);
        emit AddQuoteToken(address(_lender), _p2000, 20_000 * 1e18, 0.000000099836282890 * 1e18);
        _lender.addQuoteToken(_pool, 20_000 * 1e18, _p2000);

        assertEq(_pool.htp(), 0);
        assertEq(_pool.lup(), 0.000000099836282890 * 1e18);

        assertEq(_pool.sum(),                             30_000 * 1e18);
        assertEq(_pool.depositAccumulator(),              30_000 * 1e18);
        assertEq(_pool.lpBalance(1524, address(_lender)), 20_000 * 1e18);

        // check balances
        assertEq(_quote.balanceOf(address(_pool)),   30_000 * 1e18);
        assertEq(_quote.balanceOf(address(_lender)), 170_000 * 1e18);

        // check bucket balance
        (lpAccumulator, availableCollateral) = _pool.buckets(1524);
        assertEq(lpAccumulator,       20_000 * 1e18);
        assertEq(availableCollateral, 0);

        // test 40_000 DAI deposit at price of 1 MKR = 5000 DAI
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(_lender), address(_pool), 40_000 * 1e18);
        vm.expectEmit(true, true, false, true);
        emit AddQuoteToken(address(_lender), _p5007, 40_000 * 1e18, 0.000000099836282890 * 1e18);
        _lender.addQuoteToken(_pool, 40_000 * 1e18, _p5007);

        assertEq(_pool.htp(), 0);
        assertEq(_pool.lup(), 0.000000099836282890 * 1e18);

        assertEq(_pool.sum(),                             70_000 * 1e18);
        assertEq(_pool.depositAccumulator(),              70_000 * 1e18);
        assertEq(_pool.lpBalance(1708, address(_lender)), 40_000 * 1e18);

        // check balances
        assertEq(_quote.balanceOf(address(_pool)),   70_000 * 1e18);
        assertEq(_quote.balanceOf(address(_lender)), 130_000 * 1e18);

        // check bucket balance
        (lpAccumulator, availableCollateral) = _pool.buckets(1708);
        assertEq(lpAccumulator,       40_000 * 1e18);
        assertEq(availableCollateral, 0);
    }

}
