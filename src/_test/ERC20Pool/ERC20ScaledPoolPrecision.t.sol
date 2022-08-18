// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.14;

import { ERC20Pool }        from "../../erc20/ERC20Pool.sol";
import { ERC20PoolFactory } from "../../erc20/ERC20PoolFactory.sol";

import { BucketMath } from "../../libraries/BucketMath.sol";
import { Maths }      from "../../libraries/Maths.sol";

import { DSTestPlus }         from "../utils/DSTestPlus.sol";
import { TokenWithNDecimals } from "../utils/Tokens.sol";

contract ERC20ScaledPoolPrecisionTest is DSTestPlus {

    uint256 internal _lpPoolPrecision         = 10**27;
    uint256 internal _quotePoolPrecision      = 10**18;
    uint256 internal _collateralPoolPrecision = 10**18;
    uint256 internal _collateralPrecision;
    uint256 internal _quotePrecision;

    address internal _borrower;
    address internal _borrower2;
    address internal _borrower3;
    address internal _lender;
    address internal _bidder;

    TokenWithNDecimals internal _collateral;
    TokenWithNDecimals internal _quote;
    ERC20Pool          internal _pool;

    function init(uint256 collateralPrecisionDecimals_, uint256 quotePrecisionDecimals_) internal {
        _collateral = new TokenWithNDecimals("Collateral", "C", uint8(collateralPrecisionDecimals_));
        _quote      = new TokenWithNDecimals("Quote", "Q", uint8(quotePrecisionDecimals_));
        _pool       = ERC20Pool(new ERC20PoolFactory().deployPool(address(_collateral), address(_quote), 0.05 * 10**18));

        _borrower  = makeAddr("borrower");
        _borrower2 = makeAddr("borrower2");
        _borrower3 = makeAddr("borrower2");
        _lender    = makeAddr("lender");
        _bidder    = makeAddr("bidder");

        deal(address(_collateral), _bidder,  150 * _collateralPrecision);
        deal(address(_collateral), _borrower, 150 * _collateralPrecision);
        deal(address(_collateral), _borrower2, 200 * _collateralPrecision);
        deal(address(_collateral), _borrower3, 200 * _collateralPrecision);

        deal(address(_quote), _lender,  200_000 * _quotePrecision);

        vm.startPrank(_borrower);
        _collateral.approve(address(_pool), 150 * _collateralPrecision);
        _quote.approve(address(_pool), 200_000 * _quotePrecision);

        changePrank(_borrower2);
        _collateral.approve(address(_pool), 200 * _collateralPrecision);
        _quote.approve(address(_pool), 200_000 * _quotePrecision);

        changePrank(_borrower3);
        _collateral.approve(address(_pool), 200 * _collateralPrecision);
        _quote.approve(address(_pool), 200_000 * _quotePrecision);

        changePrank(_bidder);
        _collateral.approve(address(_pool), 200_000 * _collateralPrecision);

        changePrank(_lender);
        _quote.approve(address(_pool), 200_000 * _quotePrecision);
    }

    function testAddRemoveQuotePrecision(uint8 collateralPrecisionDecimals_, uint8 quotePrecisionDecimals_) external virtual {
        // setup fuzzy bounds and initialize the pool
        uint256 boundColPrecision = bound(uint256(collateralPrecisionDecimals_), 1, 18);
        uint256 boundQuotePrecision = bound(uint256(quotePrecisionDecimals_), 1, 18);
        _collateralPrecision = uint256(10) ** boundColPrecision;
        _quotePrecision = uint256(10) ** boundQuotePrecision;

        init(boundColPrecision, boundQuotePrecision);

        // deposit 50_000 quote tokens into each of 3 buckets
        _pool.addQuoteToken(50_000 * _quotePoolPrecision, 2549);
        _pool.addQuoteToken(50_000 * _quotePoolPrecision, 2550);
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(_lender), address(_pool), 50_000 * _quotePrecision);
        vm.expectEmit(true, true, false, true);
        emit AddQuoteToken(address(_lender), _pool.indexToPrice(2551), 50_000 * _quotePoolPrecision, BucketMath.MAX_PRICE);
        _pool.addQuoteToken(50_000 * _quotePoolPrecision, 2551);

        // check balances
        assertEq(_quote.balanceOf(address(_pool)),   150_000 * _quotePrecision);
        assertEq(_quote.balanceOf(address(_lender)), 50_000 * _quotePrecision);

        // check initial pool state
        assertEq(_pool.htp(), 0);
        assertEq(_pool.lup(), BucketMath.MAX_PRICE);

        assertEq(_pool.poolSize(),                        150_000 * _quotePoolPrecision);
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
        _pool.removeQuoteToken(25_000 * _quotePoolPrecision, 2549);

        // check balances
        assertEq(_quote.balanceOf(address(_pool)),   125_000 * _quotePrecision);
        assertEq(_quote.balanceOf(address(_lender)), 75_000 * _quotePrecision);

        // check pool state
        assertEq(_pool.htp(), 0);
        assertEq(_pool.lup(), BucketMath.MAX_PRICE);

        assertEq(_pool.poolSize(),                        125_000 * _quotePoolPrecision);
        assertEq(_pool.lpBalance(2549, address(_lender)), 25_000 * _lpPoolPrecision);
        assertEq(_pool.exchangeRate(2549),                     1 * _lpPoolPrecision);

        // check bucket balance
        (lpAccumulator, availableCollateral) = _pool.buckets(2549);
        assertEq(lpAccumulator,       25_000 * _lpPoolPrecision);
        assertEq(availableCollateral, 0);
    }

    function testBorrowRepayPrecision(uint8 collateralPrecisionDecimals_, uint8 quotePrecisionDecimals_) external virtual {
        // setup fuzzy bounds and initialize the pool
        uint256 boundColPrecision = bound(uint256(collateralPrecisionDecimals_), 1, 18);
        uint256 boundQuotePrecision = bound(uint256(quotePrecisionDecimals_), 1, 18);
        _collateralPrecision = uint256(10) ** boundColPrecision;
        _quotePrecision = uint256(10) ** boundQuotePrecision;

        init(boundColPrecision, boundQuotePrecision);

        // deposit 50_000 quote tokens into each of 3 buckets
        _pool.addQuoteToken(50_000 * _quotePoolPrecision, 2549);
        _pool.addQuoteToken(50_000 * _quotePoolPrecision, 2550);
        _pool.addQuoteToken(50_000 * _quotePoolPrecision, 2551);

        // borrowers adds collateral
        changePrank(_borrower);
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(_borrower), address(_pool), 50 * _collateralPrecision);
        vm.expectEmit(true, true, false, true);
        emit PledgeCollateral(address(_borrower), 50 * _collateralPoolPrecision);
        _pool.pledgeCollateral(50 * _collateralPoolPrecision, address(0), address(0));

        // check balances
        assertEq(_collateral.balanceOf(address(_pool)),   50 * _collateralPrecision);
        assertEq(_collateral.balanceOf(address(_borrower)), 100 * _collateralPrecision);
        assertEq(_quote.balanceOf(address(_pool)),   150_000 * _quotePrecision);
        assertEq(_quote.balanceOf(address(_borrower)), 0);

        // check pool state
        assertEq(_pool.htp(), 0);
        assertEq(_pool.lup(), BucketMath.MAX_PRICE);
        assertEq(address(_pool.loanQueueHead()), address(0));

        assertEq(_pool.poolSize(),                        150_000 * _quotePoolPrecision);
        assertEq(_pool.lpBalance(2549, address(_lender)), 50_000 * _lpPoolPrecision);
        assertEq(_pool.exchangeRate(2549),                     1 * _lpPoolPrecision);

        // borrower borrows
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(_pool), address(_borrower), 10_000 * _quotePrecision);
        vm.expectEmit(true, true, false, true);
        emit Borrow(address(_borrower), _pool.indexToPrice(2549), 10_000 * _quotePoolPrecision);
        _pool.borrow(10_000 * _quotePoolPrecision, 3000, address(0), address(0));

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

        assertEq(_pool.borrowerDebt(),      debt);
        assertEq(_pool.pledgedCollateral(), col);
        assertEq(_pool.lenderDebt(),        10_000 * _quotePoolPrecision);

        assertEq(_pool.poolSize(),                        150_000 * _quotePoolPrecision);
        assertEq(_pool.lpBalance(2549, address(_lender)), 50_000 * _lpPoolPrecision);
        assertEq(_pool.exchangeRate(2549),                     1 * _lpPoolPrecision);

        // borrower repays half of loan
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(_borrower), address(_pool), 5_000 * _quotePrecision);
        vm.expectEmit(true, true, false, true);
        emit Repay(address(_borrower), _pool.indexToPrice(2549), 5_000 * _quotePoolPrecision);
        _pool.repay(5_000 * _quotePoolPrecision, address(0), address(0));

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

        assertEq(_pool.borrowerDebt(),      debt);
        assertEq(_pool.pledgedCollateral(), col);

        assertEq(_pool.poolSize(),                        150_000 * _quotePoolPrecision);
        assertEq(_pool.lpBalance(2549, address(_lender)), 50_000 * _lpPoolPrecision);
        assertEq(_pool.exchangeRate(2549),                     1 * _lpPoolPrecision);

        // remove all of the remaining unencumbered collateral
        uint256 unencumberedCollateral = col - _pool.encumberedCollateral(debt, _pool.lup());
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(_pool), address(_borrower), unencumberedCollateral / _pool.collateralScale());
        vm.expectEmit(true, true, false, true);
        emit PullCollateral(address(_borrower), unencumberedCollateral);
        _pool.pullCollateral(unencumberedCollateral, address(0), address(0));

        //  FIXME: check balances
        // assertEq(_collateral.balanceOf(address(_pool)),   1.7 * _collateralPrecision);
        // assertEq(_collateral.balanceOf(address(_borrower)), 148.30 * _collateralPrecision);
        assertEq(_quote.balanceOf(address(_pool)),   145_000 * _quotePrecision);
        assertEq(_quote.balanceOf(address(_borrower)), 5_000 * _quotePrecision);

        // check pool state
        (debt, , col,) = _pool.borrowerInfo(address(_borrower));
        assertEq(_pool.htp(), Maths.wdiv(debt, col));
        assertEq(_pool.lup(), _pool.indexToPrice(2549));
        assertEq(address(_pool.loanQueueHead()), address(_borrower));

        assertEq(_pool.borrowerDebt(),      debt);
        assertEq(_pool.pledgedCollateral(), col); 
    }

    // TODO: Rework this test to do something useful, now that the purchase feature has been eliminated.
    function skip_testPurchaseClaimPrecision(uint8 collateralPrecisionDecimals_, uint8 quotePrecisionDecimals_) external virtual {
        // setup fuzzy bounds and initialize the pool
        uint256 boundColPrecision = bound(uint256(collateralPrecisionDecimals_), 1, 18);
        uint256 boundQuotePrecision = bound(uint256(quotePrecisionDecimals_), 1, 18);
        _collateralPrecision = uint256(10) ** boundColPrecision;
        _quotePrecision = uint256(10) ** boundQuotePrecision;

        init(boundColPrecision, boundQuotePrecision);

        // deposit 50_000 quote tokens into each of 3 buckets
        _pool.addQuoteToken(50_000 * _quotePoolPrecision, 2549);
        _pool.addQuoteToken(50_000 * _quotePoolPrecision, 2550);
        _pool.addQuoteToken(50_000 * _quotePoolPrecision, 2551);

        // bidder purchases quote with collateral
        changePrank(_bidder);
        uint256 quoteToPurchase = 500 * _quotePoolPrecision;
        uint256 collateralRequired = Maths.wdiv(quoteToPurchase, _pool.indexToPrice(2549));
        uint256 adjustedCollateralReq = collateralRequired / _pool.collateralScale();
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(_bidder), address(_pool), adjustedCollateralReq);
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(_pool), address(_bidder), 500 * _quotePrecision);
        vm.expectEmit(true, true, false, true);
        emit Purchase(address(_bidder), _pool.indexToPrice(2549), quoteToPurchase, collateralRequired);
