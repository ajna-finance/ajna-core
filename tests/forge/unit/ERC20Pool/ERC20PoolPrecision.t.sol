// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.18;

import { ERC20DSTestPlus }    from './ERC20DSTestPlus.sol';
import { TokenWithNDecimals } from '../../utils/Tokens.sol';

import 'src/ERC20Pool.sol';
import 'src/ERC20PoolFactory.sol';

import 'src/PoolInfoUtils.sol';
import { MAX_PRICE } from 'src/libraries/helpers/PoolHelper.sol';

import 'src/interfaces/pool/IPool.sol';
import 'src/libraries/internal/Maths.sol';

contract ERC20PoolPrecisionTest is ERC20DSTestPlus {

    uint256 internal constant MAX_DEPOSIT    = 1e22 * 1e18;
    uint256 internal constant MAX_COLLATERAL = 1e12 * 1e18;
    uint256 internal constant POOL_PRECISION = 1e18;
    uint256 internal constant LP_PRECISION   = 1e18;

    uint256 internal _collateralPrecision;
    uint256 internal _quotePrecision;
    uint256 internal _quoteDust;

    address internal _borrower;
    address internal _borrower2;
    address internal _lender;
    address internal _bidder;

    uint256 internal _lenderDepositDenormalized;
    uint256 internal _lenderDepositNormalized;

    TokenWithNDecimals internal _collateral;
    TokenWithNDecimals internal _quote;

    function init(uint256 collateralPrecisionDecimals_, uint256 quotePrecisionDecimals_) internal {
        _collateral = new TokenWithNDecimals("Collateral", "C", uint8(collateralPrecisionDecimals_));
        _quote      = new TokenWithNDecimals("Quote", "Q", uint8(quotePrecisionDecimals_));
        _pool       = ERC20Pool(new ERC20PoolFactory(_ajna).deployPool(address(_collateral), address(_quote), 0.05 * 10**18));
        vm.label(address(_pool), "ERC20Pool");
        _poolUtils  = new PoolInfoUtils();

        _collateralPrecision = uint256(10) ** collateralPrecisionDecimals_;
        _quotePrecision = uint256(10) ** quotePrecisionDecimals_;
        _quoteDust      = _pool.quoteTokenScale();

        _startTest();

        _borrower  = makeAddr("borrower");
        _borrower2 = makeAddr("borrower2");
        _lender    = makeAddr("lender");
        _bidder    = makeAddr("bidder");

        deal(address(_collateral), _bidder,  150 * _collateralPrecision);
        deal(address(_collateral), _borrower, 150 * _collateralPrecision);
        deal(address(_collateral), _borrower2, 200 * _collateralPrecision);

        _lenderDepositDenormalized = 200_000 * _quotePrecision;
        _lenderDepositNormalized = 200_000 * 1e18;
        deal(address(_quote), _lender,  _lenderDepositDenormalized);

        changePrank(_borrower);
        _collateral.approve(address(_pool), 150 * _collateralPrecision);
        _quote.approve(address(_pool), _lenderDepositDenormalized);

        changePrank(_borrower2);
        _collateral.approve(address(_pool), 200 * _collateralPrecision);
        _quote.approve(address(_pool), _lenderDepositDenormalized);

        changePrank(_bidder);
        _collateral.approve(address(_pool), 200_000 * _collateralPrecision);

        changePrank(_lender);
        _quote.approve(address(_pool), _lenderDepositDenormalized);

        skip(1 days); // to avoid deposit time 0 equals bucket bankruptcy time
    }

    /********************/
    /*** Test Methods ***/
    /********************/

    function testAddRemoveQuotePrecision(uint8 collateralPrecisionDecimals_, uint8 quotePrecisionDecimals_) external virtual tearDown {
        // setup fuzzy bounds and initialize the pool
        uint256 boundColPrecision = bound(uint256(collateralPrecisionDecimals_), 1, 18);
        uint256 boundQuotePrecision = bound(uint256(quotePrecisionDecimals_), 1, 18);
        init(boundColPrecision, boundQuotePrecision);

        uint256 start = block.timestamp;

        // deposit 50_000 quote tokens into each of 3 buckets
        _addInitialLiquidity({
            from:   _lender,
            amount: 50_000 * POOL_PRECISION,
            index:  2549
        });
        _addInitialLiquidity({
            from:   _lender,
            amount: 50_000 * POOL_PRECISION,
            index:  2550
        });
        _addInitialLiquidity({
            from:   _lender,
            amount: 50_000 * POOL_PRECISION,
            index:  2551
        });

        // check balances
        assertEq(_quote.balanceOf(address(_pool)), 150_000 * _quotePrecision);
        assertEq(_quote.balanceOf(_lender),        50_000 * _quotePrecision);

        // check initial pool state
        _assertPoolPrices({
            htp:      0,
            htpIndex: 7388,
            hpb:      3_025.946482308870940904 * 1e18,
            hpbIndex: 2549,
            lup:      MAX_PRICE,
            lupIndex: 0
        });
        _assertLoans({
            noOfLoans:         0,
            maxBorrower:       address(0),
            maxThresholdPrice: 0
        });
        assertEq(_pool.depositSize(), 150_000 * POOL_PRECISION);

        // check bucket balance
        _assertBucket({
            index:        2549,
            lpBalance:    50_000 * 1e18,
            collateral:   0,
            deposit:      50_000 * POOL_PRECISION,
            exchangeRate: 1 * LP_PRECISION
        });
        _assertLenderLpBalance({
            lender:      _lender,
            index:       2549,
            lpBalance:   50_000 * 1e18,
            depositTime: start
        });

        skip(1 days); // skip to avoid penalty
        // lender removes some quote token from highest priced bucket
        _removeLiquidity({
            from:     _lender,
            amount:   25_000 * POOL_PRECISION,
            index:    2549,
            newLup:   MAX_PRICE,
            lpRedeem: 25_000 * 1e18
        });

        // check balances
        assertEq(_quote.balanceOf(address(_pool)), 125_000 * _quotePrecision);
        assertEq(_quote.balanceOf(_lender),        75_000 * _quotePrecision);

        // check pool state
        _assertPoolPrices({
            htp:      0,
            htpIndex: 7388,
            hpb:      3_025.946482308870940904 * 1e18,
            hpbIndex: 2549,
            lup:      MAX_PRICE,
            lupIndex: 0
        });
        _assertLoans({
            noOfLoans:         0,
            maxBorrower:       address(0),
            maxThresholdPrice: 0
        });
        assertEq(_pool.depositSize(), 125_000 * POOL_PRECISION);

        // check bucket balance
        _assertBucket({
            index:        2549,
            lpBalance:    25_000 * 1e18,
            collateral:   0,
            deposit:      25_000 * POOL_PRECISION,
            exchangeRate: 1 * 1e18
        });
        _assertLenderLpBalance({
            lender:      _lender,
            index:       2549,
            lpBalance:   25_000 * LP_PRECISION,
            depositTime: start
        });
    }

    function testAddRemoveCollateralPrecision (
        uint8   collateralPrecisionDecimals_,
        uint8   quotePrecisionDecimals_,
        uint16  bucketId_
    ) external tearDown {
        // setup fuzzy bounds and initialize the pool
        uint256 collateralDecimals = bound(uint256(collateralPrecisionDecimals_), 1, 18);
        uint256 quoteDecimals      = bound(uint256(quotePrecisionDecimals_),      1, 18);
        uint256 bucketId           = bound(uint256(bucketId_),                    1, 7388);
        init(collateralDecimals, quoteDecimals);
        // minimum amount of collateral which can be transferred
        uint256 minCollateralAmount = ERC20Pool(address(_pool)).bucketCollateralDust(0);
        // minimum amount of collateral which should remain in bucket
        uint256 collateralDust      = ERC20Pool(address(_pool)).bucketCollateralDust(bucketId);

        // put some deposit in the bucket
        _addInitialLiquidity({
            from:   _lender,
            amount: _lenderDepositNormalized,
            index:  bucketId
        });

        // add collateral to the bucket
        _addCollateralWithoutCheckingLP(_bidder, 100 * 1e18, bucketId);
        (uint256 bidderLpBalance, ) = _pool.lenderInfo(bucketId, _bidder);
        assertGt(bidderLpBalance, 0);

        // ensure dusty amounts are handled appropriately
        if (collateralDust != 1) {
            // ensure amount below the dust limit reverts
            _assertAddCollateralDustRevert(_bidder, collateralDust / 2, bucketId);
            // ensure amount above the dust limit is rounded to collateral scale
            uint256 unscaledCollateralAmount = collateralDust + collateralDust / 2;
            _addCollateralWithoutCheckingLP(_bidder, unscaledCollateralAmount, bucketId);
        }

        // remove collateral from the bucket
        _removeCollateralWithoutLPCheck(_bidder, 50 * 1e18, bucketId);

        // test removal of dusty amount
        if (minCollateralAmount != 1) {
            (, , uint256 claimableCollateral, , , ) = _poolUtils.bucketInfo(address(_pool), bucketId);
            uint256 removalAmount = claimableCollateral - (minCollateralAmount - 1);
            if (collateralDust == minCollateralAmount)
                _removeCollateralWithoutLPCheck(_bidder, removalAmount, bucketId);
            else
                _assertRemoveCollateralDustRevert(_bidder, removalAmount, bucketId);
        }
    }

    function testBorrowRepayPrecision(
        uint8 collateralPrecisionDecimals_, 
        uint8 quotePrecisionDecimals_
    ) external {
        // setup fuzzy bounds and initialize the pool
        uint256 boundColPrecision = bound(uint256(collateralPrecisionDecimals_), 1, 18);
        uint256 boundQuotePrecision = bound(uint256(quotePrecisionDecimals_), 1, 18);
        init(boundColPrecision, boundQuotePrecision);

        uint256 start = block.timestamp;

        _addInitialLiquidity({
            from:   _lender,
            amount: 50_000 * POOL_PRECISION,
            index:  2549
        });
        _addInitialLiquidity({
            from:   _lender,
            amount: 50_000 * POOL_PRECISION,
            index:  2550
        });
        _addInitialLiquidity({
            from:   _lender,
            amount: 50_000 * POOL_PRECISION,
            index:  2551
        });

        // borrowers adds collateral
        _pledgeCollateral({
            from:     _borrower,
            borrower: _borrower,
            amount:   50 * POOL_PRECISION
        });

        // check balances
        assertEq(_collateral.balanceOf(address(_pool)), 50 * _collateralPrecision);
        assertEq(_collateral.balanceOf(_borrower),      100 * _collateralPrecision);
        assertEq(_quote.balanceOf(address(_pool)), 150_000 * _quotePrecision);
        assertEq(_quote.balanceOf(_borrower),      0);

        // check pool state
        _assertPoolPrices({
            htp:      0,
            htpIndex: 7388,
            hpb:      3_025.946482308870940904 * 1e18,
            hpbIndex: 2549,
            lup:      MAX_PRICE,
            lupIndex: 0
        });
        _assertLoans({
            noOfLoans:         0,
            maxBorrower:       address(0),
            maxThresholdPrice: 0
        });
        assertEq(_pool.depositSize(), 150_000 * POOL_PRECISION);

        // check bucket balance
        _assertBucket({
            index:        2549,
            lpBalance:    50_000 * LP_PRECISION,
            collateral:   0,
            deposit:      50_000 * POOL_PRECISION,
            exchangeRate: 1 * LP_PRECISION
        });
        _assertLenderLpBalance({
            lender:      _lender,
            index:       2549,
            lpBalance:   50_000 * LP_PRECISION,
            depositTime: start
        });

        // borrower borrows
        uint256 price = _priceAt(2549);

        _borrow({
            from:       _borrower,
            amount:     10_000 * POOL_PRECISION,
            indexLimit: 3_000,
            newLup:     price
        });

        // check balances
        assertEq(_collateral.balanceOf(address(_pool)),   50 * _collateralPrecision);
        assertEq(_collateral.balanceOf(_borrower), 100 * _collateralPrecision);
        assertEq(_quote.balanceOf(address(_pool)),   140_000 * _quotePrecision);
        assertEq(_quote.balanceOf(_borrower), 10_000 * _quotePrecision);

        // check pool state
        uint256 debt = 10_008.653846153846150000 * 1e18;
        uint256 col  = 50 * 1e18;

        // 50 collateral @ 3025.9 = 151295, so borrower is 15_116% collateralized
        _assertBorrower({
            borrower:                  _borrower,
            borrowerDebt:              debt,
            borrowerCollateral:        col,
            borrowert0Np:              229.411561015492614726 * 1e18,
            borrowerCollateralization: 15.116650694597107214 * 1e18
        });
        _assertPoolPrices({
            htp:      200.173076923076923000 * 1e18,
            htpIndex: 3093,
            hpb:      3_025.946482308870940904 * 1e18,
            hpbIndex: 2549,
            lup:      price,
            lupIndex: 2549
        });
        _assertLoans({
            noOfLoans:         1,
            maxBorrower:       _borrower,
            maxThresholdPrice: 200.173076923076923000 * 1e18
        });

        (uint256 poolDebt,,,) = _pool.debtInfo();

        assertEq(_pool.depositSize(),       150_000 * POOL_PRECISION);
        assertEq(poolDebt,                  debt);
        assertEq(_pool.pledgedCollateral(), col);

        _assertBucket({
            index:        2549,
            lpBalance:    50_000 * LP_PRECISION,
            collateral:   0,
            deposit:      50_000 * POOL_PRECISION,
            exchangeRate: 1 * LP_PRECISION
        });
        _assertLenderLpBalance({
            lender:      _lender,
            index:       2549,
            lpBalance:   50_000 * LP_PRECISION,
            depositTime: start
        });

        // borrower repays half of loan
        _repayDebt({
            from:             _borrower,
            borrower:         _borrower,
            amountToRepay:    5_000 * POOL_PRECISION,
            amountRepaid:     5_000 * POOL_PRECISION,
            collateralToPull: 0,
            newLup:           3_025.946482308870940904 * 1e18
        });

        // check balances
        assertEq(_collateral.balanceOf(address(_pool)), 50 * _collateralPrecision);
        assertEq(_collateral.balanceOf(_borrower),      100 * _collateralPrecision);

        assertEq(_quote.balanceOf(address(_pool)), 145_000 * _quotePrecision);
        assertEq(_quote.balanceOf(_borrower),      5_000 * _quotePrecision);

        // check pool state
        debt = 5_008.653846153846150000 * 1e18;
        col  = 50 * 1e18;

        _assertBorrower({
            borrower:                  _borrower,
            borrowerDebt:              debt,
            borrowerCollateral:        col,
            borrowert0Np:              114.804959297694401926 * 1e18,
            borrowerCollateralization: 30.207183159927296805 * 1e18
        });
        _assertPoolPrices({
            htp:      100.173076923076923000 * 1e18,
            htpIndex: 3232,
            hpb:      3_025.946482308870940904 * 1e18,
            hpbIndex: 2549,
            lup:      price,
            lupIndex: 2549
        });
        _assertLoans({
            noOfLoans:         1,
            maxBorrower:       _borrower,
            maxThresholdPrice: 100.173076923076923000 * 1e18
        });

        (poolDebt,,,) = _pool.debtInfo();

        assertEq(_pool.depositSize(),       150_000 * 1e18);
        assertEq(poolDebt,                  debt);
        assertEq(_pool.pledgedCollateral(), col);

        _assertBucket({
            index:        2549,
            lpBalance:    50_000 * LP_PRECISION,
            collateral:   0,
            deposit:      50_000 * 1e18,
            exchangeRate: 1 * 1e18
        });
        _assertLenderLpBalance({
            lender:      _lender,
            index:       2549,
            lpBalance:   50_000 * LP_PRECISION,
            depositTime: start
        });

        // remove all of the remaining claimable collateral
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
    }

    function testRepayLessThanTokenPrecision(
        uint8  quotePrecisionDecimals_,
        uint16 bucketId_
    ) external tearDown {
        // setup fuzzy bounds and initialize the pool
        uint256 boundQuotePrecision = bound(uint256(quotePrecisionDecimals_), 1, 17);
        init(18, boundQuotePrecision);
        // borrower has 150 collateral, so they can draw 25k debt down to a price of ~166.6667 quote token
        uint256 bucketId = bound(uint256(bucketId_), 1, _poolUtils.priceToIndex(167 * 1e18));
        uint256 bucketPrice = _poolUtils.indexToPrice(bucketId);

        // lender adds fixed liquidity
        _addInitialLiquidity({
            from:   _lender,
            amount: 50_000 * 1e18,
            index:  bucketId
        });
        skip(3 hours);

        // borrower draws debt
        _drawDebt({
            from:               _borrower, 
            borrower:           _borrower,
            amountToBorrow:     25_000 * 1e18,
            limitIndex:         bucketId,
            collateralToPledge: 150 * 1e18,
            newLup:             bucketPrice
        });
        skip(12 hours);

        // borrower attempts to repay less than token precision
        assertGt(_quoteDust, 1);
        changePrank(_borrower);
        vm.expectRevert(IPoolErrors.InvalidAmount.selector);
        ERC20Pool(address(_pool)).repayDebt(_borrower, _quoteDust - 1, 0, _borrower, bucketId);
    }

    function testDepositTwoActorSameBucket(
        uint8   collateralPrecisionDecimals_,
        uint8   quotePrecisionDecimals_,
        uint16  bucketId_,
        uint256 quoteAmount_,
        uint256 collateralAmount_
    ) external tearDown {
        // setup fuzzy bounds and initialize the pool
        uint256 boundColPrecision   = bound(uint256(collateralPrecisionDecimals_), 1, 18);
        uint256 boundQuotePrecision = bound(uint256(quotePrecisionDecimals_),      1, 18);

        init(boundColPrecision, boundQuotePrecision);

        uint256 bucketId = bound(uint256(bucketId_), 1, 7388);

        // ensure half of deposits are below the scale limit
        uint256 maxColAmountBound   = collateralAmount_ % 2 == 0 ? MAX_COLLATERAL : uint256(10) ** boundColPrecision;
        uint256 maxQuoteAmountBound = quoteAmount_      % 2 == 0 ? MAX_DEPOSIT    : uint256(10) ** boundQuotePrecision;
        uint256 collateralAmount    = bound(uint256(collateralAmount_),            1, maxColAmountBound);
        uint256 quoteAmount         = bound(uint256(quoteAmount_),                 1, maxQuoteAmountBound);

        uint256 quoteScale = _pool.quoteTokenScale();
        uint256 quoteDust  = _pool.quoteTokenScale();
        if (quoteAmount < quoteDust) quoteAmount = quoteDust;

        uint256 colScale      = ERC20Pool(address(_pool)).collateralScale();
        uint256 colDustAmount = ERC20Pool(address(_pool)).bucketCollateralDust(bucketId);
        if (collateralAmount < colDustAmount) collateralAmount = colDustAmount;

        assertEq(ERC20Pool(address(_pool)).collateralScale(), 10 ** (18 - boundColPrecision));
        assertEq(_pool.quoteTokenScale(), 10 ** (18 - boundQuotePrecision));

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
            exchangeRate: 1e18
        });

        // addQuoteToken should add scaled quote token amount validate LP
        _addLiquidityNoEventCheck(_lender, quoteAmount, bucketId);

        // deposit collateral and sanity check bidder LP
        _addCollateralWithoutCheckingLP(_bidder, collateralAmount, bucketId);

        // check bucket quantities and LP
        (, uint256 curDeposit, uint256 availableCollateral, uint256 bucketLpBalance,,) = _poolUtils.bucketInfo(address(_pool), bucketId);
        assertEq(curDeposit,          _roundToScale(quoteAmount, quoteScale));
        assertEq(availableCollateral, _roundToScale(collateralAmount, colScale));

        (uint256 lenderLpBalance, ) = _pool.lenderInfo(bucketId, _lender);
        assertEq(lenderLpBalance, _roundToScale(quoteAmount, quoteScale));
        (uint256 bidderLpBalance, ) = _pool.lenderInfo(bucketId, _bidder);
        assertGt(bidderLpBalance, 0);
        assertEq(bucketLpBalance, lenderLpBalance + bidderLpBalance);
    }

