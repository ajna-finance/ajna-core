// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.18;

import { ERC20DSTestPlus }    from './ERC20DSTestPlus.sol';
import { TokenWithNDecimals } from '../../utils/Tokens.sol';

import 'src/ERC20Pool.sol';
import 'src/ERC20PoolFactory.sol';

import 'src/PoolInfoUtils.sol';
import { MAX_PRICE, COLLATERALIZATION_FACTOR } from 'src/libraries/helpers/PoolHelper.sol';

import 'src/interfaces/pool/IPool.sol';
import 'src/libraries/internal/Maths.sol';
import "forge-std/console.sol";

contract ERC20PoolPrecisionTest is ERC20DSTestPlus {

    uint256 internal constant MAX_DEPOSIT    = 1e22 * 1e18;
    uint256 internal constant MAX_COLLATERAL = 1e12 * 1e18;

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

        skip(1 minutes); // to avoid deposit time 0 equals bucket bankruptcy time
    }

    /********************/
    /*** Test Methods ***/
    /********************/

    function testAddRemoveQuotePrecision(
        uint8 collateralPrecisionDecimals_, 
        uint8 quotePrecisionDecimals_
    ) external virtual tearDown {
        // setup fuzzy bounds and initialize the pool
        uint256 boundColPrecision = bound(uint256(collateralPrecisionDecimals_), 1, 18);
        uint256 boundQuotePrecision = bound(uint256(quotePrecisionDecimals_), 1, 18);
        init(boundColPrecision, boundQuotePrecision);

        uint256 start = block.timestamp;

        // deposit 50_000 quote tokens into each of 3 buckets
        _addInitialLiquidity({
            from:   _lender,
            amount: 50_000 * 1e18,
            index:  2549
        });
        _addInitialLiquidity({
            from:   _lender,
            amount: 50_000 * 1e18,
            index:  2550
        });
        _addInitialLiquidity({
            from:   _lender,
            amount: 50_000 * 1e18,
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
            noOfLoans:             0,
            maxBorrower:           address(0),
            maxT0DebtToCollateral: 0
        });
        assertEq(_pool.depositSize(), 149_993.150684931506850000 * 1e18);

        // check bucket balance
        _assertBucket({
            index:        2549,
            lpBalance:    49_997.716894977168950000 * 1e18,
            collateral:   0,
            deposit:      49_997.716894977168950000 * 1e18,
            exchangeRate: 1 * 1e18
        });
        _assertLenderLpBalance({
            lender:      _lender,
            index:       2549,
            lpBalance:   49_997.716894977168950000 * 1e18,
            depositTime: start
        });

        // lender removes some quote token from highest priced bucket
        _removeLiquidity({
            from:     _lender,
            amount:   25_000 * 1e18,
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
            noOfLoans:             0,
            maxBorrower:           address(0),
            maxT0DebtToCollateral: 0
        });
        assertEq(_pool.depositSize(), 124_993.150684931506850000 * 1e18);

        // check bucket balance
        _assertBucket({
            index:        2549,
            lpBalance:    24_997.716894977168950000 * 1e18,
            collateral:   0,
            deposit:      24_997.716894977168950000 * 1e18,
            exchangeRate: 1 * 1e18
        });
        _assertLenderLpBalance({
            lender:      _lender,
            index:       2549,
            lpBalance:   24_997.716894977168950000 * 1e18,
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
    ) external tearDown {
        // setup fuzzy bounds and initialize the pool
        uint256 boundColPrecision = bound(uint256(collateralPrecisionDecimals_), 1, 18);
        uint256 boundQuotePrecision = bound(uint256(quotePrecisionDecimals_), 1, 18);
        init(boundColPrecision, boundQuotePrecision);

        uint256 start = block.timestamp;

        _addInitialLiquidity({
            from:   _lender,
            amount: 50_000 * 1e18,
            index:  2549
        });
        _addInitialLiquidity({
            from:   _lender,
            amount: 50_000 * 1e18,
            index:  2550
        });
        _addInitialLiquidity({
            from:   _lender,
            amount: 50_000 * 1e18,
            index:  2551
        });

        // borrowers adds collateral
        _pledgeCollateral({
            from:     _borrower,
            borrower: _borrower,
            amount:   50 * 1e18
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
            noOfLoans:             0,
            maxBorrower:           address(0),
            maxT0DebtToCollateral: 0
        });
        assertEq(_pool.depositSize(), 149_993.150684931506850000 * 1e18);

        // check bucket balance
        _assertBucket({
            index:        2549,
            lpBalance:    49_997.716894977168950000 * 1e18,
            collateral:   0,
            deposit:      49_997.716894977168950000 * 1e18,
            exchangeRate: 1 * 1e18
        });
        _assertLenderLpBalance({
            lender:      _lender,
            index:       2549,
            lpBalance:   49_997.716894977168950000 * 1e18,
            depositTime: start
        });

        // borrower borrows
        uint256 price = _priceAt(2549);

        _borrow({
            from:       _borrower,
            amount:     10_000 * 1e18,
            indexLimit: 3_000,
            newLup:     price
        });

        // check balances
        assertEq(_collateral.balanceOf(address(_pool)),   50 * _collateralPrecision);
        assertEq(_collateral.balanceOf(_borrower), 100 * _collateralPrecision);
        assertEq(_quote.balanceOf(address(_pool)),   140_000 * _quotePrecision);
        assertEq(_quote.balanceOf(_borrower), 10_000 * _quotePrecision);


        // 50 collateral @ 3025.9 = 151295, so borrower is heavily overcollateralized
        uint256 debt = 10_009.615384615384620000 * 1e18;
        uint256 col  = 50 * 1e18;
        _assertBorrower({
            borrower:                  _borrower,
            borrowerDebt:              debt,
            borrowerCollateral:        col,
            borrowert0Np:              231.477467645772810675 * 1e18,
            borrowerCollateralization: 14.533844775739053504 * 1e18
        });
        _assertPoolPrices({
            htp:      208.200000000000000096 * 1e18,
            htpIndex: 3085,
            hpb:      3_025.946482308870940904 * 1e18,
            hpbIndex: 2549,
            lup:      price,
            lupIndex: 2549
        });
        _assertLoans({
            noOfLoans:             1,
            maxBorrower:           _borrower,
            maxT0DebtToCollateral: 200.192307692307692400 * 1e18
        });

        (uint256 poolDebt,,,) = _pool.debtInfo();

        assertEq(_pool.depositSize(),       149_993.150684931506850000 * 1e18);
        assertEq(poolDebt,                  debt);
        assertEq(_pool.pledgedCollateral(), col);

        _assertBucket({
            index:        2549,
            lpBalance:    49_997.716894977168950000 * 1e18,
            collateral:   0,
            deposit:      49_997.716894977168950000 * 1e18,
            exchangeRate: 1 * 1e18
        });
        _assertLenderLpBalance({
            lender:      _lender,
            index:       2549,
            lpBalance:   49_997.716894977168950000 * 1e18,
            depositTime: start
        });

        // borrower repays half of loan
        _repayDebt({
            from:             _borrower,
            borrower:         _borrower,
            amountToRepay:    5_000 * 1e18,
            amountRepaid:     5_000 * 1e18,
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
        _assertBorrower({
            borrower:                  _borrower,
            borrowerDebt:              debt,
            borrowerCollateral:        col,
            borrowert0Np:              115.849914162773904339 * 1e18,
            borrowerCollateralization: 29.039793496246362170 * 1e18
        });
        _assertPoolPrices({
            htp:      104.200000000000000096 * 1e18,
            htpIndex: 3224,
            hpb:      3_025.946482308870940904 * 1e18,
            hpbIndex: 2549,
            lup:      price,
            lupIndex: 2549
        });
        _assertLoans({
            noOfLoans:             1,
            maxBorrower:           _borrower,
            maxT0DebtToCollateral: 100.192307692307692400 * 1e18
        });

        (poolDebt,,,) = _pool.debtInfo();
        assertEq(_pool.depositSize(),       149_993.150684931506850000 * 1e18);
        assertEq(poolDebt,                  debt);
        assertEq(_pool.pledgedCollateral(), col);

        _assertBucket({
            index:        2549,
            lpBalance:    49_997.716894977168950000 * 1e18,
            collateral:   0,
            deposit:      49_997.716894977168950000 * 1e18,
            exchangeRate: 1 * 1e18
        });
        _assertLenderLpBalance({
            lender:      _lender,
            index:       2549,
            lpBalance:   49_997.716894977168950000 * 1e18,
            depositTime: start
        });

        // remove all remaining claimable collateral
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
        uint256 collateralToPledge = _calculateCollateralToPledge(25_000 * 1e18, bucketId, 1.1 * 1e18);
        _mintAndApproveCollateral(_borrower, collateralToPledge);
        _drawDebt({
            from:               _borrower, 
            borrower:           _borrower,
            amountToBorrow:     25_000 * 1e18,
            limitIndex:         bucketId,
            collateralToPledge: collateralToPledge,
            newLup:             bucketPrice
        });

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
        uint256 quoteAmount;
        uint256 quoteScale = _pool.quoteTokenScale();
        uint256 collateralAmount;
        uint256 colScale      = ERC20Pool(address(_pool)).collateralScale();

        {
            // ensure half of deposits are below the scale limit
            uint256 maxColAmountBound   = collateralAmount_ % 2 == 0 ? MAX_COLLATERAL : uint256(10) ** boundColPrecision;
            uint256 maxQuoteAmountBound = quoteAmount_      % 2 == 0 ? MAX_DEPOSIT    : uint256(10) ** boundQuotePrecision;
            collateralAmount    = bound(uint256(collateralAmount_),            1, maxColAmountBound);
            quoteAmount         = bound(uint256(quoteAmount_),                 1, maxQuoteAmountBound);

            if (quoteAmount < quoteScale) quoteAmount = quoteScale;
            uint256 colDustAmount = ERC20Pool(address(_pool)).bucketCollateralDust(bucketId);
            if (collateralAmount < colDustAmount) collateralAmount = colDustAmount;
        }

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
        {
            uint256 depositRoundedToScale = _roundToScale(quoteAmount, quoteScale);
            uint256 depositLessPenalty    = Maths.wmul(depositRoundedToScale, _depositFee());
            (, uint256 curDeposit, uint256 availableCollateral, uint256 bucketLpBalance,,) = _poolUtils.bucketInfo(address(_pool), bucketId);
            assertEq(curDeposit, depositLessPenalty);
            assertEq(availableCollateral, _roundToScale(collateralAmount, colScale));

            (uint256 lenderLpBalance, ) = _pool.lenderInfo(bucketId, _lender);
            assertEq(lenderLpBalance, depositLessPenalty);
            (uint256 bidderLpBalance, ) = _pool.lenderInfo(bucketId, _bidder);
            assertGt(bidderLpBalance, 0);
            assertEq(bucketLpBalance, lenderLpBalance + bidderLpBalance);
        }
    }

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
        assertEq(curDeposit, 
            Maths.wmul(_roundToScale(quoteAmount1, quoteScale), _depositFee()) + 
            Maths.wmul(_roundToScale(quoteAmount2, quoteScale), _depositFee()));
        assertEq(bucketLP, lpBalance1 + lpBalance2);
    }

    function testMoveQuoteTokenNoDebt(
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

        uint256 fromBucketId        = bound(uint256(fromBucketId_), 1, 7388);
        uint256 toBucketId          = bound(uint256(toBucketId_),   1, 7388);
        uint256 amountToMove        = bound(uint256(amountToMove_), 1, _lenderDepositNormalized);
        amountToMove                = Maths.wmul(amountToMove, _depositFee());

        _addInitialLiquidity({
            from:   _lender,
            amount: _lenderDepositNormalized,
            index:  fromBucketId
        });
        uint256 lenderDepositLessFee = Maths.wmul(_lenderDepositNormalized, _depositFee());

        if (fromBucketId == toBucketId) {
            _assertMoveLiquidityToSameIndexRevert({
                from:      _lender,
                amount:    amountToMove,
                fromIndex: fromBucketId,
                toIndex:   toBucketId
            });
            return;
        }

        if (amountToMove < _quoteDust) {
            _assertMoveLiquidityDustRevert({
                from:      _lender,
                amount:    amountToMove,
                fromIndex: fromBucketId,
                toIndex:   toBucketId
            });
            return;
        }

        // if fromBucket deposit - amount to move < _quoteDust
        (, uint256 deposit,, uint256 lps,,) = _poolUtils.bucketInfo(address(_pool), fromBucketId);

        if (deposit > amountToMove && deposit - amountToMove < _quoteDust) {
            _assertMoveLiquidityDustRevert({
                from:      _lender,
                amount:    amountToMove,
                fromIndex: fromBucketId,
                toIndex:   toBucketId
            });
            return;
        }

        uint256 amountMoved = amountToMove;
        if (fromBucketId < toBucketId) {
            // if moving to a lower-priced bucket, the deposit fee should be charged again
            amountMoved = Maths.wmul(amountToMove, _depositFee());
        }
        _moveLiquidity({
            from:         _lender,
            amount:       amountToMove,
            fromIndex:    fromBucketId,
            toIndex:      toBucketId,
            lpRedeemFrom: amountToMove,
            lpAwardTo:    amountMoved,
            newLup:       MAX_PRICE
        });

        // validate from and to buckets have appropriate amounts of deposit and LP
        uint256 remaining = lenderDepositLessFee - amountToMove;
        (, deposit,, lps,,) = _poolUtils.bucketInfo(address(_pool), fromBucketId);
        assertEq(deposit, remaining);
        _validateBucketLp(fromBucketId, lps);
        (, deposit,, lps,,) = _poolUtils.bucketInfo(address(_pool), toBucketId);
        assertEq(deposit, amountMoved);
        _validateBucketLp(toBucketId, lps);
    }

    function testDrawMinDebtAmount(
        uint8   collateralPrecisionDecimals_,
        uint8   quotePrecisionDecimals_,
        uint16  bucketId_
    ) external tearDown {
        // setup fuzzy bounds and initialize the pool
        uint256 collateralDecimals = bound(uint256(collateralPrecisionDecimals_), 1, 18);
        uint256 quoteDecimals      = bound(uint256(quotePrecisionDecimals_),      1, 18);
        uint256 bucketId           = bound(uint256(bucketId_),                    1, 7387);
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

        (uint256 debt, , , ) = _poolUtils.borrowerInfo(address(_pool), borrower);
        uint256 repayAmount = debt - minDebtAmount / 2;

        _assertRepayMinDebtRevert({
            from:     borrower,
            borrower: borrower,
            amount:   repayAmount
        });
    }

    function testCollateralDustPricePrecisionAdjustment() external tearDown {
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
        uint256 bucketId           = bound(uint256(bucketId_),                    1, 7387);
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

        (uint256 currentDebt, uint256 pledgedCollateral, , ) = _poolUtils.borrowerInfo(address(_pool), _borrower);
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

    function testRemoveQuoteDust() external tearDown {
        // TODO: rework this into a fuzz test
        init(18, 6);

        _addInitialLiquidity({
            from:   _lender,
            amount: 2_000 * 1e18,
            index:  3696
        });

        // check balances
        assertEq(_quote.balanceOf(address(_pool)), 2_000.000000 * 1e6);
        assertEq(_quote.balanceOf(_lender),        198_000.000000 * 1e6);

        // remove an amount from the bucket which would leave dust behind
        (, uint256 curDeposit,,,,) = _poolUtils.bucketInfo(address(_pool), 3696);
        _assertRemoveQuoteDustRevert({
            from:     _lender,
            amount:   curDeposit - 1,
            index:    3696
        });

        _removeLiquidity({
            from:     _lender,
            amount:   curDeposit - 0.000001 * 1e18,
            index:    3696,
            newLup:   MAX_PRICE,
            lpRedeem: 1_999.908674799086758000 * 1e18
        });

        _assertBucket({
            index:        3696,
            lpBalance:    0.000001000000000000 * 1e18,
            collateral:   0,
            deposit:      0.000001000000000000 * 1e18,
            exchangeRate: 1 * 1e18
        });
    }

    function testMoveQuoteDust() external tearDown {
        // TODO: rework this into a fuzz test
        init(18, 6);

        _addInitialLiquidity({
            from:   _lender,
            amount: 2_000 * 1e18,
            index:  3696
        });

        // check balances
        assertEq(_quote.balanceOf(address(_pool)), 2_000.000000 * 1e6);
        assertEq(_quote.balanceOf(_lender),        198_000.000000 * 1e6);

        // move an amount from the bucket which would leave dust behind
        (, uint256 curDeposit,,,,) = _poolUtils.bucketInfo(address(_pool), 3696);
        _assertMoveQuoteDustRevert({
            from:      _lender,
            amount:    curDeposit - 1,
            fromIndex: 3696,
            toIndex:   3698
        });

        // move an amount smaller than token precision
        _assertMoveQuoteDustRevert({
            from:      _lender,
            amount:    1,
            fromIndex: 3696,
            toIndex:   3698
        });

        _moveLiquidity({
            from:         _lender,
            amount:       0.000001 * 1e18,
            fromIndex:    3696,
            toIndex:      3701,
            lpRedeemFrom: 0.000001 * 1e18,
            lpAwardTo:    0.000000999954337900 * 1e18,
            newLup:       1004968987.606512354182109771 * 1e18 
        });

        _assertBucket({
            index:        3696,
            lpBalance:    1_999.908674799086758000 * 1e18,
            collateral:   0,
            deposit:      1_999.908674799086758000 * 1e18,
            exchangeRate: 1 * 1e18
        });

        _assertBucket({
            index:        3701,
            lpBalance:    0.000000999954337900 * 1e18,
            collateral:   0,
            deposit:      0.000000999954337900 * 1e18,
            exchangeRate: 1 * 1e18
        });
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
        uint256 desiredPledge = Maths.wmul(Maths.wdiv(Maths.wmul(debtToDraw, COLLATERALIZATION_FACTOR), price), desiredCollateralizationRatio);
        uint256 scaledPledge  = (desiredPledge / colScale) * colScale;

        while (Maths.wdiv(Maths.wmul(scaledPledge, price), debtToDraw) < desiredCollateralizationRatio) {
            scaledPledge += colScale;
        }
        return scaledPledge;
    }

    function _encumberedCollateral(uint256 debt_, uint256 price_) internal view returns (uint256 encumberance_) {
        uint256 unscaledEncumberance =  price_ != 0 && debt_ != 0 ? Maths.ceilWdiv(Maths.wmul(debt_, COLLATERALIZATION_FACTOR), price_) : 0;
        encumberance_ = _roundUpToScale(unscaledEncumberance, ERC20Pool(address(_pool)).quoteTokenScale());
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
        (uint256 debt, , , ) = _poolUtils.borrowerInfo(address(_pool), borrower);
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