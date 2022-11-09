// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.14;

import { ERC20HelperContract } from './ERC20DSTestPlus.sol';

import '../../erc20/ERC20Pool.sol';
import '../../erc20/ERC20PoolFactory.sol';

import '../../base/interfaces/IPool.sol';
import '../../base/interfaces/pool/IPoolErrors.sol';

import '../../libraries/BucketMath.sol';
import '../../libraries/Maths.sol';
import '../../libraries/PoolUtils.sol';

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
        assertEq(_hpb(), BucketMath.MIN_PRICE);

        // test 10_000 deposit at price of 3_010.892022197881557845
        _addLiquidity(
            {
                from:   _lender,
                amount: 10_000 * 1e18,
                index:  2550,
                newLup: BucketMath.MAX_PRICE
            }
        );
        _assertPool(
            PoolState({
                htp:                  0,
                lup:                  BucketMath.MAX_PRICE,
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
        _assertBucket(
            {
                index:        2550,
                lpBalance:    10_000 * 1e27,
                collateral:   0,
                deposit:      10_000 * 1e18,
                exchangeRate: 1 * 1e27
            }
        );
        _assertLenderLpBalance(
            {
                lender:      _lender,
                index:       2550,
                lpBalance:   10_000 * 1e27,
                depositTime: _startTime
            }
        );
        // check balances
        assertEq(_quote.balanceOf(address(_pool)), 10_000 * 1e18);
        assertEq(_quote.balanceOf(_lender),        190_000 * 1e18);

        // test 20_000 deposit at price of 2_995.912459898389633881
       _addLiquidity(
            {
                from:   _lender,
                amount: 20_000 * 1e18,
                index:  2551,
                newLup: BucketMath.MAX_PRICE
            }
        );
        _assertPool(
            PoolState({
                htp:                  0,
                lup:                  BucketMath.MAX_PRICE,
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

        _assertBucket(
            {
                index:        2550,
                lpBalance:    10_000 * 1e27,
                collateral:   0,
                deposit:      10_000 * 1e18,
                exchangeRate: 1 * 1e27
            }
        );
        _assertLenderLpBalance(
            {
                lender:      _lender,
                index:       2550,
                lpBalance:   10_000 * 1e27,
                depositTime: _startTime
            }
        );
        _assertBucket(
            {
                index:        2551,
                lpBalance:    20_000 * 1e27,
                collateral:   0,
                deposit:      20_000 * 1e18,
                exchangeRate: 1 * 1e27
            }
        );
        _assertLenderLpBalance(
            {
                lender:      _lender,
                index:       2551,
                lpBalance:   20_000 * 1e27,
                depositTime: _startTime
            }
        );

        // check balances
        assertEq(_quote.balanceOf(address(_pool)), 30_000 * 1e18);
        assertEq(_quote.balanceOf(_lender),        170_000 * 1e18);

        // test 40_000 deposit at price of 3_025.946482308870940904 DAI
       _addLiquidity(
            {
                from:   _lender,
                amount: 40_000 * 1e18,
                index:  2549,
                newLup: BucketMath.MAX_PRICE
            }
        );
        _assertPool(
            PoolState({
                htp:                  0,
                lup:                  BucketMath.MAX_PRICE,
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

        _assertBucket(
            {
                index:        2549,
                lpBalance:    40_000 * 1e27,
                collateral:   0,
                deposit:      40_000 * 1e18,
                exchangeRate: 1 * 1e27
            }
        );
        _assertLenderLpBalance(
            {
                lender:      _lender,
                index:       2549,
                lpBalance:   40_000 * 1e27,
                depositTime: _startTime
            }
        );
        _assertBucket(
            {
                index:        2550,
                lpBalance:    10_000 * 1e27,
                collateral:   0,
                deposit:      10_000 * 1e18,
                exchangeRate: 1 * 1e27
            }
        );
        _assertLenderLpBalance(
            {
                lender:      _lender,
                index:       2550,
                lpBalance:   10_000 * 1e27,
                depositTime: _startTime
            }
        );
        _assertBucket(
            {
                index:        2551,
                lpBalance:    20_000 * 1e27,
                collateral:   0,
                deposit:      20_000 * 1e18,
                exchangeRate: 1 * 1e27
            }
        );
        _assertLenderLpBalance(
            {
                lender:      _lender,
                index:       2551,
                lpBalance:   20_000 * 1e27,
                depositTime: _startTime
            }
        );

        // check balances
        assertEq(_quote.balanceOf(address(_pool)), 70_000 * 1e18);
        assertEq(_quote.balanceOf(_lender),        130_000 * 1e18);
    }

    function testPoolRemoveQuoteToken() external tearDown {
       _addLiquidity(
            {
                from:   _lender,
                amount: 40_000 * 1e18,
                index:  2549,
                newLup: BucketMath.MAX_PRICE
            }
        );
       _addLiquidity(
            {
                from:   _lender,
                amount: 10_000 * 1e18,
                index:  2550,
                newLup: BucketMath.MAX_PRICE
            }
        );
       _addLiquidity(
            {
                from:   _lender,
                amount: 20_000 * 1e18,
                index:  2551,
                newLup: BucketMath.MAX_PRICE
            }
        );
        _assertPool(
            PoolState({
                htp:                  0,
                lup:                  BucketMath.MAX_PRICE,
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

        _assertBucket(
            {
                index:        2549,
                lpBalance:    40_000 * 1e27,
                collateral:   0,
                deposit:      40_000 * 1e18,
                exchangeRate: 1 * 1e27
            }
        );
        _assertLenderLpBalance(
            {
                lender:      _lender,
                index:       2549,
                lpBalance:   40_000 * 1e27,
                depositTime: _startTime
            }
        );
        _assertBucket(
            {
                index:        2550,
                lpBalance:    10_000 * 1e27,
                collateral:   0,
                deposit:      10_000 * 1e18,
                exchangeRate: 1 * 1e27
            }
        );
        _assertLenderLpBalance(
            {
                lender:      _lender,
                index:       2550,
                lpBalance:   10_000 * 1e27,
                depositTime: _startTime
            }
        );
        _assertBucket(
            {
                index:        2551,
                lpBalance:    20_000 * 1e27,
                collateral:   0,
                deposit:      20_000 * 1e18,
                exchangeRate: 1 * 1e27
            }
        );
        _assertLenderLpBalance(
            {
                lender:      _lender,
                index:       2551,
                lpBalance:   20_000 * 1e27,
                depositTime: _startTime
            }
        );

        // check balances
        assertEq(_quote.balanceOf(address(_pool)), 70_000 * 1e18);
        assertEq(_quote.balanceOf(_lender),        130_000 * 1e18);

        _removeLiquidity(
            {
                from:     _lender,
                amount:   5_000 * 1e18,
                index:    2549,
                penalty:  0,
                newLup:   BucketMath.MAX_PRICE,
                lpRedeem: 5_000 * 1e27
            }
        );
        _assertPool(
            PoolState({
                htp:                  0,
                lup:                  BucketMath.MAX_PRICE,
                poolSize:             65_000 * 1e18,
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

        _assertBucket(
            {
                index:        2549,
                lpBalance:    35_000 * 1e27,
                collateral:   0,
                deposit:      35_000 * 1e18,
                exchangeRate: 1 * 1e27
            }
        );
        _assertLenderLpBalance(
            {
                lender:      _lender,
                index:       2549,
                lpBalance:   35_000 * 1e27,
                depositTime: _startTime
            }
        );
        _assertBucket(
            {
                index:        2550,
                lpBalance:    10_000 * 1e27,
                collateral:   0,
                deposit:      10_000 * 1e18,
                exchangeRate: 1 * 1e27
            }
        );
        _assertLenderLpBalance(
            {
                lender:      _lender,
                index:       2550,
                lpBalance:   10_000 * 1e27,
                depositTime: _startTime
            }
        );
        _assertBucket(
            {
                index:        2551,
                lpBalance:    20_000 * 1e27,
                collateral:   0,
                deposit:      20_000 * 1e18,
                exchangeRate: 1 * 1e27
            }
        );
        _assertLenderLpBalance(
            {
                lender:      _lender,
                index:       2551,
                lpBalance:   20_000 * 1e27,
                depositTime: _startTime
            }
        );

        // check balances
        assertEq(_quote.balanceOf(address(_pool)), 65_000 * 1e18);
        assertEq(_quote.balanceOf(_lender),        135_000 * 1e18);

        _removeLiquidity(
            {
                from:     _lender,
                amount:   35_000 * 1e18,
                index:    2549,
                penalty:  0,
                newLup:   BucketMath.MAX_PRICE,
                lpRedeem: 35_000 * 1e27
            }
        );
        _assertPool(
            PoolState({
                htp:                  0,
                lup:                  BucketMath.MAX_PRICE,
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

        _assertBucket(
            {
                index:        2549,
                lpBalance:    0,
                collateral:   0,
                deposit:      0,
                exchangeRate: 1 * 1e27
            }
        );
        _assertLenderLpBalance(
            {
                lender:      _lender,
                index:       2549,
                lpBalance:   0,
                depositTime: _startTime
            }
        );
        _assertBucket(
            {
                index:        2550,
                lpBalance:    10_000 * 1e27,
                collateral:   0,
                deposit:      10_000 * 1e18,
                exchangeRate: 1 * 1e27
            }
        );
        _assertLenderLpBalance(
            {
                lender:      _lender,
                index:       2550,
                lpBalance:   10_000 * 1e27,
                depositTime: _startTime
            }
        );
        _assertBucket(
            {
                index:        2551,
                lpBalance:    20_000 * 1e27,
                collateral:   0,
                deposit:      20_000 * 1e18,
                exchangeRate: 1 * 1e27
            }
        );
        _assertLenderLpBalance(
            {
                lender:      _lender,
                index:       2551,
                lpBalance:   20_000 * 1e27,
                depositTime: _startTime
            }
        );

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
        _addLiquidity(
            {
                from:   _lender,
                amount: 10_000 * 1e18,
                index:  4550,
                newLup: BucketMath.MAX_PRICE
            }
        );

        _pledgeCollateral(
            {
                from:     _borrower,
                borrower: _borrower,
                amount:   3_500_000 * 1e18
            }
        );
        _borrow(
            {
                from:       _borrower,
                amount:     10_000 * 1e18,
                indexLimit: 4_551,
                newLup:     0.140143083210662942 * 1e18
            }
        );

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
    function testPoolRemoveQuoteTokenRequireChecks() external tearDown {
        _mintCollateralAndApproveTokens(_borrower, _collateral.balanceOf(_borrower) + 3_500_000 * 1e18);
        _mintCollateralAndApproveTokens(_lender, 1 * 1e18);
        // lender adds initial quote token
        _addLiquidity(
            {
                from:   _lender,
                amount: 40_000 * 1e18,
                index:  4549,
                newLup: BucketMath.MAX_PRICE
            }
        );
        _addLiquidity(
            {
                from:   _lender,
                amount: 10_000 * 1e18,
                index:  4550,
                newLup: BucketMath.MAX_PRICE
            }
        );
        _addLiquidity(
            {
                from:   _lender,
                amount: 20_000 * 1e18,
                index:  4551,
                newLup: BucketMath.MAX_PRICE
            }
        );
        _addLiquidity(
            {
                from:   _lender,
                amount: 30_000 * 1e18,
                index:  4990,
                newLup: BucketMath.MAX_PRICE
            }
        );
        // add collateral in order to give lender LPs in bucket 5_000 with 0 deposit
        // used to test revert on remove when bucket deposit is 0
        _addCollateral(
            {
                from:   _lender,
                amount: 1 * 1e18,
                index:  5000
            }
        );
        _pledgeCollateral(
            {
                from:     _borrower,
                borrower: _borrower,
                amount:   3_500_000 * 1e18
            }
        );
        _borrow(
            {
                from:       _borrower,
                amount:     70_000 * 1e18,
                indexLimit: 4_551,
                newLup:     0.139445853940958153 * 1e18
            }
        );

        // ensure lender cannot withdraw from a bucket with no deposit
        _assertRemoveAllLiquidityNoClaimRevert(
            {
                from:  _lender1,
                index: 4550
            }
        );
        // should revert if no quote token in bucket deposit
        _assertRemoveInsufficientLiquidityRevert(
            {
                from:  _lender,
                amount: 1 * 1e18,
                index:  5000
            }
        );
        // should revert if removing quote token from higher price buckets would drive lup below htp
        _assertRemoveLiquidityLupBelowHtpRevert(
            {
                from:   _lender,
                amount: 20_000 * 1e18,
                index:  4551
            }
        );

        _addLiquidity(
            {
                from:   _lender1,
                amount: 20_000 * 1e18,
                index:  4550,
                newLup: 0.139445853940958153 * 1e18
            }
        );

        // should be able to removeQuoteToken
        _removeLiquidity(
            {
                from:     _lender,
                amount:   10_000 * 1e18,
                index:    4990,
                penalty:  0,
                newLup:   PoolUtils.indexToPrice(4551),
                lpRedeem: 10_000 * 1e27
            }
        );
    }

    function testPoolRemoveQuoteTokenWithCollateral() external {
        // add 10 collateral into the 100 bucket, for LP worth 1000 quote tokens
        _mintCollateralAndApproveTokens(_lender, 10 * 1e18);
        uint256 i100 = PoolUtils.priceToIndex(100 * 1e18);
        _addCollateral(
            {
                from:   _lender,
                amount: 10 * 1e18,
                index:  i100
            }
        );

        // someone else deposits into the bucket
        _addLiquidity(_lender1, 900 * 1e18, i100, BucketMath.MAX_PRICE);

        // should be able to remove a small amount of deposit
        skip(1 days);
        _removeLiquidity(
            {
                from:     _lender,
                amount:   100 * 1e18,
                index:    i100,
                penalty:  0,
                newLup:   BucketMath.MAX_PRICE,
                lpRedeem: 100 * 1e27
            }
        );

        // should be able to remove the rest
        _removeAllLiquidity(
            {
                from:     _lender,
                amount:   800 * 1e18,
                index:    i100,
                newLup:   BucketMath.MAX_PRICE,
                lpRedeem: 800 * 1e27
            }
        );

        _assertBucket(
            {
                index:        i100,
                lpBalance:    1_003.3236814328200989 * 1e27,
                collateral:   10 * 1e18,
                deposit:      0,
                exchangeRate: 1 * 1e27
            }
        );
    }

    function testPoolRemoveQuoteTokenWithDebt() external tearDown {
        _mintCollateralAndApproveTokens(_borrower, _collateral.balanceOf(_borrower) + 100 * 1e18);

        // lender adds initial quote token
        skip(1 minutes);  // prevent deposit from having a zero timestamp

        _addLiquidity(
            {
                from:   _lender,
                amount: 3_400 * 1e18,
                index:  1606,
                newLup: BucketMath.MAX_PRICE
            }
        );
        _addLiquidity(
            {
                from:   _lender,
                amount: 3_400 * 1e18,
                index:  1663,
                newLup: BucketMath.MAX_PRICE
            }
        );

        _assertBucket(
            {
                index:        1606,
                lpBalance:    3_400 * 1e27,
                collateral:   0,
                deposit:      3_400 * 1e18,
                exchangeRate: 1 * 1e27
            }
        );
        _assertLenderLpBalance(
            {
                lender:      _lender,
                index:       1606,
                lpBalance:   3_400 * 1e27,
                depositTime: _startTime + 1 minutes
            }
        );
        _assertBucket(
            {
                index:        1663,
                lpBalance:    3_400 * 1e27,
                collateral:   0,
                deposit:      3_400 * 1e18,
                exchangeRate: 1 * 1e27
            }
        );
        _assertLenderLpBalance(
            {
                lender:      _lender,
                index:       1663,
                lpBalance:   3_400 * 1e27,
                depositTime: _startTime + 1 minutes
            }
        );

        skip(59 minutes);

        uint256 lenderBalanceBefore = _quote.balanceOf(_lender);

        // borrower takes a loan of 3000 quote token
        _pledgeCollateral(
            {
                from:     _borrower,
                borrower: _borrower,
                amount:   100 * 1e18
            }
        );
        _borrow(
            {
                from:       _borrower,
                amount:     3_000 * 1e18,
                indexLimit: 2_000,
                newLup:     333_777.824045947762079231 * 1e18
            }
        );

        skip(2 hours);

        _assertLenderLpBalance(
            {
                lender:      _lender,
                index:       1663,
                lpBalance:   3_400 * 1e27,
                depositTime: _startTime + 1 minutes
            }
        );
        _assertLenderLpBalance(
            {
                lender:      _lender,
                index:       1663,
                lpBalance:   3_400 * 1e27,
                depositTime: _startTime + 1 minutes
            }
        );

        // lender makes a partial withdrawal, paying an early withdrawal penalty - current annualized interest rate divided by 52 (one week of interest)
        uint256 penalty = Maths.WAD - Maths.wdiv(_pool.interestRate(), 52 * 10**18);
        assertLt(penalty, Maths.WAD);
        uint256 expectedWithdrawal1 = Maths.wmul(1_700 * 1e18, penalty);
        _removeLiquidity(
            {
                from:     _lender,
                amount:   1_700 * 1e18,
                index:    1606,
                penalty:  penalty,
                newLup:   PoolUtils.indexToPrice(1663),
                lpRedeem: 1_699.992488670769259236317168938 * 1e27
            }
        );

        // lender removes all quote token, including interest, from the bucket
        skip(1 days);
        assertGt(PoolUtils.indexToPrice(1606), _htp());
        uint256 expectedWithdrawal2 = 1_700.136856335210791693 * 1e18;
        _removeAllLiquidity(
            {
                from:     _lender,
                amount:   expectedWithdrawal2,
                index:    1606,
                newLup:   PoolUtils.indexToPrice(1663),
                lpRedeem: 1_700.007511329230740763682831062 * 1e27
            }
        );
        assertEq(_quote.balanceOf(_lender), lenderBalanceBefore + expectedWithdrawal1 + expectedWithdrawal2);

        _assertBucket(
            {
                index:        1606,
                lpBalance:    0,
                collateral:   0,
                deposit:      0,
                exchangeRate: 1 * 1e27
            }
        );
        _assertLenderLpBalance(
            {
                lender:      _lender,
                index:       1606,
                lpBalance:   0,
                depositTime: _startTime + 1 minutes
            }
        );
        _assertBucket(
            {
                index:        1663,
                lpBalance:    3_400 * 1e27,
                collateral:   0,
                deposit:      3_400.258688868961711800 * 1e18,
                exchangeRate: 1.000076084961459327000000000 * 1e27
            }
        );
        _assertLenderLpBalance(
            {
                lender:      _lender,
                index:       1663,
                lpBalance:   3_400 * 1e27,
                depositTime: _startTime + 1 minutes
            }
        );
    }

    function testPoolMoveQuoteToken() external tearDown {
        _addLiquidity(
            {
                from:   _lender,
                amount: 40_000 * 1e18,
                index:  2549,
                newLup: BucketMath.MAX_PRICE
            }
        );
        _addLiquidity(
            {
                from:   _lender,
                amount: 10_000 * 1e18,
                index:  2550,
                newLup: BucketMath.MAX_PRICE
            }
        );
        _addLiquidity(
            {
                from:   _lender,
                amount: 20_000 * 1e18,
                index:  2551,
                newLup: BucketMath.MAX_PRICE
            }
        );

        _assertLenderLpBalance(
            {
                lender:      _lender,
                index:       2549,
                lpBalance:   40_000 * 1e27,
                depositTime: _startTime
            }
        );
        _assertLenderLpBalance(
            {
                lender:      _lender,
                index:       2552,
                lpBalance:   0,
                depositTime: 0
            }
        );

        _moveLiquidity(
            {
                from:         _lender,
                amount:       5_000 * 1e18,
                fromIndex:    2549,
                toIndex:      2552,
                newLup:       BucketMath.MAX_PRICE,
                lpRedeemFrom: 5_000 * 1e27,
                lpRedeemTo:   5_000 * 1e27
            }
        );

        _assertLenderLpBalance(
            {
                lender:      _lender,
                index:       2549,
                lpBalance:   35_000 * 1e27,
                depositTime: _startTime
            }
        );
        _assertLenderLpBalance(
            {
                lender:      _lender,
                index:       2552,
                lpBalance:   5_000 * 1e27,
                depositTime: _startTime
            }
        );

        _moveLiquidity(
            {
                from:         _lender,
                amount:       5_000 * 1e18,
                fromIndex:    2549,
                toIndex:      2540,
                newLup:       BucketMath.MAX_PRICE,
                lpRedeemFrom: 5_000 * 1e27,
                lpRedeemTo:   5_000 * 1e27
            }
        );

        _assertLenderLpBalance(
            {
                lender:      _lender,
                index:       2540,
                lpBalance:   5_000 * 1e27,
                depositTime: _startTime
            }
        );
        _assertLenderLpBalance(
            {
                lender:      _lender,
                index:       2549,
                lpBalance:   30_000 * 1e27,
                depositTime: _startTime
            }
        );
        _assertLenderLpBalance(
            {
                lender:      _lender,
                index:       2552,
                lpBalance:   5_000 * 1e27,
                depositTime: _startTime
            }
        );

        _moveLiquidity(
            {
                from:         _lender,
                amount:       15_000 * 1e18,
                fromIndex:    2551,
                toIndex:      2777,
                newLup:       BucketMath.MAX_PRICE,
                lpRedeemFrom: 15_000 * 1e27,
                lpRedeemTo:   15_000 * 1e27
            }
        );

        _assertLenderLpBalance(
            {
                lender:      _lender,
                index:       2540,
                lpBalance:   5_000 * 1e27,
                depositTime: _startTime
            }
        );
        _assertLenderLpBalance(
            {
                lender:      _lender,
                index:       2549,
                lpBalance:   30_000 * 1e27,
                depositTime: _startTime
            }
        );
        _assertLenderLpBalance(
            {
                lender:      _lender,
                index:       2551,
                lpBalance:   5_000 * 1e27,
                depositTime: _startTime
            }
        );
        _assertLenderLpBalance(
            {
                lender:      _lender,
                index:       2552,
                lpBalance:   5_000 * 1e27,
                depositTime: _startTime
            }
        );
        _assertLenderLpBalance(
            {
                lender:      _lender,
                index:       2777,
                lpBalance:   15_000 * 1e27,
                depositTime: _startTime
            }
        );
    }

    /**
     *  @notice 1 lender, 1 bidder, 1 borrower tests reverts in moveQuoteToken.
     *          Reverts:
     *              Attempts to move quote token to the same price.
     *              Attempts to move quote token from bucket with available collateral.
     *              Attempts to move quote token when doing so would drive lup below htp.
     */
    function testPoolMoveQuoteTokenRequireChecks() external tearDown {
        // test setup
        _mintCollateralAndApproveTokens(_lender1, _collateral.balanceOf(_lender1) + 100_000 * 1e18);
        _mintCollateralAndApproveTokens(_borrower, _collateral.balanceOf(_lender1) + 1_500_000 * 1e18);

        // lender adds initial quote token
        _addLiquidity(
            {
                from:   _lender,
                amount: 40_000 * 1e18,
                index:  4549,
                newLup: BucketMath.MAX_PRICE
            }
        );
        _addLiquidity(
            {
                from:   _lender,
                amount: 10_000 * 1e18,
                index:  4550,
                newLup: BucketMath.MAX_PRICE
            }
        );
        _addLiquidity(
            {
                from:   _lender,
                amount: 20_000 * 1e18,
                index:  4551,
                newLup: BucketMath.MAX_PRICE
            }
        );
        _addLiquidity(
            {
                from:   _lender,
                amount: 30_000 * 1e18,
                index:  4651,
                newLup: BucketMath.MAX_PRICE
            }
        );

        // should revert if moving quote token to the existing price
        _assertMoveLiquidityToSamePriceRevert(
            {
                from:      _lender,
                amount:    5_000 * 1e18,
                fromIndex: 4549,
                toIndex:   4549
            }
        );

        // borrow all available quote in the higher priced original 3 buckets, as well as some of the new lowest price bucket
        _pledgeCollateral(
            {
                from:     _borrower,
                borrower: _borrower,
                amount:   1_500_000 * 1e18
            }
        );
        _borrow(
            {
                from:       _borrower,
                amount:     60_000.1 * 1e18,
                indexLimit: 4_651,
                newLup:     0.139445853940958153 * 1e18
            }
        );

        // should revert if movement would drive lup below htp
        _assertMoveLiquidityLupBelowHtpRevert(
            {
                from:      _lender,
                amount:    40_000 * 1e18,
                fromIndex: 4549,
                toIndex:   6000
            }
        );

        // should be able to moveQuoteToken if properly specified
        _moveLiquidity(
            {
                from:         _lender,
                amount:       10_000 * 1e18,
                fromIndex:    4549,
                toIndex:      4550,
                newLup:       PoolUtils.indexToPrice(4551),
                lpRedeemFrom: 10_000 * 1e27,
                lpRedeemTo:   10_000 * 1e27
            }
        );
    }

    function testMoveQuoteTokenWithDebt() external tearDown {
        // lender makes an initial deposit
        skip(1 hours);

        _addLiquidity(
            {
                from:   _lender,
                amount: 10_000 * 1e18,
                index:  2873,
                newLup: BucketMath.MAX_PRICE
            }
        );

        // borrower draws debt, establishing a pool threshold price
        skip(2 hours);
        _pledgeCollateral(
            {
                from:     _borrower,
                borrower: _borrower,
                amount:   10 * 1e18
            }
        );
        _borrow(
            {
                from:       _borrower,
                amount:     5_000 * 1e18,
                indexLimit: 3_000,
                newLup:     601.252968524772188572 * 1e18
            }
        );

        (uint256 poolDebt,,) = _pool.debtInfo();
        uint256 ptp = Maths.wdiv(poolDebt, 10 * 1e18);
        assertEq(ptp, 500.480769230769231000 * 1e18);

        // lender moves some liquidity below the pool threshold price; penalty should be assessed
        skip(16 hours);
        _moveLiquidity(
            {
                from:         _lender,
                amount:       2_500 * 1e18,
                fromIndex:    2873,
                toIndex:      2954,
                newLup:       _lup(),
                lpRedeemFrom: 2_499.899333909953254268257527496 * 1e27,
                lpRedeemTo:   2_497.596153846153845 * 1e27
            }
        );

        // another lender provides liquidity to prevent LUP from moving
        skip(1 hours);

        _addLiquidity(
            {
                from:   _lender1,
                amount: 1_000 * 1e18,
                index:  2873,
                newLup: 601.252968524772188572 * 1e18
            }
        );

        // lender moves more liquidity; no penalty assessed as sufficient time has passed
        skip(12 hours);
        _moveLiquidity(
            {
                from:         _lender,
                amount:       2_500 * 1e18,
                fromIndex:    2873,
                toIndex:      2954,
                newLup:       _lup(),
                lpRedeemFrom: 2_499.810182702901761331141452320 * 1e27,
                lpRedeemTo:   2_500 * 1e27
            }
        );

        // after a week, another lender funds the pool
        skip(7 days);

        _addLiquidity(
            {
                from:   _lender1,
                amount: 9_000 * 1e18,
                index:  2873,
                newLup: 601.252968524772188572 * 1e18
            }
        );

        // lender removes all their quote, with interest
        skip(1 hours);
        _removeAllLiquidity(
            {
                from:     _lender,
                amount:   5_003.981613396490344248 * 1e18,
                index:    2873,
                newLup:   601.252968524772188572 * 1e18,
                lpRedeem: 5_000.290483387144984400601020184 * 1e27
            }
        );
        _removeAllLiquidity(
            {
                from:     _lender,
                amount:   4_997.596153846153845 * 1e18,
                index:    2954,
                newLup:   601.252968524772188572 * 1e18,
                lpRedeem: 4_997.596153846153845 * 1e27
            }
        );
        assertGt(_quote.balanceOf(_lender), 200_000 * 1e18);
    }
}