/*********************************************************************************************************/
/*********************************************************************************************************/
/*********************************************************************************************************/

    function testDepositTwoActorSameBucketSimplified(
    ) external tearDown {
        // setup fuzzy bounds and initialize the pool
        uint256 boundColPrecision   = 14;
        uint256 boundQuotePrecision = 7;

        init(boundColPrecision, boundQuotePrecision);

        uint256 bucketId = 2161;

        uint256 collateralAmount    = 3150;
        uint256 quoteAmount         = 10795;

        uint256 quoteScale = _pool.quoteTokenScale();
        uint256 quoteDust  = _pool.quoteTokenScale();
        if (quoteAmount < quoteDust) quoteAmount = quoteDust;

        uint256 colScale      = ERC20Pool(address(_pool)).collateralScale();
        uint256 colDustAmount = ERC20Pool(address(_pool)).bucketCollateralDust(bucketId);
        if (collateralAmount < colDustAmount) collateralAmount = colDustAmount + colDustAmount / 2;

        assertEq(ERC20Pool(address(_pool)).collateralScale(), 10 ** (18 - boundColPrecision));
        assertEq(_pool.quoteTokenScale(), 10 ** (18 - boundQuotePrecision));

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
            exchangeRate: 1e18
        });

        // addQuoteToken should add scaled quote token amount validate LP
        _addLiquidityNoEventCheck(_lender, quoteAmount, bucketId);

        // deposit collateral and sanity check bidder LP
        _addCollateralWithoutCheckingLP(_bidder, collateralAmount, bucketId);

        // check bucket quantities and LP
        (, uint256 curDeposit, uint256 availableCollateral, uint256 bucketLpBalance,,) = _poolUtils.bucketInfo(address(_pool), bucketId);
        assertEq(curDeposit,          _roundToScale(quoteAmount, quoteScale));
        assertEq(availableCollateral, _roundToScale(collateralAmount, colScale));

        (uint256 lenderLpBalance, ) = _pool.lenderInfo(bucketId, _lender);
        assertEq(lenderLpBalance, _roundToScale(quoteAmount, quoteScale));
        (uint256 bidderLpBalance, ) = _pool.lenderInfo(bucketId, _bidder);
        assertGt(bidderLpBalance, 0);
        assertEq(bucketLpBalance, lenderLpBalance + bidderLpBalance);
    }

