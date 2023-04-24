// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.14;

import { ERC20HelperContract } from './ERC20DSTestPlus.sol';

import 'src/interfaces/pool/IPool.sol';
import 'src/libraries/helpers/PoolHelper.sol';

contract ERC20PoolQuoteTokenTest is ERC20HelperContract {

    address internal _borrower;
    address internal _borrower2;
    address internal _lender;
    address internal _lender1;

    function setUp() external {
        _borrower  = makeAddr("borrower");
        _borrower2 = makeAddr("borrower2");
        _lender    = makeAddr("lender");
        _lender1   = makeAddr("bidder");

        _mintCollateralAndApproveTokens(_borrower,  100 * 1e18);
        _mintCollateralAndApproveTokens(_borrower2,  200 * 1e18);

        _mintQuoteAndApproveTokens(_lender,   200_000 * 1e18);
        _mintQuoteAndApproveTokens(_lender1,  200_000 * 1e18);
    }

    /**
     *  @notice 1 lender tests adding quote token.
     *          Lender reverts:
     *              attempts to addQuoteToken at invalid price.
     */
    function testPoolDepositQuoteToken() external tearDown {
        assertEq(_hpb(), MIN_PRICE);

        // should revert if trying to deposit at index 0
        _assertAddLiquidityAtIndex0Revert({
            from:   _lender,
            amount: 10_000 * 1e18
        });

        // test 10_000 deposit at price of 3_010.892022197881557845
        _addInitialLiquidity({
            from:   _lender,
            amount: 10_000 * 1e18,
            index:  2550
        });

        _assertPool(
            PoolParams({
                htp:                  0,
                lup:                  MAX_PRICE,
                poolSize:             10_000 * 1e18,
                pledgedCollateral:    0,
                encumberedCollateral: 0,
                poolDebt:             0,
                actualUtilization:    0,
                targetUtilization:    1e18,
                minDebtAmount:        0,
                loans:                0,
                maxBorrower:          address(0),
                interestRate:         0.05 * 1e18,
                interestRateUpdate:   _startTime
            })
        );
        _assertBucket({
            index:        2550,
            lpBalance:    10_000 * 1e18,
            collateral:   0,
            deposit:      10_000 * 1e18,
            exchangeRate: 1 * 1e18
        });
        _assertLenderLpBalance({
            lender:      _lender,
            index:       2550,
            lpBalance:   10_000 * 1e18,
            depositTime: _startTime
        });

        // check balances
        assertEq(_quote.balanceOf(address(_pool)), 10_000 * 1e18);
        assertEq(_quote.balanceOf(_lender),        190_000 * 1e18);

        // test 20_000 deposit at price of 2_995.912459898389633881
       _addInitialLiquidity({
            from:   _lender,
            amount: 20_000 * 1e18,
            index:  2551
        });

        _assertPool(
            PoolParams({
                htp:                  0,
                lup:                  MAX_PRICE,
                poolSize:             30_000 * 1e18,
                pledgedCollateral:    0,
                encumberedCollateral: 0,
                poolDebt:             0,
                actualUtilization:    0,
                targetUtilization:    1e18,
                minDebtAmount:        0,
                loans:                0,
                maxBorrower:          address(0),
                interestRate:         0.05 * 1e18,
                interestRateUpdate:   _startTime
            })
        );
        _assertBucket({
            index:        2550,
            lpBalance:    10_000 * 1e18,
            collateral:   0,
            deposit:      10_000 * 1e18,
            exchangeRate: 1 * 1e18
        });
        _assertLenderLpBalance({
            lender:      _lender,
            index:       2550,
            lpBalance:   10_000 * 1e18,
            depositTime: _startTime
        });
        _assertBucket({
            index:        2551,
            lpBalance:    20_000 * 1e18,
            collateral:   0,
            deposit:      20_000 * 1e18,
            exchangeRate: 1 * 1e18
        });
        _assertLenderLpBalance({
            lender:      _lender,
            index:       2551,
            lpBalance:   20_000 * 1e18,
            depositTime: _startTime
        });

        // check balances
        assertEq(_quote.balanceOf(address(_pool)), 30_000 * 1e18);
        assertEq(_quote.balanceOf(_lender),        170_000 * 1e18);

        // test 40_000 deposit at price of 3_025.946482308870940904 DAI
       _addInitialLiquidity({
            from:   _lender,
            amount: 40_000 * 1e18,
            index:  2549
        });

        _assertPool(
            PoolParams({
                htp:                  0,
                lup:                  MAX_PRICE,
                poolSize:             70_000 * 1e18,
                pledgedCollateral:    0,
                encumberedCollateral: 0,
                poolDebt:             0,
                actualUtilization:    0,
                targetUtilization:    1e18,
                minDebtAmount:        0,
                loans:                0,
                maxBorrower:          address(0),
                interestRate:         0.05 * 1e18,
                interestRateUpdate:   _startTime
            })
        );
        _assertBucket({
            index:        2549,
            lpBalance:    40_000 * 1e18,
            collateral:   0,
            deposit:      40_000 * 1e18,
            exchangeRate: 1 * 1e18
        });
        _assertLenderLpBalance({
            lender:      _lender,
            index:       2549,
            lpBalance:   40_000 * 1e18,
            depositTime: _startTime
        });
        _assertBucket({
            index:        2550,
            lpBalance:    10_000 * 1e18,
            collateral:   0,
            deposit:      10_000 * 1e18,
            exchangeRate: 1 * 1e18
        });
        _assertLenderLpBalance({
            lender:      _lender,
            index:       2550,
            lpBalance:   10_000 * 1e18,
            depositTime: _startTime
        });
        _assertBucket({
            index:        2551,
            lpBalance:    20_000 * 1e18,
            collateral:   0,
            deposit:      20_000 * 1e18,
            exchangeRate: 1 * 1e18
        });
        _assertLenderLpBalance({
            lender:      _lender,
            index:       2551,
            lpBalance:   20_000 * 1e18,
            depositTime: _startTime
        });

        // check balances
        assertEq(_quote.balanceOf(address(_pool)), 70_000 * 1e18);
        assertEq(_quote.balanceOf(_lender),        130_000 * 1e18);
    }

    function testPoolAddQuoteTokenReverts() external tearDown {
        // should revert if trying to deposit at index 0
        _assertAddLiquidityAtIndex0Revert({
            from:   _lender,
            amount: 10_000 * 1e18
        });

        // should revert if passing an already-expired timestamp
        _assertAddLiquidityExpiredRevert({
            from:   _lender,
            amount: 100_000 * 1e18,
            index:  3232,
            expiry: block.timestamp - 1 minutes
        });

        // should revert if passing future timestamp but time has elapsed
        bytes memory data = abi.encodeWithSignature(
            "addQuoteToken(uint256,uint256,uint256)",
            50_000 * 1e18,
            3333,
            block.timestamp + 5 minutes
        );

        // should succeed if time hasn't passed
        (bool success, ) = address(_pool).call(data);
        assertEq(success, true);        

        // should fail if expiration exceeded
        skip(6 minutes);
        vm.expectRevert(IPoolErrors.TransactionExpired.selector);
        (success, ) = address(_pool).call(data);
    }

    function testPoolRemoveQuoteToken() external tearDown {
       _addLiquidity({
            from:    _lender,
            amount:  40_000 * 1e18,
            index:   2549,
            lpAward: 40_000 * 1e18,
            newLup:  MAX_PRICE
        });
       _addLiquidity({
            from:    _lender,
            amount:  10_000 * 1e18,
            index:   2550,
            lpAward: 10_000 * 1e18,
            newLup:  MAX_PRICE
        });   
       _addLiquidity(   {   
            from:    _lender,
            amount:  20_000 * 1e18,
            index:   2551,
            lpAward: 20_000 * 1e18,
            newLup:  MAX_PRICE
        });

        _assertPool(
            PoolParams({
                htp:                  0,
                lup:                  MAX_PRICE,
                poolSize:             70_000 * 1e18,
                pledgedCollateral:    0,
                encumberedCollateral: 0,
                poolDebt:             0,
                actualUtilization:    0,
                targetUtilization:    1e18,
                minDebtAmount:        0,
                loans:                0,
                maxBorrower:          address(0),
                interestRate:         0.05 * 1e18,
                interestRateUpdate:   _startTime
            })
        );
        _assertBucket({
            index:        2549,
            lpBalance:    40_000 * 1e18,
            collateral:   0,
            deposit:      40_000 * 1e18,
            exchangeRate: 1 * 1e18
        });
        _assertLenderLpBalance({
            lender:      _lender,
            index:       2549,
            lpBalance:   40_000 * 1e18,
            depositTime: _startTime
        });
        _assertBucket({
            index:        2550,
            lpBalance:    10_000 * 1e18,
            collateral:   0,
            deposit:      10_000 * 1e18,
            exchangeRate: 1 * 1e18
        });
        _assertLenderLpBalance({
            lender:      _lender,
            index:       2550,
            lpBalance:   10_000 * 1e18,
            depositTime: _startTime
        });
        _assertBucket({
            index:        2551,
            lpBalance:    20_000 * 1e18,
            collateral:   0,
            deposit:      20_000 * 1e18,
            exchangeRate: 1 * 1e18
        });
        _assertLenderLpBalance({
            lender:      _lender,
            index:       2551,
            lpBalance:   20_000 * 1e18,
            depositTime: _startTime
        });

        // check balances
        assertEq(_quote.balanceOf(address(_pool)), 70_000 * 1e18);
        assertEq(_quote.balanceOf(_lender),        130_000 * 1e18);

        skip(1 days); // skip to avoid penalty

        _removeLiquidity({
            from:     _lender,
            amount:   5_000 * 1e18,
            index:    2549,
            newLup:   MAX_PRICE,
            lpRedeem: 5_000 * 1e18
        });

        _assertPool(
            PoolParams({
                htp:                  0,
                lup:                  MAX_PRICE,
                poolSize:             65_000 * 1e18,
                pledgedCollateral:    0,
                encumberedCollateral: 0,
                poolDebt:             0,
                actualUtilization:    0,
                targetUtilization:    1e18,
                minDebtAmount:        0,
                loans:                0,
                maxBorrower:          address(0),
                interestRate:         0.045 * 1e18,
                interestRateUpdate:   _startTime + 1 days
            })
        );
        _assertBucket({
            index:        2549,
            lpBalance:    35_000 * 1e18,
            collateral:   0,
            deposit:      35_000 * 1e18,
            exchangeRate: 1 * 1e18
        });
        _assertLenderLpBalance({
            lender:      _lender,
            index:       2549,
            lpBalance:   35_000 * 1e18,
            depositTime: _startTime
        });
        _assertBucket({
            index:        2550,
            lpBalance:    10_000 * 1e18,
            collateral:   0,
            deposit:      10_000 * 1e18,
            exchangeRate: 1 * 1e18
        });
        _assertLenderLpBalance({
            lender:      _lender,
            index:       2550,
            lpBalance:   10_000 * 1e18,
            depositTime: _startTime
        });
        _assertBucket({
            index:        2551,
            lpBalance:    20_000 * 1e18,
            collateral:   0,
            deposit:      20_000 * 1e18,
            exchangeRate: 1 * 1e18
        });
        _assertLenderLpBalance({
            lender:      _lender,
            index:       2551,
            lpBalance:   20_000 * 1e18,
            depositTime: _startTime
        });

        // check balances
        assertEq(_quote.balanceOf(address(_pool)), 65_000 * 1e18);
        assertEq(_quote.balanceOf(_lender),        135_000 * 1e18);

        _removeLiquidity({
            from:     _lender,
            amount:   35_000 * 1e18,
            index:    2549,
            newLup:   MAX_PRICE,
            lpRedeem: 35_000 * 1e18
        });

        _assertPool(
            PoolParams({
                htp:                  0,
                lup:                  MAX_PRICE,
                poolSize:             30_000 * 1e18,
                pledgedCollateral:    0,
                encumberedCollateral: 0,
                poolDebt:             0,
                actualUtilization:    0,
                targetUtilization:    1e18,
                minDebtAmount:        0,
                loans:                0,
                maxBorrower:          address(0),
                interestRate:         0.045 * 1e18,
                interestRateUpdate:   _startTime + 1 days
            })
        );
        _assertBucket({
            index:        2549,
            lpBalance:    0,
            collateral:   0,
            deposit:      0,
            exchangeRate: 1 * 1e18
        });
        _assertLenderLpBalance({
            lender:      _lender,
            index:       2549,
            lpBalance:   0,
            depositTime: _startTime
        });
        _assertBucket({
            index:        2550,
            lpBalance:    10_000 * 1e18,
            collateral:   0,
            deposit:      10_000 * 1e18,
            exchangeRate: 1 * 1e18
        });
        _assertLenderLpBalance({
            lender:      _lender,
            index:       2550,
            lpBalance:   10_000 * 1e18,
            depositTime: _startTime
        });
        _assertBucket({
            index:        2551,
            lpBalance:    20_000 * 1e18,
            collateral:   0,
            deposit:      20_000 * 1e18,
            exchangeRate: 1 * 1e18
        });
        _assertLenderLpBalance({
            lender:      _lender,
            index:       2551,
            lpBalance:   20_000 * 1e18,
            depositTime: _startTime
        });

        // check balances
        assertEq(_quote.balanceOf(address(_pool)), 30_000 * 1e18);
        assertEq(_quote.balanceOf(_lender),        170_000 * 1e18);
    }

    /**
     *  @notice 1 lender tests reverts in removeQuoteToken.
     *          Reverts:
     *              Attempts to remove more quote tokens than available in bucket.
     */
    function testPoolRemoveQuoteTokenNotAvailable() external tearDown {
        _mintCollateralAndApproveTokens(_borrower, _collateral.balanceOf(_borrower) + 3_500_000 * 1e18);

        // lender adds initial quote token
        _addLiquidity({
            from:    _lender,
            amount:  11_000 * 1e18,
            index:   4550,
            lpAward: 11_000 * 1e18,
            newLup:  MAX_PRICE
        });

        _drawDebt({
            from:               _borrower,
            borrower:           _borrower,
            amountToBorrow:     10_000 * 1e18,
            limitIndex:         7000,
            collateralToPledge: 3_500_000 * 1e18,
            newLup:             0.140143083210662942 * 1e18
        });

        _assertRemoveAllLiquidityLupBelowHtpRevert(
        {
            from:  _lender,
            index: 4550
        }
    );
    }

    /**
     *  @notice 1 lender tests reverts in removeQuoteToken.
     *          Reverts:
     *              Attempts to remove more quote tokens than available from lpBalance.
     *              Attempts to remove quote token when doing so would drive lup below htp.
     */
    function testPoolRemoveQuoteTokenReverts() external tearDown {
        _mintCollateralAndApproveTokens(_borrower, _collateral.balanceOf(_borrower) + 3_500_000 * 1e18);
        _mintCollateralAndApproveTokens(_lender, 1 * 1e18);

        // lender adds initial quote token
        _addLiquidity({
            from:    _lender,
            amount:  41_000 * 1e18,
            index:   4549,
            lpAward: 41_000 * 1e18,
            newLup:  MAX_PRICE
        });
        _addLiquidity({
            from:    _lender,
            amount:  10_000 * 1e18,
            index:   4550,
            lpAward: 10_000 * 1e18,
            newLup:  MAX_PRICE
        });
        _addLiquidity({
            from:    _lender,
            amount:  20_000 * 1e18,
            index:   4551,
            lpAward: 20_000 * 1e18,
            newLup:  MAX_PRICE
        });   
        _addLiquidity(   {   
            from:    _lender,
            amount:  30_000 * 1e18,
            index:   4990,
            lpAward: 30_000 * 1e18,
            newLup:  MAX_PRICE
        });

        // add collateral in order to give lender LP in bucket 5_000 with 0 deposit
        // used to test revert on remove when bucket deposit is 0
        _addCollateral({
            from:    _lender,
            amount:  1 * 1e18,
            index:   5000,
            lpAward: 0.014854015662334135 * 1e18
        });

        _pledgeCollateral({
            from:     _borrower,
            borrower: _borrower,
            amount:   3_500_000 * 1e18
        });
        _borrow({
            from:       _borrower,
            amount:     70_000 * 1e18,
            indexLimit: 7_000,
            newLup:     0.139445853940958153 * 1e18
        });

        // ensure lender cannot withdraw from a bucket with no deposit
        _assertRemoveAllLiquidityNoClaimRevert({
            from:  _lender1,
            index: 4550
        });

        // should revert if no quote token in bucket deposit
        _assertRemoveInsufficientLiquidityRevert({
            from:  _lender,
            amount: 1 * 1e18,
            index:  5000
        });

        // should revert if removing quote token from higher price buckets would drive lup below htp
        _assertRemoveLiquidityLupBelowHtpRevert({
            from:   _lender,
            amount: 20_000 * 1e18,
            index:  4551
        });

        _addLiquidity({
            from:    _lender1,
            amount:  20_000 * 1e18,
            index:   4550,
            lpAward: 20_000 * 1e18,
            newLup:  _priceAt(4550)
        });

        skip(1 days); // skip to avoid penalty

        // should be able to removeQuoteToken
        _removeLiquidity({
            from:     _lender,
            amount:   10_000 * 1e18,
            index:    4990,
            newLup:   _priceAt(4550),
            lpRedeem: 10_000 * 1e18
        });
    }

    function testPoolRemoveQuoteTokenWithCollateral() external {
        // add 10 collateral into the 100 bucket, for LP worth 1000 quote tokens
        _mintCollateralAndApproveTokens(_lender, 10 * 1e18);

        uint256 i100 = _indexOf(100 * 1e18);

        _addCollateral({
            from:    _lender,
            amount:  10 * 1e18,
            index:   i100,
            lpAward: 1003.3236814328200989 * 1e18
        });

        // another lender deposits into the bucket
        _addLiquidity({
            from:    _lender1,
            amount:  900 * 1e18,
            index:   i100, 
            lpAward: 900 * 1e18,
            newLup:  MAX_PRICE
        });

        // should be able to remove a small amount of deposit
        skip(1 days);

        _removeLiquidity({
            from:     _lender,
            amount:   100 * 1e18,
            index:    i100,
            newLup:   MAX_PRICE,
            lpRedeem: 100 * 1e18
        });

        // should be able to remove the rest
        _removeAllLiquidity({
            from:     _lender,
            amount:   800 * 1e18,
            index:    i100,
            newLup:   MAX_PRICE,
            lpRedeem: 800 * 1e18
        });

        _assertBucket({
            index:        i100,
            lpBalance:    1_003.3236814328200989 * 1e18,
            collateral:   10 * 1e18,
            deposit:      0,
            exchangeRate: 1 * 1e18
        });
    }

    function testPoolRemoveQuoteTokenWithDebt() external tearDown {
        _mintCollateralAndApproveTokens(_borrower, _collateral.balanceOf(_borrower) + 100 * 1e18);

        // lender adds initial quote token
        skip(1 minutes);  // prevent deposit from having a zero timestamp

        _addLiquidity({
            from:    _lender,
            amount:  3_400 * 1e18,
            index:   1606,
            lpAward: 3_400 * 1e18,
            newLup:  MAX_PRICE
        });
        _addLiquidity({
            from:    _lender,
            amount:  3_400 * 1e18,
            index:   1663,
            lpAward: 3_400 * 1e18,
            newLup:  MAX_PRICE
        });

        _assertBucket({
            index:        1606,
            lpBalance:    3_400 * 1e18,
            collateral:   0,
            deposit:      3_400 * 1e18,
            exchangeRate: 1 * 1e18
        });
        _assertLenderLpBalance({
            lender:      _lender,
            index:       1606,
            lpBalance:   3_400 * 1e18,
            depositTime: _startTime + 1 minutes
        });
        _assertBucket({
            index:        1663,
            lpBalance:    3_400 * 1e18,
            collateral:   0,
            deposit:      3_400 * 1e18,
            exchangeRate: 1 * 1e18
        });
        _assertLenderLpBalance({
            lender:      _lender,
            index:       1663,
            lpBalance:   3_400 * 1e18,
            depositTime: _startTime + 1 minutes
        });

        skip(59 minutes);

        uint256 lenderBalanceBefore = _quote.balanceOf(_lender);

        // borrower takes a loan of 3000 quote token
        _drawDebt({
            from:               _borrower,
            borrower:           _borrower,
            amountToBorrow:     3_000 * 1e18,
            limitIndex:         2_000,
            collateralToPledge: 100 * 1e18,
            newLup:             333_777.824045947762079231 * 1e18
        });

        skip(2 hours);

        _assertLenderLpBalance({
            lender:      _lender,
            index:       1663,
            lpBalance:   3_400 * 1e18,
            depositTime: _startTime + 1 minutes
        });
        _assertLenderLpBalance({
            lender:      _lender,
            index:       1663,
            lpBalance:   3_400 * 1e18,
            depositTime: _startTime + 1 minutes
        });

        // lender makes a partial withdrawal
        uint256 withdrawal1 = 1_700 * 1e18;
        _removeLiquidity({
            from:          _lender,
            amount:        withdrawal1,
            index:         1606,
            newLup:        _priceAt(1663),
            lpRedeem:      1_699.989134088091859893 * 1e18
        });

        // lender removes all quote token, including interest, from the bucket
        skip(1 days);

        assertGt(_priceAt(1606), _htp());

        uint256 expectedWithdrawal2 = 1_700.138879728085771159 * 1e18;
        _removeAllLiquidity({
            from:     _lender,
            amount:   expectedWithdrawal2,
            index:    1606,
            newLup:   _priceAt(1663),
            lpRedeem: 1_700.010865911908140107 * 1e18
        });

        assertEq(_quote.balanceOf(_lender), lenderBalanceBefore + withdrawal1 + expectedWithdrawal2);

        _assertBucket({
            index:        1606,
            lpBalance:    0,
            collateral:   0,
            deposit:      0,
            exchangeRate: 1 * 1e18
        });
        _assertLenderLpBalance({
            lender:      _lender,
            index:       1606,
            lpBalance:   0,
            depositTime: _startTime + 1 minutes
        });
        _assertBucket({
            index:        1663,
            lpBalance:    3_400 * 1e18,
            collateral:   0,
            deposit:      3_400.256025995910604600 * 1e18,
            exchangeRate: 1.000075301763503119 * 1e18
        });
        _assertLenderLpBalance({
            lender:      _lender,
            index:       1663,
            lpBalance:   3_400 * 1e18,
            depositTime: _startTime + 1 minutes
        });
    }

    function testPoolMoveQuoteToken() external tearDown {
        _addLiquidity({
            from:    _lender,
            amount:  40_000 * 1e18,
            index:   2549,
            lpAward: 40_000 * 1e18,
            newLup:  MAX_PRICE
        });
        _addLiquidity({
            from:    _lender,
            amount:  10_000 * 1e18,
            index:   2550,
            lpAward: 10_000 * 1e18,
            newLup:  MAX_PRICE
        });   
        _addLiquidity(   {   
            from:    _lender,
            amount:  20_000 * 1e18,
            index:   2551,
            lpAward: 20_000 * 1e18,
            newLup:  MAX_PRICE
        });

        _assertLenderLpBalance({
            lender:      _lender,
            index:       2549,
            lpBalance:   40_000 * 1e18,
            depositTime: _startTime
        });
        _assertLenderLpBalance({
            lender:      _lender,
            index:       2552,
            lpBalance:   0,
            depositTime: 0
        });

        _moveLiquidity({
            from:         _lender,
            amount:       5_000 * 1e18,
            fromIndex:    2549,
            toIndex:      2552,
            lpRedeemFrom: 5_000 * 1e18,
            lpAwardTo:    5_000 * 1e18,
            newLup:       MAX_PRICE
        });

        _assertLenderLpBalance({
            lender:      _lender,
            index:       2549,
            lpBalance:   35_000 * 1e18,
            depositTime: _startTime
        });
        _assertLenderLpBalance({
            lender:      _lender,
            index:       2552,
            lpBalance:   5_000 * 1e18,
            depositTime: _startTime
        });

        _moveLiquidity({
            from:         _lender,
            amount:       5_000 * 1e18,
            fromIndex:    2549,
            toIndex:      2540,
            lpRedeemFrom: 5_000 * 1e18,
            lpAwardTo:    5_000 * 1e18,
            newLup:       MAX_PRICE
        });

        _assertLenderLpBalance({
            lender:      _lender,
            index:       2540,
            lpBalance:   5_000 * 1e18,
            depositTime: _startTime
        });
        _assertLenderLpBalance({
            lender:      _lender,
            index:       2549,
            lpBalance:   30_000 * 1e18,
            depositTime: _startTime
        });
        _assertLenderLpBalance({
            lender:      _lender,
            index:       2552,
            lpBalance:   5_000 * 1e18,
            depositTime: _startTime
        });

        _moveLiquidity({
            from:         _lender,
            amount:       15_000 * 1e18,
            fromIndex:    2551,
            toIndex:      2777,
            lpRedeemFrom: 15_000 * 1e18,
            lpAwardTo:    15_000 * 1e18,
            newLup:       MAX_PRICE
        });

        _assertLenderLpBalance({
            lender:      _lender,
            index:       2540,
            lpBalance:   5_000 * 1e18,
            depositTime: _startTime
        });
        _assertLenderLpBalance({
            lender:      _lender,
            index:       2549,
            lpBalance:   30_000 * 1e18,
            depositTime: _startTime
        });
        _assertLenderLpBalance({
            lender:      _lender,
            index:       2551,
            lpBalance:   5_000 * 1e18,
            depositTime: _startTime
        });
        _assertLenderLpBalance({
            lender:      _lender,
            index:       2552,
            lpBalance:   5_000 * 1e18,
            depositTime: _startTime
        });
        _assertLenderLpBalance({
            lender:      _lender,
            index:       2777,
            lpBalance:   15_000 * 1e18,
            depositTime: _startTime
        });
    }

    function testPoolMoveQuoteTokenWithDifferentTime() external tearDown {
        _addLiquidity({
            from:    _lender,
            amount:  40_000 * 1e18,
            index:   2549,
            lpAward: 40_000 * 1e18,
            newLup:  MAX_PRICE
        });

        skip(7 days);
        _addLiquidity({
            from:    _lender,
            amount:  10_000 * 1e18,
            index:   2550,
            lpAward: 10_000 * 1e18,
            newLup:  MAX_PRICE
        });

        _assertLenderLpBalance({
            lender:      _lender,
            index:       2549,
            lpBalance:   40_000 * 1e18,
            depositTime: _startTime
        });
        _assertLenderLpBalance({
            lender:      _lender,
            index:       2550,
            lpBalance:   10_000 * 1e18,
            depositTime: _startTime + 7 days
        });

        // move liquidity from an older deposit to a newer one, deposit time should remain the newer one
        _moveLiquidity({
            from:         _lender,
            amount:       5_000 * 1e18,
            fromIndex:    2549,
            toIndex:      2550,
            lpRedeemFrom: 5_000 * 1e18,
            lpAwardTo:    5_000 * 1e18,
            newLup:       MAX_PRICE
        });
        _assertLenderLpBalance({
            lender:      _lender,
            index:       2549,
            lpBalance:   35_000 * 1e18,
            depositTime: _startTime
        });
        _assertLenderLpBalance({
            lender:      _lender,
            index:       2550,
            lpBalance:   15_000 * 1e18,
            depositTime: _startTime + 7 days
        });

        // move liquidity from a newer deposit to an older one, deposit time should be set to the newer one
        _moveLiquidity({
            from:         _lender,
            amount:       5_000 * 1e18,
            fromIndex:    2550,
            toIndex:      2549,
            lpRedeemFrom: 5_000 * 1e18,
            lpAwardTo:    5_000 * 1e18,
            newLup:       MAX_PRICE
        });
        _assertLenderLpBalance({
            lender:      _lender,
            index:       2549,
            lpBalance:   40_000 * 1e18,
            depositTime: _startTime + 7 days
        });
        _assertLenderLpBalance({
            lender:      _lender,
            index:       2550,
            lpBalance:   10_000 * 1e18,
            depositTime: _startTime + 7 days
        });
    }

    /**
     *  @notice 1 lender, 1 bidder, 1 borrower tests reverts in moveQuoteToken.
     *          Reverts:
     *              Attempts to move quote token to the same price.
     *              Attempts to move quote token from bucket with available collateral.
     *              Attempts to move quote token when doing so would drive lup below htp.
     */
    function testPoolMoveQuoteTokenReverts() external tearDown {
        // test setup
        _mintCollateralAndApproveTokens(_lender1, _collateral.balanceOf(_lender1) + 100_000 * 1e18);
        _mintCollateralAndApproveTokens(_borrower, _collateral.balanceOf(_lender1) + 1_500_000 * 1e18);

        // lender adds initial quote token
        _addLiquidity({
            from:    _lender,
            amount:  40_000 * 1e18,
            index:   4549,
            lpAward: 40_000 * 1e18,
            newLup:  MAX_PRICE
        });
        _addLiquidity({
            from:    _lender,
            amount:  10_000 * 1e18,
            index:   4550,
            lpAward: 10_000 * 1e18,
            newLup:  MAX_PRICE
        });
        _addLiquidity({   
            from:    _lender,
            amount:  20_000 * 1e18,
            index:   4551,
            lpAward: 20_000 * 1e18,
            newLup:  MAX_PRICE
        });   
        _addLiquidity({   
            from:    _lender,
            amount:  30_000 * 1e18,
            index:   4651,
            lpAward: 30_000 * 1e18,
            newLup:  MAX_PRICE
        });

        // should revert if moving quote token to the existing price
        _assertMoveLiquidityToSameIndexRevert({
            from:      _lender,
            amount:    5_000 * 1e18,
            fromIndex: 4549,
            toIndex:   4549
        });

        // should revert if moving quote token to index 0
        _assertMoveLiquidityToIndex0Revert({
            from:      _lender,
            amount:    5_000 * 1e18,
            fromIndex: 4549
        });

        // borrow all available quote in the higher priced original 3 buckets, as well as some of the new lowest price bucket
        _pledgeCollateral({
            from:     _borrower,
            borrower: _borrower,
            amount:   1_500_000 * 1e18
        });
        _borrow({
            from:       _borrower,
            amount:     60_000.1 * 1e18,
            indexLimit: 4_651,
            newLup:     0.139445853940958153 * 1e18
        });

        // should revert if movement would drive lup below htp
        _assertMoveLiquidityLupBelowHtpRevert({
            from:      _lender,
            amount:    40_000 * 1e18,
            fromIndex: 4549,
            toIndex:   6000
        });

        // should revert if transaction expired
        _assertMoveLiquidityExpiredRevert({
            from:      _lender,
            amount:    30_000 * 1e18,
            fromIndex: 4549,
            toIndex:   4459,
            expiry:    block.timestamp - 20
        });

        // should be charged unutilized deposit fee if moving below LUP
        _moveLiquidityWithPenalty({
            from:         _lender,
            amount:       10_000 * 1e18,
            amountMoved:  9_998.630136986301370000 * 1e18,
            fromIndex:    4549,
            toIndex:      5000,
            lpRedeemFrom: 10_000 * 1e18,
            lpAwardTo:    9_998.630136986301370000 * 1e18,
            newLup:       _priceAt(4651)
        });

        // should be able to moveQuoteToken if properly specified
        (uint256 amountToMove,) = _pool.lenderInfo(5000, _lender);
        _moveLiquidity({
            from:         _lender,
            amount:       amountToMove,
            fromIndex:    5000,
            toIndex:      4550,
            lpRedeemFrom: amountToMove,
            lpAwardTo:    amountToMove,
            newLup:       _priceAt(4651)
        });
    }

    function testMoveQuoteTokenWithDebt() external tearDown {
        // lender makes an initial deposit
        skip(1 hours);

        _addLiquidity({
            from:    _lender,
            amount:  10_000 * 1e18,
            index:   2873,
            lpAward: 10_000 * 1e18,
            newLup:  MAX_PRICE
        });

        // borrower draws debt, establishing a pool threshold price
        skip(2 hours);

        _pledgeCollateral({
            from:     _borrower,
            borrower: _borrower,
            amount:   10 * 1e18
        });
        _borrow({
            from:       _borrower,
            amount:     5_000 * 1e18,
            indexLimit: 3_000,
            newLup:     601.252968524772188572 * 1e18
        });

        (uint256 poolDebt,,,) = _pool.debtInfo();
        uint256 ptp = Maths.wdiv(poolDebt, 10 * 1e18);
        assertEq(ptp, 500.480769230769231000 * 1e18);

        // lender moves some liquidity from LUP below the pool threshold price; penalty should be assessed
        skip(16 hours);
        uint256 lupIndex = 2873;
        assertEq(_lupIndex(), lupIndex);

        _moveLiquidityWithPenalty({
            from:         _lender,
            amount:       2_500 * 1e18,
            amountMoved:  2_499.657534246575342500 * 1e18,
            fromIndex:    lupIndex,
            toIndex:      2954,
            lpRedeemFrom: 2_499.902874075010987320 * 1e18,
            lpAwardTo:    2_499.657534246575342500 * 1e18,
            newLup:       _lup()
        });

        // another lender provides liquidity to prevent LUP from moving
        skip(1 hours);

        _addLiquidity({
            from:    _lender1,
            amount:  1_000 * 1e18,
            index:   2873,
            lpAward: 999.958177826584067212 * 1e18,
            newLup:  601.252968524772188572 * 1e18
        });

        // lender moves more liquidity from LUP; penalty should be assessed
        skip(12 hours);

        _moveLiquidityWithPenalty({
            from:         _lender,
            amount:       2_500 * 1e18,
            amountMoved:  2_499.691780821917807500 * 1e18,
            fromIndex:    lupIndex,
            toIndex:      2954,
            lpRedeemFrom: 2_499.816688122962822235 * 1e18,
            lpAwardTo:    2_499.691780821917807500 * 1e18,
            newLup:       _lup()
        });

        // after a week, another lender funds the pool
        skip(7 days);

        _addLiquidity({
            from:    _lender1,
            amount:  9_000 * 1e18,
            index:   2873,
            lpAward: 8_994.229791354853043265 * 1e18,
            newLup:  601.252968524772188572 * 1e18
        });
        
        // lender removes all their quote, with interest
        skip(1 hours);

        _removeAllLiquidity({
            from:     _lender,
            amount:   5_003.495432642728075897 * 1e18,
            index:    2873,
            newLup:   601.252968524772188572 * 1e18,
            lpRedeem: 5_000.280437802026190445 * 1e18
        });

        _removeAllLiquidity({
            from:     _lender,
            amount:   4_999.349315068493150000 * 1e18,
            index:    2954,
            newLup:   601.252968524772188572 * 1e18,
            lpRedeem: 4_999.349315068493150000 * 1e18
        });

        assertGt(_quote.balanceOf(_lender), 200_000 * 1e18);
    }

    function testAddRemoveQuoteTokenBucketExchangeRateInvariantDifferentActor() external tearDown {
        _mintQuoteAndApproveTokens(_lender, 1000000000000000000 * 1e18);

        uint256 initialLenderBalance = _quote.balanceOf(_lender);

        _addCollateral({
            from:    _borrower,
            amount:  13167,
            index:   2570,
            lpAward: 35880690
        });

        _assertLenderLpBalance({
            lender:      _borrower,
            index:       2570,
            lpBalance:   35880690,
            depositTime: _startTime
        });
        _assertLenderLpBalance({
            lender:      _lender,
            index:       2570,
            lpBalance:   0,
            depositTime: 0
        });
        _assertBucket({
            index:        2570,
            lpBalance:    35880690,
            collateral:   13167,
            deposit:      0,
            exchangeRate: 1 * 1e18
        });

        _addLiquidity({
            from:    _lender,
            amount:  984665640564039457.584007913129639933 * 1e18,
            index:   2570,
            lpAward: 984665640564039457.584007913129639933 * 1e18,
            newLup:  MAX_PRICE
        });

        _assertLenderLpBalance({
            lender:      _borrower,
            index:       2570,
            lpBalance:   35880690,
            depositTime: _startTime
        });
        _assertLenderLpBalance({
            lender:      _lender,
            index:       2570,
            lpBalance:   984665640564039457.584007913129639933 * 1e18,
            depositTime: _startTime
        });
        _assertBucket({
            index:        2570,
            lpBalance:    984665640564039457.584007913165520623 * 1e18,
            collateral:   13167,
            deposit:      984665640564039457.584007913129639933 * 1e18,
            exchangeRate: 1 * 1e18 // exchange rate should not change
        });

        skip(48 hours); // to avoid penalty

        _removeAllLiquidity({
            from:     _lender,
            amount:   984665640564039457.584007913129639933 * 1e18,
            index:    2570,
            newLup:   MAX_PRICE,
            lpRedeem: 984665640564039457.584007913129639933 * 1e18
        });

        _assertLenderLpBalance({
            lender:      _borrower,
            index:       2570,
            lpBalance:   35880690,
            depositTime: _startTime
        });
        _assertLenderLpBalance({
            lender:      _lender,
            index:       2570,
            lpBalance:   0, // LP should get back to same value as before add / remove collateral
            depositTime: _startTime
        });
        _assertBucket({
            index:        2570,
            lpBalance:    35880690,
            collateral:   13167,
            deposit:      0,
            exchangeRate: 1 * 1e18 // exchange rate should not change
        });

        assertEq(_quote.balanceOf(_lender), initialLenderBalance);
    }

    function testRemoveQuoteTokenPoolBalanceLimit() external tearDown {
        _addLiquidity({
            from:    _lender,
            amount:  0.000000059754288926 * 1e18,
            index:   852,
            lpAward: 0.000000059754288926 * 1e18,
            newLup:  MAX_PRICE
        });

        _assertLenderLpBalance({
            lender:      _lender,
            index:       852,
            lpBalance:   0.000000059754288926 * 1e18,
            depositTime: _startTime
        });

        _assertPool(
            PoolParams({
                htp:                  0,
                lup:                  MAX_PRICE,
                poolSize:             0.000000059754288926 * 1e18,
                pledgedCollateral:    0,
                encumberedCollateral: 0,
                poolDebt:             0,
                actualUtilization:    0,
                targetUtilization:    1e18,
                minDebtAmount:        0,
                loans:                0,
                maxBorrower:          address(0),
                interestRate:         0.05 * 1e18,
                interestRateUpdate:   _startTime
            })
        );

        _drawDebt({
            from:               _borrower,
            borrower:           _borrower,
            amountToBorrow:     0.000000029877144463 * 1e18,
            limitIndex:         7388,
            collateralToPledge: 1 * 1e18,
            newLup:             14_343_926.246295999585280544 * 1e18
        });

        _assertPool(
            PoolParams({
                htp:                  0.000000029905872487 * 1e18,
                lup:                  14_343_926.246295999585280544 * 1e18,
                poolSize:             0.000000059754288926 * 1e18,
                pledgedCollateral:    1 * 1e18,
                encumberedCollateral: 2085,
                poolDebt:             0.000000029905872487 * 1e18,
                actualUtilization:    0,
                targetUtilization:    1e18,
                minDebtAmount:        0.000000002990587249 * 1e18,
                loans:                1,
                maxBorrower:          _borrower,
                interestRate:         0.05 * 1e18,
                interestRateUpdate:   _startTime
            })
        );

        skip(200 days);

        _assertPool(
            PoolParams({
                htp:                  0.000000029905872487 * 1e18,
                lup:                  14_343_926.246295999585280544 * 1e18,
                poolSize:             0.000000059754288926 * 1e18,
                pledgedCollateral:    1 * 1e18,
                encumberedCollateral: 2143,
                poolDebt:             0.000000030736538487 * 1e18,
                actualUtilization:    0,
                targetUtilization:    1e18,
                minDebtAmount:        0.000000003073653849 * 1e18,
                loans:                1,
                maxBorrower:          _borrower,
                interestRate:         0.05 * 1e18,
                interestRateUpdate:   _startTime
            })
        );

        assertEq(_quote.balanceOf(address(_pool)), 0.000000029877144463 * 1e18);

        // removeQuoteToken should revert as LUP is bellow HTP
        _assertRemoveAllLiquidityLupBelowHtpRevert({
            from:     _lender,
            index:    852
        });
    }
}
