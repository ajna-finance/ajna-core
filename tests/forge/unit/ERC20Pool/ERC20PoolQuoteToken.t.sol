// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.18;

import { ERC20HelperContract } from './ERC20DSTestPlus.sol';

import 'src/interfaces/pool/IPool.sol';
import 'src/libraries/helpers/PoolHelper.sol';

contract ERC20PoolQuoteTokenTest is ERC20HelperContract {

    address internal _borrower;
    address internal _borrower2;
    address internal _lender;
    address internal _lender1;

    function setUp() external {
        _startTest();

        _borrower  = makeAddr("borrower");
        _borrower2 = makeAddr("borrower2");
        _lender    = makeAddr("lender");
        _lender1   = makeAddr("bidder");

        _mintCollateralAndApproveTokens(_borrower,   5_000 * 1e18);
        _mintCollateralAndApproveTokens(_borrower2,  5_000 * 1e18);

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

        uint256 deposit2550 = 9_999.543378995433790000 * 1e18;
        _assertPool(
            PoolParams({
                htp:                  0,
                lup:                  MAX_PRICE,
                poolSize:             deposit2550,
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
            lpBalance:    deposit2550,
            collateral:   0,
            deposit:      deposit2550,
            exchangeRate: 1 * 1e18
        });
        _assertLenderLpBalance({
            lender:      _lender,
            index:       2550,
            lpBalance:   deposit2550,
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
                poolSize:             29_998.630136986301370000 * 1e18,
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
            lpBalance:    deposit2550,
            collateral:   0,
            deposit:      deposit2550,
            exchangeRate: 1 * 1e18
        });
        _assertLenderLpBalance({
            lender:      _lender,
            index:       2550,
            lpBalance:   deposit2550,
            depositTime: _startTime
        });
        uint256 deposit2551 = 19_999.086757990867580000 * 1e18;
        _assertBucket({
            index:        2551,
            lpBalance:    deposit2551,
            collateral:   0,
            deposit:      deposit2551,
            exchangeRate: 1 * 1e18
        });
        _assertLenderLpBalance({
            lender:      _lender,
            index:       2551,
            lpBalance:   deposit2551,
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
                poolSize:             69_996.803652968036530000 * 1e18,
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
        uint256 deposit2549 = 39_998.173515981735160000 * 1e18;
        _assertBucket({
            index:        2549,
            lpBalance:    deposit2549,
            collateral:   0,
            deposit:      deposit2549,
            exchangeRate: 1 * 1e18
        });
        _assertLenderLpBalance({
            lender:      _lender,
            index:       2549,
            lpBalance:   deposit2549,
            depositTime: _startTime
        });
        _assertBucket({
            index:        2550,
            lpBalance:    deposit2550,
            collateral:   0,
            deposit:      deposit2550,
            exchangeRate: 1 * 1e18
        });
        _assertLenderLpBalance({
            lender:      _lender,
            index:       2550,
            lpBalance:   deposit2550,
            depositTime: _startTime
        });
        _assertBucket({
            index:        2551,
            lpBalance:    deposit2551,
            collateral:   0,
            deposit:      deposit2551,
            exchangeRate: 1 * 1e18
        });
        _assertLenderLpBalance({
            lender:      _lender,
            index:       2551,
            lpBalance:   deposit2551,
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

    function testPoolRemoveQuoteTokenBasic() external tearDown {
       _addLiquidity({
            from:    _lender,
            amount:  40_000 * 1e18,
            index:   2549,
            lpAward: 39_998.173515981735160000 * 1e18,
            newLup:  MAX_PRICE
        });
       _addLiquidity({
            from:    _lender,
            amount:  10_000 * 1e18,
            index:   2550,
            lpAward: 9_999.543378995433790000 * 1e18,
            newLup:  MAX_PRICE
        });   
       _addLiquidity(   {   
            from:    _lender,
            amount:  20_000 * 1e18,
            index:   2551,
            lpAward: 19_999.086757990867580000 * 1e18,
            newLup:  MAX_PRICE
        });

        _assertPool(
            PoolParams({
                htp:                  0,
                lup:                  MAX_PRICE,
                poolSize:             69_996.803652968036530000 * 1e18,
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
            lpBalance:    39_998.173515981735160000 * 1e18,
            collateral:   0,
            deposit:      39_998.173515981735160000 * 1e18,
            exchangeRate: 1 * 1e18
        });
       _assertLenderLpBalance({
            lender:      _lender,
            index:       2549,
            lpBalance:   39_998.173515981735160000 * 1e18,
            depositTime: _startTime
        });
        _assertBucket({
            index:        2550,
            lpBalance:    9_999.543378995433790000 * 1e18,
            collateral:   0,
            deposit:      9_999.543378995433790000 * 1e18,
            exchangeRate: 1 * 1e18
        });
        _assertLenderLpBalance({
            lender:      _lender,
            index:       2550,
            lpBalance:   9_999.543378995433790000 * 1e18,
            depositTime: _startTime
        });
        _assertBucket({
            index:        2551,
            lpBalance:    19_999.086757990867580000 * 1e18,
            collateral:   0,
            deposit:      19_999.086757990867580000 * 1e18,
            exchangeRate: 1 * 1e18
        });
        _assertLenderLpBalance({
            lender:      _lender,
            index:       2551,
            lpBalance:   19_999.086757990867580000 * 1e18,
            depositTime: _startTime
        });

        // check balances
        assertEq(_quote.balanceOf(address(_pool)), 70_000 * 1e18);
        assertEq(_quote.balanceOf(_lender),        130_000 * 1e18);

        // partial remove
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
                poolSize:             64_996.803652968036530000 * 1e18,
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
            lpBalance:    34_998.173515981735160000 * 1e18,
            collateral:   0,
            deposit:      34_998.173515981735160000 * 1e18,
            exchangeRate: 1 * 1e18
        });
        _assertLenderLpBalance({
            lender:      _lender,
            index:       2549,
            lpBalance:   34_998.173515981735160000 * 1e18,
            depositTime: _startTime
        });
        _assertBucket({
            index:        2550,
            lpBalance:    9_999.543378995433790000 * 1e18,
            collateral:   0,
            deposit:      9_999.543378995433790000 * 1e18,
            exchangeRate: 1 * 1e18
        });
        _assertLenderLpBalance({
            lender:      _lender,
            index:       2550,
            lpBalance:   9_999.543378995433790000 * 1e18,
            depositTime: _startTime
        });
        _assertBucket({
            index:        2551,
            lpBalance:    19_999.086757990867580000 * 1e18,
            collateral:   0,
            deposit:      19_999.086757990867580000 * 1e18,
            exchangeRate: 1 * 1e18
        });
        _assertLenderLpBalance({
            lender:      _lender,
            index:       2551,
            lpBalance:   19_999.086757990867580000 * 1e18,
            depositTime: _startTime
        });

        // check balances
        assertEq(_quote.balanceOf(address(_pool)), 65_000 * 1e18);
        assertEq(_quote.balanceOf(_lender),        135_000 * 1e18);

        // full remove
        _removeAllLiquidity({
            from:     _lender,
            amount:   34_998.173515981735160000 * 1e18,
            index:    2549,
            newLup:   MAX_PRICE,
            lpRedeem: 34_998.173515981735160000 * 1e18
        });

        _assertPool(
            PoolParams({
                htp:                  0,
                lup:                  MAX_PRICE,
                poolSize:             29_998.630136986301370000 * 1e18,
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
            lpBalance:    9_999.543378995433790000 * 1e18,
            collateral:   0,
            deposit:      9_999.543378995433790000 * 1e18,
            exchangeRate: 1 * 1e18
        });
        _assertLenderLpBalance({
            lender:      _lender,
            index:       2550,
            lpBalance:   9_999.543378995433790000 * 1e18,
            depositTime: _startTime
        });
        _assertBucket({
            index:        2551,
            lpBalance:    19_999.086757990867580000 * 1e18,
            collateral:   0,
            deposit:      19_999.086757990867580000 * 1e18,
            exchangeRate: 1 * 1e18
        });
        _assertLenderLpBalance({
            lender:      _lender,
            index:       2551,
            lpBalance:   19_999.086757990867580000 * 1e18,
            depositTime: _startTime
        });

        // check balances
        assertEq(_quote.balanceOf(address(_pool)), 30_001.826484018264840000 * 1e18);
        assertEq(_quote.balanceOf(_lender),        169_998.173515981735160000 * 1e18);
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
            lpAward: 10_999.497716894977169000 * 1e18,
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
        });
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
            lpAward: 40_998.127853881278539000 * 1e18,
            newLup:  MAX_PRICE
        });
        _addLiquidity({
            from:    _lender,
            amount:  10_000 * 1e18,
            index:   4550,
            lpAward: 9_999.543378995433790000 * 1e18,
            newLup:  MAX_PRICE
        });
        _addLiquidity({
            from:    _lender,
            amount:  20_000 * 1e18,
            index:   4551,
            lpAward: 19_999.086757990867580000 * 1e18,
            newLup:  MAX_PRICE
        });   
        _addLiquidity(   {   
            from:    _lender,
            amount:  30_000 * 1e18,
            index:   4990,
            lpAward: 29_998.630136986301370000 * 1e18,
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
            lpAward: 19_999.086757990867580000 * 1e18,
            newLup:  _priceAt(4550)
        });

        // should be able to removeQuoteToken
        _removeAllLiquidity({
            from:     _lender,
            amount:   29_998.630136986301370000 * 1e18,
            index:    4990,
            newLup:   _priceAt(4550),
            lpRedeem: 29_998.630136986301370000 * 1e18
        });
    }

    function testPoolRemoveQuoteTokenWithCollateral() external tearDown {
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
            lpAward: 899.958904109589041100 * 1e18,
            newLup:  MAX_PRICE
        });

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
            amount:   799.958904109589041100 * 1e18,
            index:    i100,
            newLup:   MAX_PRICE,
            lpRedeem: 799.958904109589041100 * 1e18
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

        uint256 liquidityAdded = 3_399.844748858447488600 * 1e18;
        _addLiquidity({
            from:    _lender,
            amount:  3_400 * 1e18,
            index:   1606,
            lpAward: liquidityAdded,
            newLup:  MAX_PRICE
        });
        _addLiquidity({
            from:    _lender,
            amount:  3_400 * 1e18,
            index:   1663,
            lpAward: liquidityAdded,
            newLup:  MAX_PRICE
        });

        _assertBucket({
            index:        1606,
            lpBalance:    liquidityAdded,
            collateral:   0,
            deposit:      liquidityAdded,
            exchangeRate: 1 * 1e18
        });
        _assertLenderLpBalance({
            lender:      _lender,
            index:       1606,
            lpBalance:   liquidityAdded,
            depositTime: _startTime + 1 minutes
        });
        _assertBucket({
            index:        1663,
            lpBalance:    liquidityAdded,
            collateral:   0,
            deposit:      liquidityAdded,
            exchangeRate: 1 * 1e18
        });
        _assertLenderLpBalance({
            lender:      _lender,
            index:       1663,
            lpBalance:   liquidityAdded,
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
            lpBalance:   liquidityAdded,
            depositTime: _startTime + 1 minutes
        });
        _assertLenderLpBalance({
            lender:      _lender,
            index:       1663,
            lpBalance:   liquidityAdded,
            depositTime: _startTime + 1 minutes
        });

        // lender makes a partial withdrawal
        uint256 withdrawal1 = 1_700 * 1e18;
        _removeLiquidity({
            from:          _lender,
            amount:        withdrawal1,
            index:         1606,
            newLup:        _priceAt(1663),
            lpRedeem:      1_699.992715262243008677 * 1e18
        });

        // lender removes all quote token, including interest, from the bucket
        skip(1 days);

        assertGt(_priceAt(1606), _getHtp());

        uint256 expectedWithdrawal2 = 1_699.976461135759488146 * 1e18;
        _removeAllLiquidity({
            from:     _lender,
            amount:   expectedWithdrawal2,
            index:    1606,
            newLup:   _priceAt(1663),
            lpRedeem: 1_699.852033596204479923 * 1e18
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
            lpBalance:    3_399.844748858447488600 * 1e18,
            collateral:   0,
            deposit:      3_400.093614235320616015 * 1e18,
            exchangeRate: 1.000073199041502318 * 1e18
        });
        _assertLenderLpBalance({
            lender:      _lender,
            index:       1663,
            lpBalance:   3_399.844748858447488600 * 1e18,
            depositTime: _startTime + 1 minutes
        });
    }

    function testPoolMoveQuoteTokenBasic() external tearDown {
        _addLiquidity({
            from:    _lender,
            amount:  40_000 * 1e18,
            index:   2549,
            lpAward: 39_998.173515981735160000 * 1e18,
            newLup:  MAX_PRICE
        });
        _addLiquidity({
            from:    _lender,
            amount:  10_000 * 1e18,
            index:   2550,
            lpAward: 9_999.543378995433790000 * 1e18,
            newLup:  MAX_PRICE
        });   
        _addLiquidity(   {   
            from:    _lender,
            amount:  20_000 * 1e18,
            index:   2551,
            lpAward: 19_999.086757990867580000 * 1e18,
            newLup:  MAX_PRICE
        });

        _assertLenderLpBalance({
            lender:      _lender,
            index:       2549,
            lpBalance:   39_998.173515981735160000 * 1e18,
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
            lpAwardTo:    4_999.771689497716895000 * 1e18,
            newLup:       MAX_PRICE
        });

        _assertLenderLpBalance({
            lender:      _lender,
            index:       2549,
            lpBalance:   34_998.173515981735160000 * 1e18,
            depositTime: _startTime
        });
        _assertLenderLpBalance({
            lender:      _lender,
            index:       2552,
            lpBalance:   4_999.771689497716895000 * 1e18,
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
            lpBalance:   29_998.173515981735160000 * 1e18,
            depositTime: _startTime
        });
        _assertLenderLpBalance({
            lender:      _lender,
            index:       2552,
            lpBalance:   4_999.771689497716895000 * 1e18,
            depositTime: _startTime
        });

        _moveLiquidity({
            from:         _lender,
            amount:       15_000 * 1e18,
            fromIndex:    2551,
            toIndex:      2777,
            lpRedeemFrom: 15_000 * 1e18,
            lpAwardTo:    14_999.315068493150685000 * 1e18,
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
            lpBalance:   29_998.173515981735160000 * 1e18,
            depositTime: _startTime
        });
        _assertLenderLpBalance({
            lender:      _lender,
            index:       2551,
            lpBalance:   4_999.086757990867580000 * 1e18,
            depositTime: _startTime
        });
        _assertLenderLpBalance({
            lender:      _lender,
            index:       2552,
            lpBalance:   4_999.771689497716895000 * 1e18,
            depositTime: _startTime
        });
        _assertLenderLpBalance({
            lender:      _lender,
            index:       2777,
            lpBalance:   14_999.315068493150685000 * 1e18,
            depositTime: _startTime
        });
    }

    function testPoolMoveQuoteTokenRevertOnHTPLUP() external tearDown {
        _addLiquidity({
            from:    _lender,
            amount:  40_000 * 1e18,
            index:   2549,
            lpAward: 39_998.173515981735160000 * 1e18,
            newLup:  MAX_PRICE
        });
        _addLiquidity({
            from:    _lender,
            amount:  10_000 * 1e18,
            index:   2550,
            lpAward: 9_999.543378995433790000 * 1e18,
            newLup:  MAX_PRICE
        });   
        _addLiquidity({   
            from:    _lender,
            amount:  20_000 * 1e18,
            index:   2551,
            lpAward: 19_999.086757990867580000 * 1e18,
            newLup:  MAX_PRICE
        });
        _addLiquidity({   
            from:    _lender,
            amount:  20_000 * 1e18,
            index:   2540,
            lpAward: 19_999.086757990867580000 * 1e18,
            newLup:  MAX_PRICE
        });
        _assertLenderLpBalance({
            lender:      _lender,
            index:       2549,
            lpBalance:   39_998.173515981735160000 * 1e18,
            depositTime: _startTime
        });
        _assertLenderLpBalance({
            lender:      _lender,
            index:       2540,
            lpBalance:   19_999.086757990867580000 * 1e18,
            depositTime: _startTime
        });
        _assertLenderLpBalance({
            lender:      _lender,
            index:       2552,
            lpBalance:   0,
            depositTime: 0
        });
        // ignoring deposit fee, book:
        // bucket   deposit cumulative
        // 2540     20k     20k
        // 2549     40k     60k
        // 2550     10k     70k
        // 2551     20k     90k

        uint256 snapshot = vm.snapshot();

        uint256 newLup = 2_995.912459898389633881 * 1e18;
        assertEq(_indexOf(newLup), 2551);
        _drawDebt({
            from:               _borrower,
            borrower:           _borrower,
            amountToBorrow:     85_000 * 1e18,
            limitIndex:         7_388,
            collateralToPledge: 30 * 1e18,
            newLup:             newLup
        });

        _assertBorrower({
            borrower:                  _borrower,
            borrowerDebt:              85_081.730769230769270000 * 1e18,
            borrowerCollateral:        30.0 * 1e18,
            borrowert0Np:              3_279.264124981781484570 * 1e18,
            borrowerCollateralization: 1.015735704322220591 * 1e18
        });

        _drawDebt({
            from:               _borrower2,
            borrower:           _borrower2,
            amountToBorrow:     900 * 1e18,
            limitIndex:         7_388,
            collateralToPledge: 5_000 * 1e18,
            newLup:             2_995.912459898389633881 * 1e18
        });

        _assertPool(
            PoolParams({
                htp:                  2_949.500000000000001360 * 1e18,
                lup:                  2_995.912459898389633881 * 1e18,
                poolSize:             89_995.890410958904110000 * 1e18,
                pledgedCollateral:    5_030.0 * 1e18,
                encumberedCollateral: 29.847968255732299676 * 1e18,
                poolDebt:             85_982.596153846153885800 * 1e18,
                actualUtilization:    0 * 1e18,
                targetUtilization:    1.0 * 1e18,
                minDebtAmount:        4_299.129807692307694290 * 1e18,
                loans:                2,
                maxBorrower:          _borrower,
                interestRate:         0.050000000000000000 * 1e18,
                interestRateUpdate:   _startTime
            })
        );

        // ensure htp > lup to fire error
        _assertLupBelowHTPRevert({
            from:         _lender,
            fromIndex:    2549,
            toIndex:      3000,
            amount:       40_000 * 1e18
        });

        vm.revertTo(snapshot);

        _drawDebt({
            from:               _borrower,
            borrower:           _borrower,
            amountToBorrow:     89_900 * 1e18,
            limitIndex:         7_388,
            collateralToPledge: 5_000 * 1e18,
            newLup:             2_995.912459898389633881 * 1e18
        });

        _assertPool(
            PoolParams({
                htp:                  18.717180000000000009 * 1e18,
                lup:                  2_995.912459898389633881 * 1e18,
                poolSize:             89_995.890410958904110000 * 1e18,
                pledgedCollateral:    5000.0 * 1e18,
                encumberedCollateral: 31.237862004544048206 * 1e18,
                poolDebt:             89_986.442307692307733800 * 1e18,
                actualUtilization:    0 * 1e18,
                targetUtilization:    1.0 * 1e18,
                minDebtAmount:        8_998.644230769230773380 * 1e18,
                loans:                1,
                maxBorrower:          _borrower,
                interestRate:         0.050000000000000000 * 1e18,
                interestRateUpdate:   _startTime
            })
        );

        skip(50 days);

        // htp > lup && debt > deposit
        _assertLupBelowHTPRevert({
            from:         _lender,
            fromIndex:    2549,
            toIndex:      3000,
            amount:       40_000 * 1e18
        });
    }

    function testPoolMoveQuoteTokenWithDifferentTime() external tearDown {
        _addLiquidity({
            from:    _lender,
            amount:  40_000 * 1e18,
            index:   2549,
            lpAward: 39_998.173515981735160000 * 1e18,
            newLup:  MAX_PRICE
        });

        skip(7 days);
        _addLiquidity({
            from:    _lender,
            amount:  10_000 * 1e18,
            index:   2550,
            lpAward: 9_999.543378995433790000 * 1e18,
            newLup:  MAX_PRICE
        });

        _assertLenderLpBalance({
            lender:      _lender,
            index:       2549,
            lpBalance:   39_998.173515981735160000 * 1e18,
            depositTime: _startTime
        });
        _assertLenderLpBalance({
            lender:      _lender,
            index:       2550,
            lpBalance:   9_999.543378995433790000 * 1e18,
            depositTime: _startTime + 7 days
        });

        // move liquidity from an older deposit to a newer one, deposit time should remain the newer one
        _moveLiquidity({
            from:         _lender,
            amount:       5_000 * 1e18,
            fromIndex:    2549,
            toIndex:      2550,
            lpRedeemFrom: 5_000 * 1e18,
            lpAwardTo:    4_999.794520547945205000 * 1e18,
            newLup:       MAX_PRICE
        });
        _assertLenderLpBalance({
            lender:      _lender,
            index:       2549,
            lpBalance:   34_998.173515981735160000 * 1e18,
            depositTime: _startTime
        });
        _assertLenderLpBalance({
            lender:      _lender,
            index:       2550,
            lpBalance:   14_999.337899543378995000 * 1e18,
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
            lpBalance:   39_998.173515981735160000 * 1e18,
            depositTime: _startTime + 7 days
        });
        _assertLenderLpBalance({
            lender:      _lender,
            index:       2550,
            lpBalance:   9_999.337899543378995000 * 1e18,
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
    function testPoolMoveQuoteTokenReverts() external {
        // test setup
        _mintCollateralAndApproveTokens(_lender1, _collateral.balanceOf(_lender1) + 100_000 * 1e18);
        _mintCollateralAndApproveTokens(_borrower, _collateral.balanceOf(_lender1) + 1_500_000 * 1e18);

        // lender adds initial quote token
        _addLiquidity({
            from:    _lender,
            amount:  40_000 * 1e18,
            index:   4549,
            lpAward: 39_998.173515981735160000 * 1e18,
            newLup:  MAX_PRICE
        });
        _addLiquidity({
            from:    _lender,
            amount:  10_000 * 1e18,
            index:   4550,
            lpAward: 9_999.543378995433790000 * 1e18,
            newLup:  MAX_PRICE
        });
        _addLiquidity({   
            from:    _lender,
            amount:  20_000 * 1e18,
            index:   4551,
            lpAward: 19_999.086757990867580000 * 1e18,
            newLup:  MAX_PRICE
        });   
        _addLiquidity({   
            from:    _lender,
            amount:  30_000 * 1e18,
            index:   4651,
            lpAward: 29_998.630136986301370000 * 1e18,
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

        // should be charged fee for moving to lower bucket
        _moveLiquidityWithPenalty({
            from:         _lender,
            amount:       10_000 * 1e18,
            amountMoved:  9_999.543378995433790000 * 1e18,
            fromIndex:    4549,
            toIndex:      5000,
            lpRedeemFrom: 10_000 * 1e18,
            lpAwardTo:    9_999.543378995433790000 * 1e18,
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
            lpAwardTo:    9_999.543378995433790000 * 1e18,
            newLup:       0.139445853940958153 * 1e18
        });
    }

    function testMoveQuoteTokenWithDebt() external tearDown {
        // lender makes an initial deposit
        skip(1 hours);

        _addLiquidity({
            from:    _lender,
            amount:  10_000 * 1e18,
            index:   2873,
            lpAward: 9_999.543378995433790000 * 1e18,
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
            amountMoved:  2_499.885844748858447500 * 1e18,
            fromIndex:    lupIndex,
            toIndex:      2954,
            lpRedeemFrom: 2_499.902869640007040861 * 1e18,
            lpAwardTo:    2_499.885844748858447500 * 1e18,
            newLup:       _lup()
        });

        // another lender provides liquidity to prevent LUP from moving
        skip(1 hours);

        _addLiquidity({
            from:    _lender1,
            amount:  1_000 * 1e18,
            index:   2873,
            lpAward: 999.917081697041550606 * 1e18,
            newLup:  601.252968524772188572 * 1e18
        });

        // lender moves more liquidity from LUP; penalty should be assessed
        skip(12 hours);

        _moveLiquidityWithPenalty({
            from:         _lender,
            amount:       2_500 * 1e18,
            amountMoved:  2_499.897260273972602500 * 1e18,
            fromIndex:    lupIndex,
            toIndex:      2954,
            lpRedeemFrom: 2_499.816678530752331668 * 1e18,
            lpAwardTo:    2_499.897260273972602500 * 1e18,
            newLup:       _lup()
        });

        // after a week, another lender funds the pool
        skip(7 days);

        _addLiquidity({
            from:    _lender1,
            amount:  9_000 * 1e18,
            index:   2873,
            lpAward: 8_993.896659993261260864 * 1e18,
            newLup:  601.252968524772188572 * 1e18
        });
        
        // lender removes all their quote, with interest
        skip(1 hours);

        _removeAllLiquidity({
            from:     _lender,
            amount:   5_003.038792937182565795 * 1e18,
            index:    2873,
            newLup:   601.252968524772188572 * 1e18,
            lpRedeem: 4_999.823830824674417471 * 1e18
        });

        _removeAllLiquidity({
            from:     _lender,
            amount:   4_999.783105022831050000 * 1e18,
            index:    2954,
            newLup:   601.252968524772188572 * 1e18,
            lpRedeem: 4_999.783105022831050000 * 1e18
        });

        assertGt(_quote.balanceOf(_lender), 200_000 * 1e18);
    }

    function testAddRemoveQuoteTokenBucketExchangeRateInvariantDifferentActor() external tearDown {
        _mintQuoteAndApproveTokens(_lender, 1000000000000000000 * 1e18);

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
            exchangeRate: 0.999999989125110331 * 1e18
        });

        _addLiquidity({
            from:    _lender,
            amount:  984665640564039457.584007913129639933 * 1e18,
            index:   2570,
            lpAward: 984620689370285202.512316095607611762 * 1e18,
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
            lpBalance:   984620689370285202.512316095607611762 * 1e18,
            depositTime: _startTime
        });
        _assertBucket({
            index:        2570,
            lpBalance:    984620689370285202.512316095643492452 * 1e18,
            collateral:   13167,
            deposit:      984620678662643839.348431774140748349 * 1e18,
            exchangeRate: 0.999999989125110331 * 1e18 // exchange rate should not change
        });

        // remove all but 1 gwei from the bucket
        _removeLiquidity({
            from:     _lender,
            amount:   984620678662643839.348431774140748348 * 1e18,
            index:    2570,
            newLup:   MAX_PRICE,
            lpRedeem: 984620689370285202.512316095607611762 * 1e18
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
            deposit:      1,
            exchangeRate: 1.000000016995254411 * 1e18
        });

        // show the pool only has 1 gwei liquidity, although reserves accumulated due to deposit fee
        _assertPool(
            PoolParams({
                htp:                  0,
                lup:                  MAX_PRICE,
                poolSize:             1,
                pledgedCollateral:    0,
                encumberedCollateral: 0,
                poolDebt:             0,
                actualUtilization:    0,
                targetUtilization:    1 * 1e18,
                minDebtAmount:        0,
                loans:                0,
                maxBorrower:          address(0),
                interestRate:         0.050000000000000000 * 1e18,
                interestRateUpdate:   _startTime
            })
        );
        assertEq(_quote.balanceOf(address(_pool)), 44961901395618.235576138988891585 * 1e18);
        assertEq(_quote.balanceOf(_lender), 999955038098604381.764423861011108415 * 1e18);

        // bucket can be healed by adding liquidity / collateral
        _addLiquidity({
            from:    _lender,
            amount:  100 * 1e18,
            index:   2570,
            lpAward: 99.995432090506529601 * 1e18,
            newLup:  MAX_PRICE
        });
        _addCollateral({
            from:    _borrower,
            amount:  1 * 1e18,
            index:   2570,
            lpAward: 2_725.046631730843547903 * 1e18
        });
    }

    function testRemoveQuoteTokenPoolBalanceLimit() external tearDown {
        _addLiquidity({
            from:    _lender,
            amount:  0.000000059754288926 * 1e18,
            index:   852,
            lpAward: 0.000000059751560420 * 1e18,
            newLup:  MAX_PRICE
        });

        _assertLenderLpBalance({
            lender:      _lender,
            index:       852,
            lpBalance:   0.000000059751560420 * 1e18,
            depositTime: _startTime
        });

        _assertPool(
            PoolParams({
                htp:                  0,
                lup:                  MAX_PRICE,
                poolSize:             0.000000059751560420 * 1e18,
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
                htp:                  0.000000031102107386 * 1e18,
                lup:                  14_343_926.246295999585280544 * 1e18,
                poolSize:             0.000000059751560420 * 1e18,
                pledgedCollateral:    1 * 1e18,
                encumberedCollateral: 2168,
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
                htp:                  0.000000031966000026 * 1e18,
                lup:                  14_343_926.246295999585280544 * 1e18,
                poolSize:             0.000000059751560420 * 1e18,
                pledgedCollateral:    1 * 1e18,
                encumberedCollateral: 2229,
                poolDebt:             0.000000030736538488 * 1e18,
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

    function testAddLiquidityAboveAuctionPrice() external {

        // Lender adds Quote token accross 5 prices
        _addInitialLiquidity({
            from:   _lender,
            amount: 2_000 * 1e18,
            index:  _i9_91
        });
        _addInitialLiquidity({
            from:   _lender,
            amount: 5_000 * 1e18,
            index:  _i9_81
        });
        _addInitialLiquidity({
            from:   _lender,
            amount: 11_000 * 1e18,
            index:  _i9_72
        });
        _addInitialLiquidity({
            from:   _lender,
            amount: 25_000 * 1e18,
            index:  _i9_62
        });
        _addInitialLiquidity({
            from:   _lender,
            amount: 30_000 * 1e18,
            index:  _i9_52
        });

        // first borrower pledge collateral and borrows
        _pledgeCollateral({
            from:     _borrower,
            borrower: _borrower,
            amount:   2 * 1e18
        });
        _borrow({
            from:       _borrower,
            amount:     19.0 * 1e18,
            indexLimit: _i9_91,
            newLup:     9.917184843435912074 * 1e18
        });

        // Skip to make borrower undercollateralized
        skip(100 days);

        _assertAuction(
            AuctionParams({
                borrower:          _borrower,
                active:            false,
                kicker:            address(0),
                bondSize:          0,
                bondFactor:        0,
                kickTime:          0,
                referencePrice:    0,
                totalBondEscrowed: 0,
                auctionPrice:      0,
                debtInAuction:     0,
                debtToCollateral:  0,
                neutralPrice:      0
            })
        );
        _assertBorrower({
            borrower:                  _borrower,
            borrowerDebt:              19.280586055366139163 * 1e18,
            borrowerCollateral:        2 * 1e18,
            borrowert0Np:              10.995179713174208507 * 1e18,
            borrowerCollateralization: 0.989156100314278654 * 1e18
        });
        
        _kick({
            from:           _lender,
            borrower:       _borrower,
            debt:           19.280586055366139162 * 1e18,
            collateral:     2 * 1e18,
            bond:           0.215563505329166046 * 1e18,
            transferAmount: 0.215563505329166046 * 1e18
        });

        _assertAuction(
            AuctionParams({
                borrower:          _borrower,
                active:            true,
                kicker:            _lender,
                bondSize:          0.215563505329166046 * 1e18,
                bondFactor:        0.011180339887498948 * 1e18,
                kickTime:          block.timestamp,
                referencePrice:    11.146834976502055842 * 1e18,
                totalBondEscrowed: 0.215563505329166046 * 1e18,
                auctionPrice:      2_853.589753984526295552 * 1e18,
                debtInAuction:     19.280586055366139163 * 1e18,
                debtToCollateral:  9.640293027683069581 * 1e18,
                neutralPrice:      11.146834976502055842 * 1e18
            })
        );
        _assertKicker({
            kicker:    _lender,
            claimable: 0,
            locked:    0.215563505329166046 * 1e18
        });

        _addLiquidityWithPenalty({
            from:        _lender1,
            amount:      1 * 1e18,
            amountAdded: 0.999958904109589041 * 1e18,
            index:       _i9_52,
            lpAward:     0.999958904109589041 * 1e18,
            newLup:      9.917184843435912074 * 1e18
        });

        skip(6.5 hours);

        _assertAuction(
            AuctionParams({
                borrower:          _borrower,
                active:            true,
                kicker:            _lender,
                bondSize:          0.215563505329166046 * 1e18,
                bondFactor:        0.011180339887498948 * 1e18,
                kickTime:          block.timestamp - 6.5 hours,
                referencePrice:    11.146834976502055842 * 1e18,
                totalBondEscrowed: 0.215563505329166046 * 1e18,
                auctionPrice:      9.373333573165302108 * 1e18,
                debtInAuction:     19.280586055366139163 * 1e18,
                debtToCollateral:  9.640293027683069581 * 1e18,
                neutralPrice:      11.146834976502055842 * 1e18
            })
        );

        // used to block last minute arbTakes that favor the taker
        _assertAddAboveAuctionPriceRevert({
            from:   _lender,
            amount: 1 * 1e18,
            index:  _i100_33
        });

    }

}
