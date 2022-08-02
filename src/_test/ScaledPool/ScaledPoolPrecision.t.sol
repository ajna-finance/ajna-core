// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.14;

import { ScaledPool }        from "../../ScaledPool.sol";
import { ScaledPoolFactory } from "../../ScaledPoolFactory.sol";

import { BucketMath }        from "../../libraries/BucketMath.sol";
import { Maths }             from "../../libraries/Maths.sol";

import { DSTestPlus }                                    from "../utils/DSTestPlus.sol";
import { CollateralToken, CollateralTokenWith6Decimals } from "../utils/Tokens.sol";
import { QuoteToken, QuoteTokenWith6Decimals }           from "../utils/Tokens.sol";
import { UserWithCollateralInScaledPool, UserWithQuoteTokenInScaledPool } from "../utils/Users.sol";


contract ScaledPoolPrecisionTest is DSTestPlus {

    uint256 internal _lpPoolPrecision         = 10**27;
    uint256 internal _quotePoolPrecision      = 10**18;
    uint256 internal _collateralPoolPrecision = 10**18;
    uint256 internal _collateralPrecision;
    uint256 internal _quotePrecision;

    address                        internal _poolAddress;
    CollateralToken                internal _collateral;
    ScaledPool                     internal _pool;
    QuoteToken                     internal _quote;
    UserWithCollateralInScaledPool internal _borrower;
    UserWithCollateralInScaledPool internal _borrower2;
    UserWithCollateralInScaledPool internal _borrower3;
    UserWithQuoteTokenInScaledPool internal _lender;
    UserWithQuoteTokenInScaledPool internal _bidder;

    function setUp() external virtual {
        _collateralPrecision = 10**18;
        _quotePrecision      = 10**18;
        _collateral          = new CollateralToken();
        _quote               = new QuoteToken();

        init();
    }

    function init() internal {
        _poolAddress = new ScaledPoolFactory().deployPool(address(_collateral), address(_quote), 0.05 * 10**18);
        _pool        = ScaledPool(_poolAddress);

        _borrower    = new UserWithCollateralInScaledPool();
        _borrower2   = new UserWithCollateralInScaledPool();
        _borrower3   = new UserWithCollateralInScaledPool();
        _bidder      = new UserWithQuoteTokenInScaledPool();
        _lender      = new UserWithQuoteTokenInScaledPool();

        _collateral.mint(address(_borrower), 150 * _collateralPrecision);
        _collateral.mint(address(_borrower2), 200 * _collateralPrecision);
        _collateral.mint(address(_borrower3), 200 * _collateralPrecision);
        _quote.mint(address(_bidder), 200_000 * _quotePrecision);
        _quote.mint(address(_lender), 200_000 * _quotePrecision);

        _borrower.approveToken(_collateral, address(_pool), 150 * _collateralPrecision);
        _borrower.approveToken(_quote,      address(_pool), 200_000 * _quotePrecision);

        _borrower2.approveToken(_collateral, address(_pool), 200 * _collateralPrecision);
        _borrower2.approveToken(_quote,      address(_pool), 200_000 * _quotePrecision);

        _borrower3.approveToken(_collateral, address(_pool), 200 * _collateralPrecision);
        _borrower3.approveToken(_quote,      address(_pool), 200_000 * _quotePrecision);

        _bidder.approveToken(_quote,  address(_pool), 200_000 * _quotePrecision);
        _lender.approveToken(_quote,  address(_pool), 200_000 * _quotePrecision);
    }

    function testAddRemoveQuotePrecision() external virtual {
        // deposit 50_000 quote tokens into each of 3 buckets
        _lender.addQuoteToken(_pool, 50_000 * _quotePoolPrecision, 2549);
        _lender.addQuoteToken(_pool, 50_000 * _quotePoolPrecision, 2550);
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(_lender), address(_pool), 50_000 * _quotePrecision);
        vm.expectEmit(true, true, false, true);
        emit AddQuoteToken(address(_lender), _pool.indexToPrice(2551), 50_000 * _quotePoolPrecision, BucketMath.MAX_PRICE);
        _lender.addQuoteToken(_pool, 50_000 * _quotePoolPrecision, 2551);

        // check balances
        assertEq(_quote.balanceOf(address(_pool)),   150_000 * _quotePrecision);
        assertEq(_quote.balanceOf(address(_lender)), 50_000 * _quotePrecision);

        // check initial pool state
        assertEq(_pool.htp(), 0);
        assertEq(_pool.lup(), BucketMath.MAX_PRICE);

        assertEq(_pool.treeSum(),                         150_000 * _quotePoolPrecision);
        assertEq(_pool.lpBalance(2549, address(_lender)), 50_000 * _lpPoolPrecision);
        assertEq(_pool.exchangeRate(2549),                     1 * _lpPoolPrecision);

        // check bucket balance
        (uint256 lpAccumulator, uint256 availableCollateral) = _pool.buckets(2549);
        assertEq(lpAccumulator,       50_000 * _lpPoolPrecision);
        assertEq(availableCollateral, 0);

        // lender removes some quote token from highest priced bucket
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(_pool), address(_lender), 25_000 * _quotePrecision);
        vm.expectEmit(true, true, false, true);
        emit RemoveQuoteToken(address(_lender), _pool.indexToPrice(2549), 25_000 * _quotePoolPrecision, BucketMath.MAX_PRICE);
        _lender.removeQuoteToken(_pool, 25_000 * _lpPoolPrecision, 2549);

        // check balances
        assertEq(_quote.balanceOf(address(_pool)),   125_000 * _quotePrecision);
        assertEq(_quote.balanceOf(address(_lender)), 75_000 * _quotePrecision);

        // check pool state
        assertEq(_pool.htp(), 0);
        assertEq(_pool.lup(), BucketMath.MAX_PRICE);

        assertEq(_pool.treeSum(),                         125_000 * _quotePoolPrecision);
        assertEq(_pool.lpBalance(2549, address(_lender)), 25_000 * _lpPoolPrecision);
        assertEq(_pool.exchangeRate(2549),                     1 * _lpPoolPrecision);

        // check bucket balance
        (lpAccumulator, availableCollateral) = _pool.buckets(2549);
        assertEq(lpAccumulator,       25_000 * _lpPoolPrecision);
        assertEq(availableCollateral, 0);
    }

    function testBorrowRepayPrecision() external virtual {
        // deposit 50_000 quote tokens into each of 3 buckets
        _lender.addQuoteToken(_pool, 50_000 * _quotePoolPrecision, 2549);
        _lender.addQuoteToken(_pool, 50_000 * _quotePoolPrecision, 2550);
        _lender.addQuoteToken(_pool, 50_000 * _quotePoolPrecision, 2551);

        // borrowers adds collateral
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(_borrower), address(_pool), 50 * _collateralPrecision);
        vm.expectEmit(true, true, false, true);
        emit AddCollateral(address(_borrower), 50 * _collateralPoolPrecision);
        _borrower.addCollateral(_pool, 50 * _collateralPoolPrecision, address(0), address(0));

        // check balances
        assertEq(_collateral.balanceOf(address(_pool)),   50 * _collateralPrecision);
        assertEq(_collateral.balanceOf(address(_borrower)), 100 * _collateralPrecision);
        assertEq(_quote.balanceOf(address(_pool)),   150_000 * _quotePrecision);
        assertEq(_quote.balanceOf(address(_borrower)), 0);

        // check pool state
        assertEq(_pool.htp(), 0);
        assertEq(_pool.lup(), BucketMath.MAX_PRICE);
        assertEq(address(_pool.loanQueueHead()), address(0));

        assertEq(_pool.treeSum(),                         150_000 * _quotePoolPrecision);
        assertEq(_pool.lpBalance(2549, address(_lender)), 50_000 * _lpPoolPrecision);
        assertEq(_pool.exchangeRate(2549),                     1 * _lpPoolPrecision);

        // borrower borrows
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(_pool), address(_borrower), 10_000 * _quotePrecision);
        vm.expectEmit(true, true, false, true);
        emit Borrow(address(_borrower), _pool.indexToPrice(2549), 10_000 * _quotePoolPrecision);
        _borrower.borrow(_pool, 10_000 * _quotePoolPrecision, 3000, address(0), address(0));

        // check balances
        assertEq(_collateral.balanceOf(address(_pool)),   50 * _collateralPrecision);
        assertEq(_collateral.balanceOf(address(_borrower)), 100 * _collateralPrecision);
        assertEq(_quote.balanceOf(address(_pool)),   140_000 * _quotePrecision);
        assertEq(_quote.balanceOf(address(_borrower)), 10_000 * _quotePrecision);

        // check pool state
        (uint256 debt, , uint256 col,) = _pool.borrowerInfo(address(_borrower));
        assertEq(_pool.htp(), Maths.wdiv(debt, col));
        assertEq(_pool.lup(), _pool.indexToPrice(2549));
        assertEq(address(_pool.loanQueueHead()), address(_borrower));

        assertEq(_pool.treeSum(),                         150_000 * _quotePoolPrecision);
        assertEq(_pool.lpBalance(2549, address(_lender)), 50_000 * _lpPoolPrecision);
        assertEq(_pool.exchangeRate(2549),                     1 * _lpPoolPrecision);

        // borrower repays half of loan
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(_borrower), address(_pool), 5_000 * _quotePrecision);
        vm.expectEmit(true, true, false, true);
        emit Repay(address(_borrower), _pool.indexToPrice(2549), 5_000 * _quotePoolPrecision);
        _borrower.repay(_pool, 5_000 * _quotePoolPrecision, address(0), address(0));

        // check balances
        assertEq(_collateral.balanceOf(address(_pool)),   50 * _collateralPrecision);
        assertEq(_collateral.balanceOf(address(_borrower)), 100 * _collateralPrecision);
        assertEq(_quote.balanceOf(address(_pool)),   145_000 * _quotePrecision);
        assertEq(_quote.balanceOf(address(_borrower)), 5_000 * _quotePrecision);

        // check pool state
        (debt, , col,) = _pool.borrowerInfo(address(_borrower));
        assertEq(_pool.htp(), Maths.wdiv(debt, col));
        assertEq(_pool.lup(), _pool.indexToPrice(2549));
        assertEq(address(_pool.loanQueueHead()), address(_borrower));

        assertEq(_pool.treeSum(),                         150_000 * _quotePoolPrecision);
        assertEq(_pool.lpBalance(2549, address(_lender)), 50_000 * _lpPoolPrecision);
        assertEq(_pool.exchangeRate(2549),                     1 * _lpPoolPrecision);
    }

    function testPurchaseClaimPrecision() external virtual {

    }
}

contract CollateralAndQuoteWith6DecimalPrecisionTest is ScaledPoolPrecisionTest {

    function setUp() external override {
        _collateralPrecision = 10**6;
        _quotePrecision      = 10**6;
        _collateral          = new CollateralTokenWith6Decimals();
        _quote               = new QuoteTokenWith6Decimals();

        init();
    }

}

// TODO: add fuzzy test with arbitrary decimals