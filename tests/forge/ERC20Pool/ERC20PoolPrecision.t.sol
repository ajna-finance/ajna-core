// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.14;

import '@openzeppelin/contracts/utils/structs/EnumerableSet.sol';

import { ERC20DSTestPlus }    from './ERC20DSTestPlus.sol';
import { TokenWithNDecimals } from '../utils/Tokens.sol';

import 'src/erc20/ERC20Pool.sol';
import 'src/erc20/ERC20PoolFactory.sol';

import 'src/base/PoolInfoUtils.sol';

import 'src/libraries/Maths.sol';

contract ERC20PoolPrecisionTest is ERC20DSTestPlus {

    using EnumerableSet for EnumerableSet.AddressSet;
    using EnumerableSet for EnumerableSet.UintSet;

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

    function init(uint256 collateralPrecisionDecimals_, uint256 quotePrecisionDecimals_) internal {
        _collateral = new TokenWithNDecimals("Collateral", "C", uint8(collateralPrecisionDecimals_));
        _quote      = new TokenWithNDecimals("Quote", "Q", uint8(quotePrecisionDecimals_));
        _pool       = ERC20Pool(new ERC20PoolFactory(_ajna).deployPool(address(_collateral), address(_quote), 0.05 * 10**18));
        _poolUtils  = new PoolInfoUtils();

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

        skip(1 days); // to avoid deposit time 0 equals bucket bankruptcy time
    }

    function testAddRemoveQuotePrecision(uint8 collateralPrecisionDecimals_, uint8 quotePrecisionDecimals_) external virtual tearDown {
        // setup fuzzy bounds and initialize the pool
        uint256 boundColPrecision = bound(uint256(collateralPrecisionDecimals_), 1, 18);
        uint256 boundQuotePrecision = bound(uint256(quotePrecisionDecimals_), 1, 18);
        _collateralPrecision = uint256(10) ** boundColPrecision;
        _quotePrecision = uint256(10) ** boundQuotePrecision;

        init(boundColPrecision, boundQuotePrecision);

        // deposit 50_000 quote tokens into each of 3 buckets
        _addInitialLiquidity(
            {
                from:   _lender,
                amount: 50_000 * _quotePoolPrecision,
                index:  2549
            }
        );
        _addInitialLiquidity(
            {
                from:   _lender,
                amount: 50_000 * _quotePoolPrecision,
                index:  2550
            }
        );
        _addInitialLiquidity(
            {
                from:   _lender,
                amount: 50_000 * _quotePoolPrecision,
                index:  2551
            }
        );

        // check balances
        assertEq(_quote.balanceOf(address(_pool)), 150_000 * _quotePrecision);
        assertEq(_quote.balanceOf(_lender),        50_000 * _quotePrecision);

        // check initial pool state
        _assertPoolPrices(
            {
                htp:      0,
                htpIndex: 7388,
                hpb:      3_025.946482308870940904 * 1e18,
                hpbIndex: 2549,
                lup:      MAX_PRICE,
                lupIndex: 0
            }
        );
        _assertLoans(
            {
                noOfLoans:         0,
                maxBorrower:       address(0),
                maxThresholdPrice: 0
            }
        );
        assertEq(_pool.depositSize(), 150_000 * _quotePoolPrecision);

        // check bucket balance
        _assertBucket(
            {
                index:        2549,
                lpBalance:    50_000 * 1e27,
                collateral:   0,
                deposit:      50_000 * _quotePoolPrecision,
                exchangeRate: 1 * _lpPoolPrecision
            }
        );
        _assertLenderLpBalance(
            {
                lender:      _lender,
                index:       2549,
                lpBalance:   50_000 * 1e27,
                depositTime: 1 days
            }
        );

        skip(1 days); // skip to avoid penalty
        // lender removes some quote token from highest priced bucket
        _removeLiquidity(
            {
                from:     _lender,
                amount:   25_000 * _quotePoolPrecision,
                index:    2549,
                newLup:   MAX_PRICE,
                lpRedeem: 25_000 * 1e27
            }
        );

        // check balances
        assertEq(_quote.balanceOf(address(_pool)), 125_000 * _quotePrecision);
        assertEq(_quote.balanceOf(_lender),        75_000 * _quotePrecision);

        // check pool state
        _assertPoolPrices(
            {
                htp:      0,
                htpIndex: 7388,
                hpb:      3_025.946482308870940904 * 1e18,
                hpbIndex: 2549,
                lup:      MAX_PRICE,
                lupIndex: 0
            }
        );
        _assertLoans(
            {
                noOfLoans:         0,
                maxBorrower:       address(0),
                maxThresholdPrice: 0
            }
        );
        assertEq(_pool.depositSize(), 125_000 * _quotePoolPrecision);

        // check bucket balance
        _assertBucket(
            {
                index:        2549,
                lpBalance:    25_000 * 1e27,
                collateral:   0,
                deposit:      25_000 * _quotePoolPrecision,
                exchangeRate: 1 * 1e27
            }
        );
        _assertLenderLpBalance(
            {
                lender:      _lender,
                index:       2549,
                lpBalance:   25_000 * _lpPoolPrecision,
                depositTime: 1 days
            }
        );
    }

    function testBorrowRepayPrecision(uint8 collateralPrecisionDecimals_, uint8 quotePrecisionDecimals_) external virtual tearDown {
        // setup fuzzy bounds and initialize the pool
        uint256 boundColPrecision = bound(uint256(collateralPrecisionDecimals_), 1, 18);
        uint256 boundQuotePrecision = bound(uint256(quotePrecisionDecimals_), 1, 18);
        _collateralPrecision = uint256(10) ** boundColPrecision;
        _quotePrecision = uint256(10) ** boundQuotePrecision;

        init(boundColPrecision, boundQuotePrecision);

        _addInitialLiquidity(
            {
                from:   _lender,
                amount: 50_000 * _quotePoolPrecision,
                index:  2549
            }
        );
        _addInitialLiquidity(
            {
                from:   _lender,
                amount: 50_000 * _quotePoolPrecision,
                index:  2550
            }
        );
        _addInitialLiquidity(
            {
                from:   _lender,
                amount: 50_000 * _quotePoolPrecision,
                index:  2551
            }
        );

        // borrowers adds collateral
        _pledgeCollateral(
            {
                from:     _borrower,
                borrower: _borrower,
                amount:   50 * _collateralPoolPrecision
            }
        );

        // check balances
        assertEq(_collateral.balanceOf(address(_pool)), 50 * _collateralPrecision);
        assertEq(_collateral.balanceOf(_borrower),      100 * _collateralPrecision);
        assertEq(_quote.balanceOf(address(_pool)), 150_000 * _quotePrecision);
        assertEq(_quote.balanceOf(_borrower),      0);

        // check pool state
        _assertPoolPrices(
            {
                htp:      0,
                htpIndex: 7388,
                hpb:      3_025.946482308870940904 * 1e18,
                hpbIndex: 2549,
                lup:      MAX_PRICE,
                lupIndex: 0
            }
        );
        _assertLoans(
            {
                noOfLoans:         0,
                maxBorrower:       address(0),
                maxThresholdPrice: 0
            }
        );
        assertEq(_pool.depositSize(), 150_000 * _quotePoolPrecision);

        // check bucket balance
        _assertBucket(
            {
                index:        2549,
                lpBalance:    50_000 * _lpPoolPrecision,
                collateral:   0,
                deposit:      50_000 * _quotePoolPrecision,
                exchangeRate: 1 * _lpPoolPrecision
            }
        );
        _assertLenderLpBalance(
            {
                lender:      _lender,
                index:       2549,
                lpBalance:   50_000 * _lpPoolPrecision,
                depositTime: 1 days
            }
        );

        // borrower borrows
        uint256 price = _priceAt(2549);

        _borrow(
            {
                from:       _borrower,
                amount:     10_000 * _quotePoolPrecision,
                indexLimit: 3_000,
                newLup:     price
            }
        );

        // check balances
        assertEq(_collateral.balanceOf(address(_pool)),   50 * _collateralPrecision);
        assertEq(_collateral.balanceOf(_borrower), 100 * _collateralPrecision);
        assertEq(_quote.balanceOf(address(_pool)),   140_000 * _quotePrecision);
        assertEq(_quote.balanceOf(_borrower), 10_000 * _quotePrecision);

        // check pool state
        uint256 debt = 10_009.615384615384620000 * 1e18;
        uint256 col  = 50 * 1e18;
        _assertBorrower(
            {
                borrower:                  _borrower,
                borrowerDebt:              debt,
                borrowerCollateral:        col,
                borrowert0Np:              210.201923076923077020 * 1e18,
                borrowerCollateralization: 15.115198566768615646 * 1e18
            }
        );
        _assertPoolPrices(
            {
                htp:      200.192307692307692400 * 1e18,
                htpIndex: 3093,
                hpb:      3_025.946482308870940904 * 1e18,
                hpbIndex: 2549,
                lup:      price,
                lupIndex: 2549
            }
        );
        _assertLoans(
            {
                noOfLoans:         1,
                maxBorrower:       _borrower,
                maxThresholdPrice: 200.192307692307692400 * 1e18
            }
        );
        (uint256 poolDebt,,) = _pool.debtInfo();
        assertEq(_pool.depositSize(),       150_000 * _quotePoolPrecision);
        assertEq(poolDebt,                  debt);
        assertEq(_pool.pledgedCollateral(), col);

        _assertBucket(
            {
                index:        2549,
                lpBalance:    50_000 * _lpPoolPrecision,
                collateral:   0,
                deposit:      50_000 * _quotePoolPrecision,
                exchangeRate: 1 * _lpPoolPrecision
            }
        );
        _assertLenderLpBalance(
            {
                lender:      _lender,
                index:       2549,
                lpBalance:   50_000 * _lpPoolPrecision,
                depositTime: 1 days
            }
        );

        // borrower repays half of loan
        _repayDebt({
            from:             _borrower,
            borrower:         _borrower,
            amountToRepay:    5_000 * _quotePoolPrecision,
            amountRepaid:     5_000 * _quotePoolPrecision,
            collateralToPull: 0,
            newLup:           3_025.946482308870940904 * 1e18
        });

        // check balances
        assertEq(_collateral.balanceOf(address(_pool)), 50 * _collateralPrecision);
        assertEq(_collateral.balanceOf(_borrower),      100 * _collateralPrecision);

        assertEq(_quote.balanceOf(address(_pool)), 145_000 * _quotePrecision);
        assertEq(_quote.balanceOf(_borrower),      5_000 * _quotePrecision);

        // check pool state
        debt = 5_009.615384615384620000 * 1e18;
        col  = 50 * 1e18;
        _assertBorrower(
            {
                borrower:                  _borrower,
                borrowerDebt:              debt,
                borrowerCollateral:        col,
                borrowert0Np:              210.201923076923077020 * 1e18,
                borrowerCollateralization: 30.201385236096216664 * 1e18
            }
        );
        _assertPoolPrices(
            {
                htp:      100.192307692307692400 * 1e18,
                htpIndex: 3232,
                hpb:      3_025.946482308870940904 * 1e18,
                hpbIndex: 2549,
                lup:      price,
                lupIndex: 2549
            }
        );
        _assertLoans(
            {
                noOfLoans:         1,
                maxBorrower:       _borrower,
                maxThresholdPrice: 100.192307692307692400 * 1e18
            }
        );
        (poolDebt,,) = _pool.debtInfo();
        assertEq(_pool.depositSize(),       150_000 * 1e18);
        assertEq(poolDebt,                  debt);
        assertEq(_pool.pledgedCollateral(), col);

        _assertBucket(
            {
                index:        2549,
                lpBalance:    50_000 * _lpPoolPrecision,
                collateral:   0,
                deposit:      50_000 * 1e18,
                exchangeRate: 1 * 1e27
            }
        );
        _assertLenderLpBalance(
            {
                lender:      _lender,
                index:       2549,
                lpBalance:   50_000 * _lpPoolPrecision,
                depositTime: 1 days
            }
        );

        // remove all of the remaining unencumbered collateral
        uint256 unencumberedCollateral = col - _encumberedCollateral(debt, _lup());

        _repayDebtNoLupCheck({
            from:             _borrower,
            borrower:         _borrower,
            amountToRepay:    0,
            amountRepaid:     0,
            collateralToPull: unencumberedCollateral
        });

        assertEq(_collateral.balanceOf(address(_pool)),   (50 * 1e18) / ERC20Pool(address(_pool)).collateralScale() - (unencumberedCollateral / ERC20Pool(address(_pool)).collateralScale()));
        assertEq(_collateral.balanceOf(_borrower), (100 * 1e18) / ERC20Pool(address(_pool)).collateralScale() + (unencumberedCollateral / ERC20Pool(address(_pool)).collateralScale()));
        assertEq(_quote.balanceOf(address(_pool)),   145_000 * _quotePrecision);
        assertEq(_quote.balanceOf(_borrower), 5_000 * _quotePrecision);

        // check pool state
        debt = 5_009.615384615384620000 * 1e18;
        col  = 1.655553200925393083 * 1e18;
        _assertBorrower(
            {
                borrower:                  _borrower,
                borrowerDebt:              debt,
                borrowerCollateral:        col,
                borrowert0Np:              3_192.373538835858843381 * 1e18,
                borrowerCollateralization: 1 * 1e18
            }
        );
        _assertPoolPrices(
            {
                htp:      3_025.946482308870941594 * 1e18,
                htpIndex: 2549,
                hpb:      3_025.946482308870940904 * 1e18,
                hpbIndex: 2549,
                lup:      price,
                lupIndex: 2549
            }
        );
        _assertLoans(
            {
                noOfLoans:         1,
                maxBorrower:       _borrower,
                maxThresholdPrice: 3_025.946482308870941594 * 1e18
            }
        );
        (poolDebt,,) = _pool.debtInfo();
        assertEq(_pool.depositSize(),       150_000 * 1e18);
        assertEq(poolDebt,                  debt);
        assertEq(_pool.pledgedCollateral(), col);
    }

    function testFuzzedDepositTwoActorSameBucket(
        uint8   collateralPrecisionDecimals_, 
        uint8   quotePrecisionDecimals_,
        uint16  bucketId_,
        uint256 quoteAmount_,
        uint256 collateralAmount_
    ) external virtual tearDown {
        // setup fuzzy bounds and initialize the pool
        uint256 boundColPrecision   = bound(uint256(collateralPrecisionDecimals_), 1, 18);
        uint256 boundQuotePrecision = bound(uint256(quotePrecisionDecimals_),      1, 18);
        uint256 bucketId            = bound(uint256(bucketId_),                    1, 7388);
        uint256 quoteAmount         = bound(uint256(quoteAmount_),                 0, 1e22 * 1e18);
        uint256 collateralAmount    = bound(uint256(collateralAmount_),            1e8, 1e12 * 1e18);
        _collateralPrecision        = uint256(10) ** boundColPrecision;
        _quotePrecision             = uint256(10) ** boundQuotePrecision;
        init(boundColPrecision, boundQuotePrecision);

        // mint and run approvals, ignoring amounts already init approved above
        changePrank(_lender);
        deal(address(_quote), _lender, quoteAmount * _quotePrecision);
        _quote.approve(address(_pool), quoteAmount * _quotePrecision);
        changePrank(_bidder);
        deal(address(_collateral), _bidder, collateralAmount * _collateralPrecision);
        _collateral.approve(address(_pool), collateralAmount * _collateralPrecision);

        _assertBucket({
            index:        bucketId,
            lpBalance:    0,
            collateral:   0,
            deposit:      0,
            exchangeRate: 1e27
        });

        // deposit quote token and sanity check lender LPs
        _addInitialLiquidity(_lender, quoteAmount, bucketId);
        (uint256 lpBalance, uint256 time) = _pool.lenderInfo(bucketId, _lender);
        if (quoteAmount != 0) {
            assertGt(lpBalance, 0);
        } else {
            assertEq(lpBalance, 0);
        }
        assertGt(time, _startTime);

        // deposit collateral and sanity check bidder LPs
        _addCollateralWithoutCheckingLP(_bidder, collateralAmount, bucketId);
        (lpBalance, time) = _pool.lenderInfo(bucketId, _bidder);
        if (collateralAmount != 0) {
            assertGt(lpBalance, 0);
        } else {
            assertEq(lpBalance, 0);
        }
        assertGt(time, _startTime);

        // check bucket
        uint256 curDeposit;
        uint256 availableCollateral;
        (, curDeposit, availableCollateral, lpBalance,,) = _poolUtils.bucketInfo(address(_pool), bucketId);
        assertEq(curDeposit, quoteAmount);
        assertEq(availableCollateral, collateralAmount);
        if (quoteAmount + collateralAmount == 0) {
            assertEq(lpBalance, 0);
        } else {
            assertGt(lpBalance, 0);
        }
    }

    function testFuzzedDepositTwoLendersSameBucket(
        uint8   collateralPrecisionDecimals_, 
        uint8   quotePrecisionDecimals_,
        uint16  bucketId_,
        uint256 quoteAmount1_,
        uint256 quoteAmount2_
    ) external virtual tearDown {
        // setup fuzzy bounds and initialize the pool
        uint256 boundColPrecision   = bound(uint256(collateralPrecisionDecimals_), 1, 18);
        uint256 boundQuotePrecision = bound(uint256(quotePrecisionDecimals_),      1, 18);
        uint256 bucketId            = bound(uint256(bucketId_),                    1, 7388);
        uint256 quoteAmount1        = bound(uint256(quoteAmount1_),                0, 1e22 * 1e18);
        uint256 quoteAmount2        = bound(uint256(quoteAmount2_),                0, 1e22 * 1e18);
        _quotePrecision             = uint256(10) ** boundQuotePrecision;
        init(boundColPrecision, boundQuotePrecision);

        // mint and run approvals, ignoring amounts already init approved above
        deal(address(_quote), _lender, quoteAmount1 * _quotePrecision);
        changePrank(_lender);
        _quote.approve(address(_pool), quoteAmount1 * _quotePrecision);
        address lender2 = makeAddr("lender2");
        deal(address(_quote), lender2, quoteAmount2 * _quotePrecision);
        changePrank(lender2);
        _quote.approve(address(_pool), quoteAmount2 * _quotePrecision);

        // deposit lender1 quote token and sanity check LPs
        _addInitialLiquidity(_lender, quoteAmount1, bucketId);
        uint256 time;
        uint256 lpBalance1;
        (lpBalance1, time) = _pool.lenderInfo(bucketId, _lender);
        if (quoteAmount1 != 0) {
            assertGt(lpBalance1, 0);
        } else {
            assertEq(lpBalance1, 0);
        }
        assertGt(time, _startTime);

        // deposit lender2 quote token and sanity check LPs
        _addInitialLiquidity(lender2, quoteAmount2, bucketId);
        uint256 lpBalance2;
        (lpBalance2, time) = _pool.lenderInfo(bucketId, lender2);
        if (quoteAmount2 != 0) {
            assertGt(lpBalance2, 0);
        } else {
            assertEq(lpBalance2, 0);
        }
        assertGt(time, _startTime);

        // check bucket
        uint256 curDeposit;
        uint256 bucketLPs;
        (, curDeposit, , bucketLPs,,) = _poolUtils.bucketInfo(address(_pool), bucketId);
        assertEq(curDeposit, quoteAmount1 + quoteAmount2);
        if (curDeposit == 0) {
            assertEq(bucketLPs, 0);
        } else {
            assertEq(bucketLPs, lpBalance1 + lpBalance2);
        }
    }

    function _encumberedCollateral(uint256 debt_, uint256 price_) internal pure returns (uint256 encumberance_) {
        encumberance_ =  price_ != 0 && debt_ != 0 ? Maths.wdiv(debt_, price_) : 0;
    }

    function _addCollateralWithoutCheckingLP(
        address from,
        uint256 amount,
        uint256 index
    ) internal returns (uint256) {
        changePrank(from);
        // CAUTION: this does not actually check topic1 and 2 as it should
        vm.expectEmit(true, true, false, false);
        emit AddCollateral(from, index, amount, 0);
        vm.expectEmit(true, true, false, true);
        emit Transfer(from, address(_pool), amount / ERC20Pool(address(_pool)).collateralScale());

        // Add for tearDown
        bidders.add(from);
        bidderDepositedIndex[from].add(index);
        bucketsUsed.add(index); 

        return ERC20Pool(address(_pool)).addCollateral(amount, index);
    }
}