//        _bidder.purchaseQuote(_pool, quoteToPurchase, 2549);

        // check bucket state
        (uint256 lpAccumulatorStateOne, uint256 availableCollateral) = _pool.buckets(2549);
        assertEq(availableCollateral, collateralRequired);
        assertGt(availableCollateral, 0);
        assertEq(lpAccumulatorStateOne,       _pool.lpBalance(2549, address(_lender)));
        assertGt(lpAccumulatorStateOne,       0);

        // check balances
        assertEq(_collateral.balanceOf(address(_pool)),   adjustedCollateralReq);
        assertEq(_collateral.balanceOf(address(_bidder)), 150 * _collateralPrecision - adjustedCollateralReq);
        assertEq(_quote.balanceOf(address(_pool)),   150_000 * _quotePrecision - 500 * _quotePrecision);
        assertEq(_quote.balanceOf(address(_bidder)), 500 * _quotePrecision);

        // check pool state
        assertEq(_pool.htp(), 0);
        assertEq(_pool.lup(), BucketMath.MAX_PRICE);

        assertEq(_pool.poolSize(),                        149_500 * _quotePoolPrecision);
        assertEq(_pool.lpBalance(2549, address(_lender)), 50_000 * _lpPoolPrecision);

        // lender claims newly available collateral from bucket
        changePrank(_lender);
        uint256 lpRedemption = Maths.wrdivr(Maths.wmul(availableCollateral, _pool.indexToPrice(2549)), _pool.exchangeRate(2549));
        vm.expectEmit(true, true, true, true);
        emit Transfer(address(_pool), address(_lender), adjustedCollateralReq);
        vm.expectEmit(true, true, true, true);
        emit ClaimCollateral(address(_lender), _pool.indexToPrice(2549), availableCollateral, lpRedemption);
//        _lender.claimCollateral(_pool, availableCollateral, 2549);

        // check bucket state
        (uint256 lpAccumulatorStateTwo, uint256 availableCollateralStateTwo) = _pool.buckets(2549);
        assertEq(availableCollateralStateTwo, 0);
        assertEq(lpAccumulatorStateTwo,       _pool.lpBalance(2549, address(_lender)));
        assertGt(lpAccumulatorStateTwo,       0);
        assertLt(lpAccumulatorStateTwo, lpAccumulatorStateOne);

        // check balances
        assertEq(_collateral.balanceOf(address(_pool)),   0);
        assertEq(_collateral.balanceOf(address(_bidder)), 150 * _collateralPrecision - adjustedCollateralReq);
        assertEq(_collateral.balanceOf(address(_lender)), adjustedCollateralReq);
        assertEq(_quote.balanceOf(address(_pool)),   150_000 * _quotePrecision - 500 * _quotePrecision);
        assertEq(_quote.balanceOf(address(_bidder)), 500 * _quotePrecision);

        // check pool state
        assertEq(_pool.htp(),      0);
        assertEq(_pool.lup(),      BucketMath.MAX_PRICE);
        assertEq(_pool.poolSize(), 149_500 * _quotePoolPrecision);
    }
}