/*********************************************************************************************************/
/*********************************************************************************************************/
/*********************************************************************************************************/

    
    function testDepositTwoLendersSameBucket(
        uint8   collateralPrecisionDecimals_,
        uint8   quotePrecisionDecimals_,
        uint16  bucketId_,
        uint256 quoteAmount1_,
        uint256 quoteAmount2_
    ) external tearDown {
        // setup fuzzy bounds and initialize the pool
        uint256 boundColPrecision   = bound(uint256(collateralPrecisionDecimals_), 1, 18);
        uint256 boundQuotePrecision = bound(uint256(quotePrecisionDecimals_),      1, 18);

        init(boundColPrecision, boundQuotePrecision);

        uint256 bucketId  = bound(uint256(bucketId_), 1, 7388);

        // ensure half of deposits are below the scale limit
        uint256 maxQuoteAmount1 = quoteAmount1_ % 2 == 0 ? MAX_DEPOSIT : 1e18;
        uint256 maxQuoteAmount2 = quoteAmount2_ % 2 == 0 ? MAX_DEPOSIT : 1e18;

        uint256 quoteAmount1 = bound(uint256(quoteAmount1_), 1e18, maxQuoteAmount1);
        uint256 quoteAmount2 = bound(uint256(quoteAmount2_), 1e18, maxQuoteAmount2);

        // mint and run approvals, ignoring amounts already init approved above
        deal(address(_quote), _lender, quoteAmount1 * _quotePrecision);
        changePrank(_lender);
        _quote.approve(address(_pool), quoteAmount1 * _quotePrecision);
        address lender2 = makeAddr("lender2");
        deal(address(_quote), lender2, quoteAmount2 * _quotePrecision);
        changePrank(lender2);
        _quote.approve(address(_pool), quoteAmount2 * _quotePrecision);

        // addQuoteToken should add scaled quote token amount and LP
        _addLiquidityNoEventCheck(_lender, quoteAmount1, bucketId);
        (uint256 lpBalance1, ) = _pool.lenderInfo(bucketId, _lender);
        assertGt(lpBalance1, 0);

        // addQuoteToken should add scaled quote token amount and LP
        _addLiquidityNoEventCheck(lender2, quoteAmount2, bucketId);
        (uint256 lpBalance2, ) = _pool.lenderInfo(bucketId, lender2);
        assertGt(lpBalance2, 0);

        // check bucket
        uint256 quoteScale = _pool.quoteTokenScale();
        (, uint256 curDeposit, , uint256 bucketLP,,) = _poolUtils.bucketInfo(address(_pool), bucketId);
        assertEq(curDeposit, _roundToScale(quoteAmount1, quoteScale) + _roundToScale(quoteAmount2, quoteScale));
        assertEq(bucketLP, lpBalance1 + lpBalance2);
    }

    function testMoveQuoteToken(
        uint8   collateralPrecisionDecimals_, 
        uint8   quotePrecisionDecimals_,
        uint16  fromBucketId_,
        uint16  toBucketId_,
        uint256 amountToMove_
    ) external tearDown {
        // setup fuzzy bounds and initialize the pool
        uint256 boundColPrecision   = bound(uint256(collateralPrecisionDecimals_), 1, 18);
        uint256 boundQuotePrecision = bound(uint256(quotePrecisionDecimals_),      1, 18);
        // init to set lender deposit normalized
        init(boundColPrecision, boundQuotePrecision);

        uint256 fromBucketId        = bound(uint256(fromBucketId_),                1, 7388);
        uint256 toBucketId          = bound(uint256(toBucketId_),                  1, 7388);
        uint256 amountToMove        = bound(uint256(amountToMove_),                1, _lenderDepositNormalized);

        _addInitialLiquidity({
            from:   _lender,
            amount: _lenderDepositNormalized,
            index:  fromBucketId
        });

        if (fromBucketId == toBucketId) {
            _assertMoveLiquidityToSameIndexRevert({
                from:      _lender,
                amount:    amountToMove,
                fromIndex: fromBucketId,
                toIndex:   toBucketId
            });

            return;
        }

        if (amountToMove != 0 && amountToMove < _quoteDust) {
            _assertMoveLiquidityDustRevert({
                from:      _lender,
                amount:    amountToMove,
                fromIndex: fromBucketId,
                toIndex:   toBucketId
            });

            return;
        }

        _moveLiquidity({
            from:         _lender,
            amount:       amountToMove,
            fromIndex:    fromBucketId,
            toIndex:      toBucketId,
            lpRedeemFrom: amountToMove,
            lpAwardTo:    amountToMove,
            newLup:       MAX_PRICE
        });

        // validate from and to buckets have appropriate amounts of deposit and LP
        (, uint256 deposit,, uint256 lps,,) = _poolUtils.bucketInfo(address(_pool), fromBucketId);
        uint256 remaining = _lenderDepositNormalized - amountToMove;

        assertEq(deposit, remaining);
        assertEq(lps, remaining);
        (, deposit,, lps,,) = _poolUtils.bucketInfo(address(_pool), toBucketId);
        assertEq(deposit, amountToMove);
        assertEq(lps, amountToMove);
    }

    function testDrawMinDebtAmount(
        uint8   collateralPrecisionDecimals_,
        uint8   quotePrecisionDecimals_,
        uint16  bucketId_
    ) external tearDown {
        // setup fuzzy bounds and initialize the pool
        uint256 collateralDecimals = bound(uint256(collateralPrecisionDecimals_), 1, 18);
        uint256 quoteDecimals      = bound(uint256(quotePrecisionDecimals_),      1, 18);
        uint256 bucketId           = bound(uint256(bucketId_),                    1, 7388);
        init(collateralDecimals, quoteDecimals);

        _addInitialLiquidity({
            from:   _lender,
            amount: _lenderDepositNormalized,
            index:  bucketId
        });

        // 12 borrowers will take most of the liquidity; divide by 13 to leave room for origination fee
        uint256 debtToDraw         = Maths.wdiv(_lenderDepositNormalized, 13 * 1e18);
        uint256 collateralToPledge = _calculateCollateralToPledge(debtToDraw, bucketId, 1.1 * 1e18);
        address borrower;
        for (uint i=0; i<12; ++i) {
            borrower = makeAddr(string(abi.encodePacked("anonBorrower", i)));

            // mint and approve collateral tokens
            _mintAndApproveCollateral(borrower, collateralToPledge);
            // approve quote token to facilitate teardown
            _quote.approve(address(_pool), _lenderDepositDenormalized);

            // ensure illegitimate amounts revert
            if (i < 10) {
                if (quoteDecimals < 18) {
                    _assertBorrowInvalidAmountRevert({
                        from:       _borrower,
                        amount:     1,
                        indexLimit: bucketId
                    });
                }
            } else {
                _assertBorrowMinDebtRevert({
                    from:       _borrower,
                    amount:     Maths.wdiv(debtToDraw, 11 * 1e18),
                    indexLimit: bucketId
                });
            }

            // draw a legitimate amount of debt
            _drawDebtNoLupCheck({
                    from:               borrower,
                    borrower:           borrower,
                    amountToBorrow:     debtToDraw,
                    limitIndex:         bucketId,
                    collateralToPledge: collateralToPledge
            });
        }

        // have last borrower attempt an bad repay before tearDown
        (uint256 minDebtAmount, , , ) = _poolUtils.poolUtilizationInfo(address(_pool));
        assertGt(minDebtAmount, 1);

        (uint256 debt, , ) = _poolUtils.borrowerInfo(address(_pool), borrower);
        uint256 repayAmount = debt - minDebtAmount / 2;

        _assertRepayMinDebtRevert({
            from:     borrower,
            borrower: borrower,
            amount:   repayAmount
        });
    }

    function testCollateralDustPricePrecisionAdjustment() external {
        // test the bucket price adjustment used for determining dust amount
        assertEq(_getCollateralDustPricePrecisionAdjustment(0),    0);
        assertEq(_getCollateralDustPricePrecisionAdjustment(1),    0);
        assertEq(_getCollateralDustPricePrecisionAdjustment(4156), 2);
        assertEq(_getCollateralDustPricePrecisionAdjustment(4310), 3);
        assertEq(_getCollateralDustPricePrecisionAdjustment(5260), 6);
        assertEq(_getCollateralDustPricePrecisionAdjustment(6466), 8);
        assertEq(_getCollateralDustPricePrecisionAdjustment(6647), 8);
        assertEq(_getCollateralDustPricePrecisionAdjustment(7388), 9);

        // check dust limits for 18-decimal collateral
        init(18, 18);
        assertEq(IERC20Pool(address(_pool)).bucketCollateralDust(0),    1);
        assertEq(IERC20Pool(address(_pool)).bucketCollateralDust(1),    1);
        assertEq(IERC20Pool(address(_pool)).bucketCollateralDust(4166), 100);
        assertEq(IERC20Pool(address(_pool)).bucketCollateralDust(7388), 1000000000);
        vm.stopPrank();

        // check dust limits for 12-decimal collateral
        init(12, 18);
        assertEq(IERC20Pool(address(_pool)).bucketCollateralDust(0),    1000000);
        assertEq(IERC20Pool(address(_pool)).bucketCollateralDust(1),    1000000);
        assertEq(IERC20Pool(address(_pool)).bucketCollateralDust(6466), 100000000);
        assertEq(IERC20Pool(address(_pool)).bucketCollateralDust(7388), 1000000000);
        vm.stopPrank();

        // check dust limits for 6-decimal collateral
        init(6, 18);
        assertEq(IERC20Pool(address(_pool)).bucketCollateralDust(0),    1000000000000);
        assertEq(IERC20Pool(address(_pool)).bucketCollateralDust(1),    1000000000000);
        assertEq(IERC20Pool(address(_pool)).bucketCollateralDust(4156), 1000000000000);
        assertEq(IERC20Pool(address(_pool)).bucketCollateralDust(7388), 1000000000000);
    }

    function testDrawDebtPrecision(
        uint8   collateralPrecisionDecimals_,
        uint8   quotePrecisionDecimals_,
        uint16  bucketId_
    ) external tearDown {
        // setup fuzzy bounds and initialize the pool
        uint256 collateralDecimals = bound(uint256(collateralPrecisionDecimals_), 1, 18);
        uint256 quoteDecimals      = bound(uint256(quotePrecisionDecimals_),      1, 18);
        uint256 bucketId           = bound(uint256(bucketId_),                    1, 7388);
        init(collateralDecimals, quoteDecimals);
        uint256 collateralScale = 10 ** (18 - collateralDecimals);

        // add liquidity to a single bucket
        _addInitialLiquidity({
            from:   _lender,
            amount: _lenderDepositNormalized,
            index:  bucketId
        });

        // calculate amount of debt to draw to bring pool to ~50% utilization
        uint256 debtToDraw         = Maths.wdiv(_lenderDepositNormalized, 2 * 1e18);
        // determine amount of collateral required, with higher precision than the token
        uint256 collateralToPledge = _calculateCollateralToPledge(debtToDraw, bucketId, 1.1 * 1e18);
        _mintAndApproveCollateral(_borrower, collateralToPledge);

        // validate that dusty amount was not credited to the borrower
        _drawDebt({
            from:               _borrower, 
            borrower:           _borrower,
            amountToBorrow:     debtToDraw,
            limitIndex:         bucketId,
            collateralToPledge: collateralToPledge,
            newLup:             _priceAt(bucketId)
        });

        (uint256 currentDebt, uint256 pledgedCollateral, ) = _poolUtils.borrowerInfo(address(_pool), _borrower);
        assertGt(currentDebt, debtToDraw);

        // round the collateral amount to token precision
        uint256 collateralRounded  = (collateralToPledge / collateralScale) * collateralScale;
        assertEq(pledgedCollateral, collateralRounded);

        // accumulate some interest prior to tearDown to validate repayment
        skip(1 weeks);
    }

    function testFlashLoanPrecision(
        uint8 collateralPrecisionDecimals_,
        uint8 quotePrecisionDecimals_
    ) external tearDown {
        // setup fuzzy bounds and initialize the pool
        uint256 collateralDecimals = bound(uint256(collateralPrecisionDecimals_), 1, 18);
        uint256 quoteDecimals      = bound(uint256(quotePrecisionDecimals_),      1, 18);
        init(collateralDecimals, quoteDecimals);

        // add liquidity
        _addInitialLiquidity({
            from:   _lender,
            amount: 10_000 * 1e18,
            index:  2500
        });

        _pledgeCollateral({
            from:     _borrower,
            borrower: _borrower,
            amount:   150 * 1e18
        });

        assertEq(_pool.maxFlashLoan(address(_collateral)), 150 * 10 ** collateralDecimals);
        assertEq(_pool.maxFlashLoan(address(_quote)),      10_000 * 10 ** quoteDecimals);
    }


    /**********************/
    /*** Helper Methods ***/
    /**********************/

    function _calculateCollateralToPledge(
        uint256 debtToDraw,
        uint256 newLupIndex,
        uint256 desiredCollateralizationRatio
    ) internal returns (uint256) {
        assertGt(desiredCollateralizationRatio, 1e18);
        uint256 colScale      = ERC20Pool(address(_pool)).collateralScale();
        uint256 price         = _priceAt(newLupIndex);
        uint256 desiredPledge = Maths.wmul(Maths.wdiv(debtToDraw, price), desiredCollateralizationRatio);
        uint256 scaledPledge  = (desiredPledge / colScale) * colScale;

        while (Maths.wdiv(Maths.wmul(scaledPledge, price), debtToDraw) < desiredCollateralizationRatio) {
            scaledPledge += colScale;
        }
        return scaledPledge;
    }

    function _encumberedCollateral(uint256 debt_, uint256 price_) internal pure returns (uint256 encumberance_) {
        encumberance_ =  price_ != 0 && debt_ != 0 ? Maths.wdiv(debt_, price_) : 0;
    }

    function _mintAndApproveCollateral(
        address recipient,
        uint256 normalizedAmount
    ) internal {
        changePrank(recipient);
        uint256 denormalizationFactor = 10 ** (18 - _collateral.decimals());
        _collateral.approve(address(_pool), normalizedAmount / denormalizationFactor);
        deal(address(_collateral), recipient, normalizedAmount / denormalizationFactor);
    }

    function _mintAndApproveQuoteToken(
        address recipient,
        uint256 normalizedAmount
    ) internal {
        changePrank(recipient);
        uint256 denormalizationFactor = 10 ** (18 - _quote.decimals());
        deal(address(_quote), recipient, normalizedAmount / denormalizationFactor);
        _quote.approve(address(_pool), normalizedAmount / denormalizationFactor);
    }

    function _repayDebtWithoutPullingCollateral(
        address borrower
    ) internal {
        (uint256 debt, , ) = _poolUtils.borrowerInfo(address(_pool), borrower);
        _mintAndApproveQuoteToken(borrower, debt);
        _repayDebt({
            from:             _borrower,
            borrower:         _borrower,
            amountToRepay:    debt,
            amountRepaid:     debt,
            collateralToPull: 0,
            newLup:           MAX_PRICE
        });
    }

}
