// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.14;

import { ERC20HelperContract } from './ERC20DSTestPlus.sol';
import { Token }               from '../utils/Tokens.sol';

import '../../base/PoolInfoUtils.sol';

import '../../erc20/ERC20Pool.sol';
import '../../erc20/ERC20PoolFactory.sol';

import '../../libraries/BucketMath.sol';

contract ERC20PoolInterestRateTestAndEMAs is ERC20HelperContract {
    address internal _borrower;
    address internal _borrower2;
    address internal _lender;
    address internal _lender1;

    function setUp() external {
        _borrower  = makeAddr("borrower");
        _borrower2 = makeAddr("borrower2");
        _lender    = makeAddr("lender");
        _lender1   = makeAddr("_lender1");

        _mintCollateralAndApproveTokens(_borrower,  10_000 * 1e18);
        _mintCollateralAndApproveTokens(_borrower2, 200 * 1e18);

        _mintQuoteAndApproveTokens(_lender,   200_000 * 1e18);
        _mintQuoteAndApproveTokens(_lender1,  200_000 * 1e18);
    }

    function testPoolInterestRateIncreaseDecrease() external tearDown {
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
        _addLiquidity(
            {
                from:   _lender,
                amount: 20_000 * 1e18,
                index:  2552,
                newLup: BucketMath.MAX_PRICE
            }
        );
        _addLiquidity(
            {
                from:   _lender,
                amount: 50_000 * 1e18,
                index:  3900,
                newLup: BucketMath.MAX_PRICE
            }
        );
        _addLiquidity(
            {
                from:   _lender,
                amount: 10_000 * 1e18,
                index:  4200,
                newLup: BucketMath.MAX_PRICE
            }
        );

        skip(10 days);

        _assertPool(
            PoolState({
                htp:                  0,
                lup:                  BucketMath.MAX_PRICE,
                poolSize:             110_000 * 1e18,
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
        // enforce EMA and target utilization update
        _pledgeCollateral(
            {
                from:     _borrower,
                borrower: _borrower,
                amount:   100 * 1e18
            }
        );
        vm.expectEmit(true, true, false, true);
        emit UpdateInterestRate(0.05 * 1e18, 0.055 * 1e18);
        _borrow(
            {
                from:       _borrower,
                amount:     46_000 * 1e18,
                indexLimit: 4_300,
                newLup:     2_981.007422784467321543 * 1e18
            }
        );

        _assertPool(
            PoolState({
                htp:                  460.442307692307692520 * 1e18,
                lup:                  2_981.007422784467321543 * 1e18,
                poolSize:             110_000 * 1e18,
                pledgedCollateral:    100 * 1e18,
                encumberedCollateral: 15.445862501819022598 * 1e18,
                poolDebt:             46_044.230769230769252000 * 1e18,
                actualUtilization:    0.920884615384615385 * 1e18,
                targetUtilization:    0.000000505854275034 * 1e18,
                minDebtAmount:        4_604.423076923076925200 * 1e18,
                loans:                1,
                maxBorrower:          _borrower,
                interestRate:         0.055 * 1e18,
                interestRateUpdate:   _startTime + 10 days
            })
        );

        // repay entire loan
        deal(address(_quote), _borrower,  _quote.balanceOf(_borrower) + 200 * 1e18);
        _repay(
            {
                from:     _borrower,
                borrower: _borrower,
                amount:   46_044.230769230769252000 * 1e18,
                repaid:   46_044.230769230769252000 * 1e18,
                newLup:   BucketMath.MAX_PRICE
            }
        );
    }

    function testPoolInterestRateDecrease() external tearDown {
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
        // borrower draws debt
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
                indexLimit: 3000,
                newLup:     601.252968524772188572 * 1e18
            }
        );

        _assertPool(
            PoolState({
                htp:                  500.480769230769231000 * 1e18,
                lup:                  601.252968524772188572 * 1e18,
                poolSize:             10_000 * 1e18,
                pledgedCollateral:    10 * 1e18,
                encumberedCollateral: 8.323963380317995918 * 1e18,
                poolDebt:             5_004.807692307692310000 * 1e18,
                actualUtilization:    0.500480769230769231 * 1e18,
                targetUtilization:    1e18,
                minDebtAmount:        500.480769230769231000 * 1e18,
                loans:                1,
                maxBorrower:          _borrower,
                interestRate:         0.05 * 1e18,
                interestRateUpdate:   _startTime
            })
        );

        // another lender provides liquidity, decresing interest rate from 0.05 to 0.045
        skip(12 hours);

        vm.expectEmit(true, true, false, true);
        emit UpdateInterestRate(0.05 * 1e18, 0.045 * 1e18);
        _addLiquidity(
            {
                from:   _lender1,
                amount: 1_000 * 1e18,
                index:  2873,
                newLup: 601.252968524772188572 * 1e18
            }
        );

        _assertPool(
            PoolState({
                htp:                  500.549332936289892272 * 1e18,
                lup:                  601.252968524772188572 * 1e18,
                poolSize:             11_000.302006983390040000 * 1e18,
                pledgedCollateral:    10 * 1e18,
                encumberedCollateral: 8.324533534321699024 * 1e18,
                poolDebt:             5_005.150499094935086587 * 1e18,
                actualUtilization:    0.455001189596202387 * 1e18,
                targetUtilization:    0.832453353432169902 * 1e18,
                minDebtAmount:        500.515049909493508659 * 1e18,
                loans:                1,
                maxBorrower:          _borrower,
                interestRate:         0.045 * 1e18,
                interestRateUpdate:   _startTime + 15 hours
            })
        );
    }

    function testPendingInflator() external tearDown {
        // add liquidity
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
                amount: 10_000 * 1e18,
                index:  2552,
                newLup: BucketMath.MAX_PRICE
            }
        );
        _addLiquidity(
            {
                from:   _lender,
                amount: 10_000 * 1e18,
                index:  4200,
                newLup: BucketMath.MAX_PRICE
            }
        );

        skip(3600);

        // draw debt
        _pledgeCollateral(
            {
                from:     _borrower,
                borrower: _borrower,
                amount:   50 * 1e18
            }
        );
        _borrow(
            {
                from:       _borrower,
                amount:     15_000 * 1e18,
                indexLimit: 4_300,
                newLup:     2_981.007422784467321543 * 1e18
            }
        );

        _assertPool(
            PoolState({
                htp:                  300.288461538461538600 * 1e18,
                lup:                  2_981.007422784467321543 * 1e18,
                poolSize:             30_000 * 1e18,
                pledgedCollateral:    50 * 1e18,
                encumberedCollateral: 5.036694294071420412 * 1e18,
                poolDebt:             15_014.423076923076930000 * 1e18,
                actualUtilization:    0.750721153846153847 * 1e18,
                targetUtilization:    1e18,
                minDebtAmount:        1_501.442307692307693000 * 1e18,
                loans:                1,
                maxBorrower:          _borrower,
                interestRate:         0.05 * 1e18,
                interestRateUpdate:   _startTime
            })
        );

        vm.warp(block.timestamp + 3600);

        // ensure pendingInflator increases as time passes
        _assertPool(
            PoolState({
                htp:                  300.288461538461538600 * 1e18,
                lup:                  2_981.007422784467321543 * 1e18,
                poolSize:             30_000 * 1e18,
                pledgedCollateral:    50 * 1e18,
                encumberedCollateral: 5.036723042408567816 * 1e18,
                poolDebt:             15_014.508775929506051308 * 1e18,
                actualUtilization:    0.750725438796475303 * 1e18,
                targetUtilization:    1e18,
                minDebtAmount:        1_501.450877592950605131 * 1e18,
                loans:                1,
                maxBorrower:          _borrower,
                interestRate:         0.05 * 1e18,
                interestRateUpdate:   _startTime
            })
        );
    }

    function testPoolEMAAndTargetUtilizationUpdate() external tearDown {

        // add initial quote to the pool
        _addLiquidity(
            {
                from:   _lender,
                amount: 10_000 * 1e18,
                index:  3_010,
                newLup: BucketMath.MAX_PRICE
            }
        );
        _addLiquidity(
            {
                from:   _lender,
                amount: 10_000 * 1e18,
                index:  2_995,
                newLup: BucketMath.MAX_PRICE
            }
        );

        _assertPool(
            PoolState({
                htp:                  0,
                lup:                  BucketMath.MAX_PRICE,
                poolSize:             20_000 * 1e18,
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
        _assertEMAs(
            {
                debtEma:   0,
                lupColEma: 0
            }
        );

        // borrower 1 borrows 500 quote from the pool
        _pledgeCollateral(
            {
                from:     _borrower,
                borrower: _borrower,
                amount:   50 * 1e18
            }
        );
        _borrow(
            {
                from:       _borrower,
                amount:     500 * 1e18,
                indexLimit: 3_010,
                newLup:     327.188250324085203338 * 1e18
            }
        );

        _assertPool(
            PoolState({
                htp:                  10.009615384615384620 * 1e18,
                lup:                  327.188250324085203338 * 1e18,
                poolSize:             20_000 * 1e18,
                pledgedCollateral:    50 * 1e18,
                encumberedCollateral: 1.529641632103338099 * 1e18,
                poolDebt:             500.480769230769231000 * 1e18,
                actualUtilization:    0.025024038461538462 * 1e18,
                targetUtilization:    1e18,
                minDebtAmount:        50.048076923076923100 * 1e18,
                loans:                1,
                maxBorrower:          address(_borrower),
                interestRate:         0.05 * 1e18,
                interestRateUpdate:   _startTime
            })
        );
        _assertEMAs(
            {
                debtEma:   0,
                lupColEma: 0
            }
        );

        _pledgeCollateral(
            {
                from:     _borrower2,
                borrower: _borrower2,
                amount:   50 * 1e18
            }
        );
        _borrow(
            {
                from:       _borrower2,
                amount:     500 * 1e18,
                indexLimit: 3_010,
                newLup:     327.188250324085203338 * 1e18
            }
        );

        _assertPool(
            PoolState({
                htp:                  10.009615384615384620 * 1e18,
                lup:                  327.188250324085203338 * 1e18,
                poolSize:             20_000 * 1e18,
                pledgedCollateral:    100 * 1e18,
                encumberedCollateral: 3.059283264206676197 * 1e18,
                poolDebt:             1000.961538461538462000 * 1e18,
                actualUtilization:    0.050048076923076923 * 1e18,
                targetUtilization:    1e18,
                minDebtAmount:        50.048076923076923100 * 1e18,
                loans:                2,
                maxBorrower:          address(_borrower),
                interestRate:         0.05 * 1e18,
                interestRateUpdate:   _startTime
            })
        );
        _assertEMAs(
            {
                debtEma:   0,
                lupColEma: 0
            }
        );

        skip(10 days);

        // borrower 1 borrows 500 quote from the pool
        _borrow(
            {
                from:       _borrower,
                amount:     10 * 1e18,
                indexLimit: 3_010,
                newLup:     327.188250324085203338 * 1e18
            }
        );

        _assertPool(
            PoolState({
                htp:                  10.237543320969223878 * 1e18,
                lup:                  327.188250324085203338 * 1e18,
                poolSize:             20_001.169794343035540000 * 1e18,
                pledgedCollateral:    100 * 1e18,
                encumberedCollateral: 3.094069767562214045 * 1e18,
                poolDebt:             1012.343273629329809307 * 1e18,
                actualUtilization:    0.050614203271033305 * 1e18,
                targetUtilization:    0.030940697675622140 * 1e18,
                minDebtAmount:        50.617163681466490465 * 1e18,
                loans:                2,
                maxBorrower:          address(_borrower),
                interestRate:         0.05 * 1e18,
                interestRateUpdate:   _startTime
            })
        );
        _assertEMAs(
            {
                debtEma:   95.440014344854493304 * 1e18,
                lupColEma: 3_084.610933645840358918 * 1e18
            }
        );
    }
}
