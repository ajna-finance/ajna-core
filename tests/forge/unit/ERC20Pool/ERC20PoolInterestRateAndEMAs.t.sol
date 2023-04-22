// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.14;

import { ERC20HelperContract } from './ERC20DSTestPlus.sol';

import 'src/libraries/helpers/PoolHelper.sol';
import 'src/interfaces/pool/erc20/IERC20Pool.sol';

contract ERC20PoolInterestRateTestAndEMAs is ERC20HelperContract {

    address internal _borrower;
    address internal _borrower2;
    address internal _borrower3;
    address internal _lender;
    address internal _lender1;
    address internal _lender2;

    function setUp() external {
        _borrower  = makeAddr("borrower");
        _borrower2 = makeAddr("borrower2");
        _borrower3 = makeAddr("borrower3");
        _lender    = makeAddr("lender");
        _lender1   = makeAddr("_lender1");
        _lender2   = makeAddr("_lender2");

        _mintCollateralAndApproveTokens(_borrower,  10_000 * 1e18);
        _mintCollateralAndApproveTokens(_borrower2, 200 * 1e18);
        _mintCollateralAndApproveTokens(_borrower3, 1_000_000_000 * 1e18);

        _mintQuoteAndApproveTokens(_lender,   200_000 * 1e18);
        _mintQuoteAndApproveTokens(_lender1,  200_000 * 1e18);
        _mintQuoteAndApproveTokens(_lender2,  100_000_000_000_000_000 * 1e18);
    }

    function testPoolInterestRateIncreaseDecrease() external tearDown {
        _addInitialLiquidity({
            from:   _lender,
            amount: 10_000 * 1e18,
            index:  2550
        });
        _addInitialLiquidity({
            from:   _lender,
            amount: 20_000 * 1e18,
            index:  2551
        });
        _addInitialLiquidity({
            from:   _lender,
            amount: 20_000 * 1e18,
            index:  2552
        });
        _addInitialLiquidity({
            from:   _lender,
            amount: 50_000 * 1e18,
            index:  3900
        });
        _addInitialLiquidity({
            from:   _lender,
            amount: 10_000 * 1e18,
            index:  4200
        });

        skip(10 days);

        _assertPool(
            PoolParams({
                htp:                  0,
                lup:                  MAX_PRICE,
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
        changePrank(_borrower);

        vm.expectEmit(true, true, false, true);
        emit UpdateInterestRate(0.05 * 1e18, 0.045 * 1e18);
        _drawDebtNoLupCheck({
            from:               _borrower,
            borrower:           _borrower,
            amountToBorrow:     46_000 * 1e18,
            limitIndex:         4_300,
            collateralToPledge: 100.0 * 1e18
        });

        _assertPool(
            PoolParams({
                htp:                  460.442307692307692520 * 1e18,
                lup:                  2_981.007422784467321543 * 1e18,
                poolSize:             110_000 * 1e18,
                pledgedCollateral:    100 * 1e18,
                encumberedCollateral: 15.464917089564537419 * 1e18,
                poolDebt:             46_101.032636738246882092 * 1e18,
                actualUtilization:    0.000000000000000000 * 1e18,
                targetUtilization:    1.000000000000000000 * 1e18,
                minDebtAmount:        4_610.103263673824688209 * 1e18,
                loans:                1,
                maxBorrower:          _borrower,
                interestRate:         0.045 * 1e18,
                interestRateUpdate:   _startTime + 10 days
            })
        );
        _assertEMAs({
            debtColEma:   0,
            lupt0DebtEma: 0,
            debtEma:      0,
            depositEma:   109_999.904632568359400000 * 1e18
        });

        skip(14 hours);

        uint256 snapshot = vm.snapshot();
        // update interest rate
        _updateInterest();

        _assertPool(
            PoolParams({
                htp:                  461.043482411861952490 * 1e18,
                lup:                  2_981.007422784467321543 * 1e18,
                poolSize:             110_051.099851162112050000 * 1e18,
                pledgedCollateral:    100 * 1e18,
                encumberedCollateral: 15.466029332500467905 * 1e18,
                poolDebt:             46_104.348241186195248997 * 1e18,
                actualUtilization:    0.332788778646025592 * 1e18,
                targetUtilization:    0.154458625018190226 * 1e18,
                minDebtAmount:        4_610.434824118619524900 * 1e18,
                loans:                1,
                maxBorrower:          _borrower,
                interestRate:         0.045 * 1e18,
                interestRateUpdate:   _startTime + 10 days
            })
        );
        _assertEMAs({
            debtColEma:   2_313_024.841496349382919830 * 1e18,
            lupt0DebtEma: 14_975_044.878354639842735067 * 1e18,
            debtEma:      25_533.857684197937318785 * 1e18,
            depositEma:   76_726.919062848880206510 * 1e18
        });

        vm.revertTo(snapshot);
        // repay entire loan

        deal(address(_quote), _borrower,  _quote.balanceOf(_borrower) + 200 * 1e18);

        _repayDebt({
            from:             _borrower,
            borrower:         _borrower,
            amountToRepay:    46_200 * 1e18,
            amountRepaid:     46_104.348241186195248997 * 1e18,
            collateralToPull: 0,
            newLup:           MAX_PRICE
        });

        _assertPool(
            PoolParams({
                htp:                  0,
                lup:                  MAX_PRICE,
                poolSize:             110_051.099851162112050000 * 1e18,
                pledgedCollateral:    100 * 1e18,
                encumberedCollateral: 0,
                poolDebt:             0,
                actualUtilization:    0.332788778646025592 * 1e18,
                targetUtilization:    0.154458625018190226 * 1e18,
                minDebtAmount:        0,
                loans:                0,
                maxBorrower:          address(0),
                interestRate:         0.0405 * 1e18,
                interestRateUpdate:   _startTime + 10 days + 14 hours
            })
        );

        _assertEMAs({
            debtColEma:   2_313_024.841496349382919830 * 1e18,
            lupt0DebtEma: 14_975_044.878354639842735067 * 1e18,
            debtEma:      25_533.857684197937318785 * 1e18,
            depositEma:   76_726.919062848880206510 * 1e18
        });
    }

    function testOverutilizedPoolInterestRateIncrease() external tearDown {
        // lender deposits 1000
        _addInitialLiquidity({
            from:   _lender,
            amount: 1_000 * 1e18,
            index:  3232
        });

        // borrower draws 9100
        _pledgeCollateral({
            from:     _borrower,
            borrower: _borrower,
            amount:    1_500 * 1e18
        });
        _borrow({
            from:       _borrower,
            amount:     995 * 1e18,
            indexLimit: 3300,
            newLup:     100.332368143282009890 * 1e18
        });

        _assertPool(
            PoolParams({
                htp:                  0.663971153846153846 * 1e18,
                lup:                  100.332368143282009890 * 1e18,
                poolSize:             1_000 * 1e18,
                pledgedCollateral:    1_500 * 1e18,
                encumberedCollateral: 9.926574536214785829 * 1e18,
                poolDebt:             995.956730769230769690 * 1e18,
                actualUtilization:    0,
                targetUtilization:    1 * 1e18,
                minDebtAmount:        99.595673076923076969 * 1e18,
                loans:                1,
                maxBorrower:          _borrower,
                interestRate:         0.05 * 1e18,
                interestRateUpdate:   _startTime
            })
        );

        skip(13 hours);

        // update interest rate
        _updateInterest();

        _assertPool(
            PoolParams({
                htp:                  0.664020422940018855 * 1e18,
                lup:                  100.332368143282009890 * 1e18,
                poolSize:             1_000.062818094677886000 * 1e18,
                pledgedCollateral:    1_500 * 1e18,
                encumberedCollateral: 9.927311124438159308 * 1e18,
                poolDebt:             996.030634410028283604 * 1e18,
                actualUtilization:    0.525927743411473669 * 1e18,
                targetUtilization:    0.006617716357476524 * 1e18,
                minDebtAmount:        99.603063441002828360 * 1e18,
                loans:                1,
                maxBorrower:          _borrower,
                interestRate:         0.055 * 1e18,
                interestRateUpdate:   _startTime + 13 hours
            })
        );
    }

    function testPoolInterestRateDecrease() external tearDown {
        // lender makes an initial deposit
        skip(1 hours);

        _addInitialLiquidity({
            from:   _lender,
            amount: 10_000 * 1e18,
            index:  2873
        });

        // borrower draws debt
        skip(2 hours);
        _pledgeCollateral({
            from:     _borrower,
            borrower: _borrower,
            amount:   10 * 1e18
        });
        _borrow({
            from:       _borrower,
            amount:     5_000 * 1e18,
            indexLimit: 3000,
            newLup:     601.252968524772188572 * 1e18
        });

        _assertPool(
            PoolParams({
                htp:                  500.480769230769231000 * 1e18,
                lup:                  601.252968524772188572 * 1e18,
                poolSize:             10_000 * 1e18,
                pledgedCollateral:    10 * 1e18,
                encumberedCollateral: 8.323963380317995918 * 1e18,
                poolDebt:             5_004.807692307692310000 * 1e18,
                actualUtilization:    0,
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
        _addLiquidityNoEventCheck({
            from:    _lender1,
            amount:  1_000 * 1e18,
            index:   2873
        });

        _assertPool(
            PoolParams({
                htp:                  500.515049909493508659 * 1e18,
                lup:                  601.252968524772188572 * 1e18,
                poolSize:             11_000.291385769156360000 * 1e18,
                pledgedCollateral:    10 * 1e18,
                encumberedCollateral: 8.324533534321699024 * 1e18,
                poolDebt:             5_005.150499094935086587 * 1e18,
                actualUtilization:    0.250240384615384603 * 1e18,
                targetUtilization:    0.832396338031799592 * 1e18,
                minDebtAmount:        500.515049909493508659 * 1e18,
                loans:                1,
                maxBorrower:          _borrower,
                interestRate:         0.045 * 1e18,
                interestRateUpdate:   _startTime + 15 hours
            })
        );
    }

    function testMinInterestRate() external tearDown {
        _addInitialLiquidity({
            from:   _lender,
            amount: 10_000 * 1e18,
            index:  _i1505_26
        });

        // pledge a tiny amount of collateral and draw a tiny amount of debt
        _drawDebt({
            from:               _borrower,
            borrower:           _borrower,
            amountToBorrow:     0.00001 * 1e18,
            limitIndex:         _i1505_26,
            collateralToPledge: 0.00001 * 1e18,
            newLup:             _p1505_26
        });

        // confirm interest rate starts out at 5%
        _assertPool(
            PoolParams({
                htp:                  1.0009615384615 * 1e18,
                lup:                  _p1505_26,
                poolSize:             10_000 * 1e18,
                pledgedCollateral:    0.00001 * 1e18,
                encumberedCollateral: 0.000000006649741966 * 1e18,
                poolDebt:             0.000010009615384615 * 1e18,
                actualUtilization:    0,
                targetUtilization:    1e18,
                minDebtAmount:        0.000001000961538462 * 1e18,
                loans:                1,
                maxBorrower:          _borrower,
                interestRate:         0.05 * 1e18,
                interestRateUpdate:   _startTime
            })
        );

        uint i = 0;
        while (i < 77) {
            // trigger an interest accumulation
            skip(12 hours);

            _updateInterest();
            
            unchecked { ++i; }
        }

        // show the rate bottoms out at 10 bps
        _assertPool(
            PoolParams({
                htp:                  1.002309975983935259 * 1e18,
                lup:                  _p1505_26,
                poolSize:             10_000.000000011461360000 * 1e18,
                pledgedCollateral:    0.00001 * 1e18,
                encumberedCollateral: 0.000000006658700114 * 1e18,
                poolDebt:             0.000010023099759839 * 1e18,
                actualUtilization:    0.000000001002307157 * 1e18,
                targetUtilization:    0.000665852030273875 * 1e18,
                minDebtAmount:        0.000001002309975984 * 1e18,
                loans:                1,
                maxBorrower:          _borrower,
                interestRate:         0.001 * 1e18,
                interestRateUpdate:   _startTime + (76*12 hours)
            })
        );
    }

    function testMaxInterestRate() external tearDown {
        _addInitialLiquidity({
            from:   _lender,
            amount: 10_000 * 1e18,
            index:  _i1505_26
        });

        // pledge a lot of collateral, but draw a tiny amount of debt
        _drawDebt({
            from:               _borrower,
            borrower:           _borrower,
            amountToBorrow:     0.00001 * 1e18,
            limitIndex:         _i1505_26,
            collateralToPledge: 10_000 * 1e18,
            newLup:             _p1505_26
        });

        // confirm interest rate starts out at 5%
        _assertPool(
            PoolParams({
                htp:                  0.000000001000961538 * 1e18,
                lup:                  _p1505_26,
                poolSize:             10_000 * 1e18,
                pledgedCollateral:    10_000 * 1e18,
                encumberedCollateral: 0.000000006649741966 * 1e18,
                poolDebt:             0.000010009615384615 * 1e18,
                actualUtilization:    0,
                targetUtilization:    1e18,
                minDebtAmount:        0.000001000961538462 * 1e18,
                loans:                1,
                maxBorrower:          _borrower,
                interestRate:         0.05 * 1e18,
                interestRateUpdate:   _startTime
            })
        );

        uint i = 0;
        while (i < 194) {
            // trigger an interest accumulation
            skip(12 hours);

            _updateInterest();

            unchecked { ++i; }
        }

        // show the rate reset to 10%
        _assertPool(
            PoolParams({
                htp:                  1028117286,
                lup:                  _p1505_26,
                poolSize:             10_000.000000230822950000 * 1e18,
                pledgedCollateral:    10_000.0 * 1e18,
                encumberedCollateral: 0.000000006830147214 * 1e18,
                poolDebt:             0.000010281172862060 * 1e18,
                actualUtilization:    0.000000001027819578 * 1e18,
                targetUtilization:    0.000000000000681949 * 1e18,
                minDebtAmount:        0.000001028117286206 * 1e18,
                loans:                1,
                maxBorrower:          _borrower,
                interestRate:         0.1 * 1e18, // rate reset to 10%
                interestRateUpdate:   _startTime + (194 * 12 hours)
            })
        );
    }

    function testPendingInflator() external tearDown {
        // add liquidity
        _addInitialLiquidity({
            from:   _lender,
            amount: 10_000 * 1e18,
            index:  2550
        });
        _addInitialLiquidity({
            from:   _lender,
            amount: 10_000 * 1e18,
            index:  2552
        });
        _addInitialLiquidity({
            from:   _lender,
            amount: 10_000 * 1e18,
            index:  4200
        });

        skip(3600);

        // draw debt
        _pledgeCollateral({
            from:     _borrower,
            borrower: _borrower,
            amount:   50 * 1e18
        });
        _borrow({
            from:       _borrower,
            amount:     15_000 * 1e18,
            indexLimit: 4_300,
            newLup:     2_981.007422784467321543 * 1e18
        });

        _assertPool(
            PoolParams({
                htp:                  300.288461538461538600 * 1e18,
                lup:                  2_981.007422784467321543 * 1e18,
                poolSize:             30_000 * 1e18,
                pledgedCollateral:    50 * 1e18,
                encumberedCollateral: 5.036694294071420412 * 1e18,
                poolDebt:             15_014.423076923076930000 * 1e18,
                actualUtilization:    0,
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
            PoolParams({
                htp:                  300.288461538461538600 * 1e18,
                lup:                  2_981.007422784467321543 * 1e18,
                poolSize:             30_000 * 1e18,
                pledgedCollateral:    50 * 1e18,
                encumberedCollateral: 5.036723042408567816 * 1e18,
                poolDebt:             15_014.508775929506051308 * 1e18,
                actualUtilization:    0,
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
        _addInitialLiquidity({
            from:   _lender,
            amount: 10_000 * 1e18,
            index:  3_010
        });
        _addInitialLiquidity({
            from:   _lender,
            amount: 10_000 * 1e18,
            index:  2_995
        });

        _assertPool(
            PoolParams({
                htp:                  0,
                lup:                  MAX_PRICE,
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
        _assertEMAs({
            debtColEma:   0,
            lupt0DebtEma: 0,
            debtEma:      0,
            depositEma:   10_000 * 1e18
        });

        // borrower 1 borrows 500 quote from the pool
        _pledgeCollateral({
            from:     _borrower,
            borrower: _borrower,
            amount:   50 * 1e18
        });
        _borrow({
            from:       _borrower,
            amount:     500 * 1e18,
            indexLimit: 3_010,
            newLup:     327.188250324085203338 * 1e18
        });

        _assertPool(
            PoolParams({
                htp:                  10.009615384615384620 * 1e18,
                lup:                  327.188250324085203338 * 1e18,
                poolSize:             20_000 * 1e18,
                pledgedCollateral:    50 * 1e18,
                encumberedCollateral: 1.529641632103338099 * 1e18,
                poolDebt:             500.480769230769231000 * 1e18,
                actualUtilization:    0,
                targetUtilization:    1e18,
                minDebtAmount:        50.048076923076923100 * 1e18,
                loans:                1,
                maxBorrower:          address(_borrower),
                interestRate:         0.05 * 1e18,
                interestRateUpdate:   _startTime
            })
        );
        _assertEMAs({
            debtColEma:   0,
            lupt0DebtEma: 0,
            debtEma:      0,
            depositEma:   10_000 * 1e18
        });

        _pledgeCollateral({
            from:     _borrower2,
            borrower: _borrower2,
            amount:   50 * 1e18
        });
        _borrow({
            from:       _borrower2,
            amount:     500 * 1e18,
            indexLimit: 3_010,
            newLup:     327.188250324085203338 * 1e18
        });

        _assertPool(
            PoolParams({
                htp:                  10.009615384615384620 * 1e18,
                lup:                  327.188250324085203338 * 1e18,
                poolSize:             20_000 * 1e18,
                pledgedCollateral:    100 * 1e18,
                encumberedCollateral: 3.059283264206676197 * 1e18,
                poolDebt:             1000.961538461538462000 * 1e18,
                actualUtilization:    0,
                targetUtilization:    1e18,
                minDebtAmount:        50.048076923076923100 * 1e18,
                loans:                2,
                maxBorrower:          address(_borrower),
                interestRate:         0.05 * 1e18,
                interestRateUpdate:   _startTime
            })
        );
        _assertEMAs({
            debtColEma:   0,
            lupt0DebtEma: 0,
            debtEma:      0,
            depositEma:   10_000 * 1e18
        });

        skip(10 days);

        // borrower 1 borrows 10 quote from the pool
        _borrow({
            from:       _borrower,
            amount:     10 * 1e18,
            indexLimit: 3_010,
            newLup:     327.188250324085203338 * 1e18
        });

        _assertPool(
            PoolParams({
                htp:                  10.223528890139451939 * 1e18,
                lup:                  327.188250324085203338 * 1e18,
                poolSize:             20_001.166301815699560000 * 1e18,
                pledgedCollateral:    100 * 1e18,
                encumberedCollateral: 3.094069767562214045 * 1e18,
                poolDebt:             1_012.343273629329809307 * 1e18,
                actualUtilization:    0.050048053058282770 * 1e18,
                targetUtilization:    0.030592832642066762 * 1e18,
                minDebtAmount:        50.617163681466490465 * 1e18,
                loans:                2,
                maxBorrower:          address(_borrower),
                interestRate:         0.05 * 1e18,
                interestRateUpdate:   _startTime
            })
        );
        _assertEMAs({
            debtColEma:   8_636.472785378662688101 * 1e18,
            lupt0DebtEma: 282_303.796004265917437005 * 1e18,
            debtEma:      1_000.960583870227520994 * 1e18,
            depositEma:   19_999.990463256835940000 * 1e18
        });
    }
    function testPoolLargeCollateralPostedTargetUtilization() external tearDown {

        // add initial quote to the pool
        _addInitialLiquidity({
            from:   _lender,
            amount: 20_000 * 1e18,
            index:  3_010
        });
        _addInitialLiquidity({
            from:   _lender,
            amount: 20_000 * 1e18,
            index:  2_995
        });

        _assertPool(
            PoolParams({
                htp:                  0,
                lup:                  MAX_PRICE,
                poolSize:             40_000 * 1e18,
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
        _assertEMAs({
            debtColEma:   0,
            lupt0DebtEma: 0,
            debtEma:      0,
            depositEma:   20_000 * 1e18
        });

        // borrower 1 borrows 10000 quote from the pool
        _pledgeCollateral({
            from:     _borrower,
            borrower: _borrower,
            amount:   50 * 1e18
        });
        _borrow({
            from:       _borrower,
            amount:     10_000 * 1e18,
            indexLimit: 3_010,
            newLup:     327.188250324085203338 * 1e18
        });

        _assertPool(
            PoolParams({
                htp:                  200.192307692307692400 * 1e18,
                lup:                  327.188250324085203338 * 1e18,
                poolSize:             40_000 * 1e18,
                pledgedCollateral:    50 * 1e18,
                encumberedCollateral: 30.592832642066761971 * 1e18,
                poolDebt:             10009.615384615384620000 * 1e18,
                actualUtilization:    0,
                targetUtilization:    1e18,
                minDebtAmount:        1000.961538461538462000 * 1e18,
                loans:                1,
                maxBorrower:          address(_borrower),
                interestRate:         0.05 * 1e18,
                interestRateUpdate:   _startTime
            })
        );
        _assertEMAs({
            debtColEma:   0,
            lupt0DebtEma: 0,
            debtEma:      0,
            depositEma:   20_000 * 1e18
        });

        // borrower 2 borrows 9000 quote from the pool
        _pledgeCollateral({
            from:     _borrower2,
            borrower: _borrower2,
            amount:   50 * 1e18
        });
        _borrow({
            from:       _borrower2,
            amount:     9000 * 1e18,
            indexLimit: 3_010,
            newLup:     327.188250324085203338 * 1e18
        });

        _assertPool(
            PoolParams({
                htp:                  200.192307692307692400 * 1e18,
                lup:                  327.188250324085203338 * 1e18,
                poolSize:             40_000 * 1e18,
                pledgedCollateral:    100 * 1e18,
                encumberedCollateral: 58.126382019926847745 * 1e18,
                poolDebt:             19_018.269230769230778000 * 1e18,
                actualUtilization:    0,
                targetUtilization:    1e18,
                minDebtAmount:        950.913461538461538900 * 1e18,
                loans:                2,
                maxBorrower:          address(_borrower),
                interestRate:         0.05 * 1e18,
                interestRateUpdate:   _startTime
            })
        );
        _assertEMAs({
            debtColEma:   0,
            lupt0DebtEma: 0,
            debtEma:      0,
            depositEma:   20_000 * 1e18
        });

        skip(10 days);

        // borrower 1 borrows 10 quote from the pool
        _borrow({
            from:       _borrower,
            amount:     10 * 1e18,
            indexLimit: 3_010,
            newLup:     327.188250324085203338 * 1e18
        });

        _assertPool(
            PoolParams({
                htp:                  200.666923956635192629 * 1e18,
                lup:                  327.188250324085203338 * 1e18,
                poolSize:             40_022.159734498291760000 * 1e18,
                pledgedCollateral:    100 * 1e18,
                encumberedCollateral: 58.236654596124865142 * 1e18,
                poolDebt:             19_054.349122034189453676 * 1e18,
                actualUtilization:    0.475456504053686315 * 1e18,
                targetUtilization:    0.582873969285693044 * 1e18,
                minDebtAmount:        952.717456101709472684 * 1e18,
                loans:                2,
                maxBorrower:          address(_borrower),
                interestRate:         0.05 * 1e18,
                interestRateUpdate:   _startTime
            })
        );
        _assertEMAs({
            debtColEma:   3_126_403.148307075893092949 * 1e18,
            lupt0DebtEma: 5_363_772.124081052431303092 * 1e18,
            debtEma:      19_018.251093534322898890 * 1e18,
            depositEma:   39_999.980926513671880000 * 1e18
        });

        skip(10 days);

        // borrower 3 pledges enormous qty (50,000) of collateral and takes tiny debt (12 QT)
        _pledgeCollateral({
            from:     _borrower3,
            borrower: _borrower3,
            amount:   50_000 * 1e18
        });
        _borrow({
            from:       _borrower2,
            amount:     12 * 1e18,
            indexLimit: 3_010,
            newLup:     327.188250324085203338 * 1e18
        });
        _assertPool(
            PoolParams({
                htp:                  200.941998518054562716 * 1e18,
                lup:                  327.188250324085203338 * 1e18,
                poolSize:             40_045.119710562067080000 * 1e18,
                pledgedCollateral:    50_100 * 1e18,
                encumberedCollateral: 58.353196900686720280 * 1e18,
                poolDebt:             19_092.480394752519489737 * 1e18,
                actualUtilization:    0.476094973986474284 * 1e18,
                targetUtilization:    0.583872645876088990 * 1e18,
                minDebtAmount:        954.624019737625974487 * 1e18,
                loans:                2,
                maxBorrower:          address(_borrower),
                interestRate:         0.05 * 1e18,
                interestRateUpdate:   _startTime
            })
        );
        _assertEMAs({
            debtColEma:   3_565_623.757561586266590548 * 1e18,
            lupt0DebtEma: 6_106_851.867005073649467074 * 1e18,
            debtEma:      19_054.349087608426800461 * 1e18,
            depositEma:   40_022.159713346932216568 * 1e18
        });

        skip(1 days);
        // borrower 3 touches the pool again to force an interest rate update
        _borrow({
            from:       _borrower2,
            amount:     3.14 * 1e18,
            indexLimit: 3_010,
            newLup:     327.188250324085203338 * 1e18
        });
        _assertPool(
            PoolParams({
                htp:                  200.969526704670605713 * 1e18,
                lup:                  327.188250324085203338 * 1e18,
                poolSize:             40_047.419013400059920000 * 1e18,
                pledgedCollateral:    50_100 * 1e18,
                encumberedCollateral: 58.370797186283932430 * 1e18,
                poolDebt:             19_098.239001402275530018 * 1e18,
                actualUtilization:    0.476604475533389646 * 1e18,
                targetUtilization:    0.584103777552299209 * 1e18, // big col. deposit barely affects
                minDebtAmount:        954.911950070113776501 * 1e18,
                loans:                2,
                maxBorrower:          address(_borrower),
                interestRate:         0.05 * 1e18,
                interestRateUpdate:   _startTime
            })
        );
        _assertEMAs({
            debtColEma:   3_579_931.895052572545685505 * 1e18, // big col. deposit barely affects 
            lupt0DebtEma: 6_128_931.249262523887589290 * 1e18,
            debtEma:      19_082.947567966496316465 * 1e18,
            depositEma:   40_039.379711258283363568 * 1e18
        });
    }

    function testAccruePoolInterestHtpGtMaxPrice() external tearDown {
        _addLiquidityNoEventCheck({
            from:    _lender2,
            amount:  100_000_000_000_000_000 * 1e18,
            index:   1
        });

        _drawDebtNoLupCheck({
            from:               _borrower3,
            borrower:           _borrower3,
            amountToBorrow:     90_000_000_000_000_000 * 1e18,
            limitIndex:         5000,
            collateralToPledge: 90_100_000 * 1e18
        });

        skip(100 days);

        assertGt(MAX_PRICE, _htp());

        uint256 expectedPoolDebt = 91329091841208027.611736396814389869 * 1e18;

        _assertPool(
            PoolParams({
                htp:                  999850593.357807564705882353 * 1e18,
                lup:                  999969141.897027226245329498 * 1e18,
                poolSize:             100_000_000_000_000_000 * 1e18,
                pledgedCollateral:    90_100_000 * 1e18,
                encumberedCollateral: 91_331_910.170696775095411340 * 1e18,
                poolDebt:             91329091841208027.611736396814389869 * 1e18,
                actualUtilization:    0,
                targetUtilization:    1 * 1e18,
                minDebtAmount:        9132909184120802.761173639681438987 * 1e18,
                loans:                1,
                maxBorrower:          address(_borrower3),
                interestRate:         0.05 * 1e18,
                interestRateUpdate:   _startTime
            })
        );

        (uint256 poolDebt,,,) = _pool.debtInfo();
        assertEq(poolDebt, expectedPoolDebt);

        // accrue interest
        _updateInterest();

        // check that no interest earned if HTP is over the highest price bucket
        (poolDebt,,,) = _pool.debtInfo();
        assertEq(poolDebt, expectedPoolDebt);
    }

    function testAccruePoolInterestHtpLup() external tearDown {
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
        _addInitialLiquidity({
            from:   _lender,
            amount: 1_000 * 1e18,
            index:  4000
        });
        _addInitialLiquidity({
            from:   _lender,
            amount: 30_000 * 1e18,
            index:  5000
        });

        uint256 snapshot = vm.snapshot();

        // first borrower pledge collateral and borrows
        _pledgeCollateral({
            from:     _borrower,
            borrower: _borrower,
            amount:   1000 * 1e18
        });
        _borrow({
            from:       _borrower,
            amount:     100 * 1e18,
            indexLimit: _i9_72,
            newLup:     _p9_91
        });


        // Assert that HTP < LUP, meaning on accual interest should accrue between HTP - LUP
        _assertPool(
            PoolParams({
                htp:                  0.100096153846153846 * 1e18,
                lup:                  _p9_91,
                poolSize:             104_000.00 * 1e18,
                pledgedCollateral:    1_000 * 1e18,
                encumberedCollateral: 10.093202398300210588 * 1e18,
                poolDebt:             100.096153846153846200 * 1e18,
                actualUtilization:    0,
                targetUtilization:    1 * 1e18,
                minDebtAmount:        10.009615384615384620 * 1e18,
                loans:                1,
                maxBorrower:          address(_borrower),
                interestRate:         0.05 * 1e18,
                interestRateUpdate:   _startTime
            })
        );

        skip(100 days);

        _repayDebt({
            from:             _borrower,
            borrower:         _borrower,
            amountToRepay:    0.0001 * 1e18,
            amountRepaid:     0.0001 * 1e18,
            collateralToPull: 0,
            newLup:           _p9_91
        });

        // Proof that interest accrued between HTP and LUP
        _assertBucket({
            index:        _i9_62,
            lpBalance:    25_000.00 * 1e18,
            collateral:   0,
            deposit:      25_000.396460350119775000 * 1e18,
            exchangeRate: 1.000015858414004791 * 1e18
        });

        vm.revertTo(snapshot);

        // first borrower pledge collateral and borrows
        _pledgeCollateral({
            from:     _borrower,
            borrower: _borrower,
            amount:   1000 * 1e18
        });
        _borrow({
            from:       _borrower,
            amount:     9_500 * 1e18,
            indexLimit: _i9_72,
            newLup:     _p9_72
        });

        // borrower3 pledge collateral and borrows so we have a lower LUP value
        _pledgeCollateral({
            from:     _borrower3,
            borrower: _borrower3,
            amount:   10_000_000 * 1e18
        });
        _borrow({
            from:       _borrower3,
            amount:     65_000 * 1e18,
            indexLimit: 7_000,
            newLup:    0.014854015662334135 * 1e18
        });

        // Assert that HTP < LUP, meaning on accual interest should accrue between HTP - LUP
        _assertPool(
            PoolParams({
                htp:                  9.509134615384615389 * 1e18,
                lup:                  0.014854015662334135 * 1e18,
                poolSize:             104_000.00 * 1e18,
                pledgedCollateral:    10_001_000.0 * 1e18,
                encumberedCollateral: 5_020_301.332014790293374287 * 1e18,
                poolDebt:             74_571.634615384615419000 * 1e18,
                actualUtilization:    0,
                targetUtilization:    1 * 1e18,
                minDebtAmount:        3_728.581730769230770950 * 1e18,
                loans:                2,
                maxBorrower:          address(_borrower),
                interestRate:         0.05 * 1e18,
                interestRateUpdate:   _startTime
            })
        );

        skip(100 days);

        // Proof that no interest accrued since no actions have been called against the book
        _assertBucket({
            index:        4_000,
            lpBalance:    1_000.00 * 1e18,
            collateral:   0,
            deposit:      1_000.00 * 1e18,
            exchangeRate: 1.0 * 1e18
        });

        _repayDebt({
            from:             _borrower3,
            borrower:         _borrower3,
            amountToRepay:    0.0001 * 1e18,
            amountRepaid:     0.0001 * 1e18,
            collateralToPull: 0,
            newLup:           0.014854015662334135 * 1e18
        });

        // Proof that interest accrued between LUP and HTP
        _assertBucket({
            index:        4_000,
            lpBalance:    1000.00 * 1e18,
            collateral:   0,
            deposit:      1_008.406484270040092000 * 1e18,
            exchangeRate: 1.008406484270040092 * 1e18
        });
    }
}
