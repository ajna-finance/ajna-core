// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.18;

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
        _startTest();

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
                poolSize:             109_994.977168949771690000 * 1e18,
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
                htp:                  478.860000000000000221 * 1e18,
                lup:                  2_981.007422784467321543 * 1e18,
                poolSize:             109_994.977168949771690000 * 1e18,
                pledgedCollateral:    100 * 1e18,
                encumberedCollateral: 16.063697001891783502 * 1e18,
                poolDebt:             46_044.230769230769252000 * 1e18,
                actualUtilization:    0.000000000000000000 * 1e18,
                targetUtilization:    1.000000000000000000 * 1e18,
                minDebtAmount:        4_604.423076923076925200 * 1e18,
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
            depositEma:   109_994.881805872808333863 * 1e18
        });

        skip(14 hours);

        uint256 snapshot = vm.snapshot();
        // update interest rate
        _updateInterest();

        _assertPool(
            PoolParams({
                htp:                  478.894439800046459253 * 1e18,
                lup:                  2_981.007422784467321543 * 1e18,
                poolSize:             109_997.791960299722618973 * 1e18,
                pledgedCollateral:    100 * 1e18,
                encumberedCollateral: 16.064852309315147443 * 1e18,
                poolDebt:             46_047.542288466005697371 * 1e18,
                actualUtilization:    0.332803975174572376 * 1e18,
                targetUtilization:    0.154458625018190226 * 1e18,
                minDebtAmount:        4_604.754228846600569737 * 1e18,
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
            depositEma:   76_723.415550562905372147 * 1e18
        });

        vm.revertTo(snapshot);
        // repay entire loan

        deal(address(_quote), _borrower,  _quote.balanceOf(_borrower) + 200 * 1e18);

        _repayDebt({
            from:             _borrower,
            borrower:         _borrower,
            amountToRepay:    46_200 * 1e18,
            amountRepaid:     46_047.542288466005697371 * 1e18,
            collateralToPull: 0,
            newLup:           MAX_PRICE
        });

        _assertPool(
            PoolParams({
                htp:                  0,
                lup:                  MAX_PRICE,
                poolSize:             109_997.791960299722618973 * 1e18,
                pledgedCollateral:    100 * 1e18,
                encumberedCollateral: 0,
                poolDebt:             0,
                actualUtilization:    0.332803975174572376 * 1e18,
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
            depositEma:   76_723.415550562905372147 * 1e18
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
                htp:                  0.690530000000000000 * 1e18,
                lup:                  100.332368143282009890 * 1e18,
                poolSize:             999.954337899543379 * 1e18,
                pledgedCollateral:    1_500 * 1e18,
                encumberedCollateral: 10.323637517663377262 * 1e18,
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
                htp:                  0.690581239857619609 * 1e18,
                lup:                  100.332368143282009890 * 1e18,
                poolSize:             1_000.017155994221264894 * 1e18,
                pledgedCollateral:    1_500 * 1e18,
                encumberedCollateral: 10.324403569415685680 * 1e18,
                poolDebt:             996.030634410028283604 * 1e18,
                actualUtilization:    0.525951759473550087 * 1e18,
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
                htp:                  520.500000000000000240 * 1e18,
                lup:                  601.252968524772188572 * 1e18,
                poolSize:             9_999.54337899543379 * 1e18,
                pledgedCollateral:    10 * 1e18,
                encumberedCollateral: 8.656921915530715754 * 1e18,
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
                htp:                  520.535651905873249005 * 1e18,
                lup:                  601.252968524772188572 * 1e18,
                poolSize:             10_999.789102664133521092 * 1e18,
                pledgedCollateral:    10 * 1e18,
                encumberedCollateral: 8.657514875694566985 * 1e18,
                poolDebt:             5_005.150499094935086587 * 1e18,
                actualUtilization:    0.250251811638747103 * 1e18,
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
                htp:                  1.040999999999960000 * 1e18,
                lup:                  _p1505_26,
                poolSize:             9_999.54337899543379 * 1e18,
                pledgedCollateral:    0.00001 * 1e18,
                encumberedCollateral: 0.000000006915731644 * 1e18,
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
                htp:                  1.042402375023292669 * 1e18,
                lup:                  _p1505_26,
                poolSize:             9_999.543379006895126627 * 1e18,
                pledgedCollateral:    0.00001 * 1e18,
                encumberedCollateral: 0.000000006925048118 * 1e18,
                poolDebt:             0.000010023099759840 * 1e18,
                actualUtilization:    0.000000001002352927 * 1e18,
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
                htp:                  0.000000001041000000 * 1e18,
                lup:                  _p1505_26,
                poolSize:             9_999.54337899543379 * 1e18,
                pledgedCollateral:    10_000 * 1e18,
                encumberedCollateral: 0.000000006915731644 * 1e18,
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
                htp:                  1069241977,
                lup:                  _p1505_26,
                poolSize:             9_999.543379226256659662 * 1e18,
                pledgedCollateral:    10_000.0 * 1e18,
                encumberedCollateral: 0.000000007103353103 * 1e18,
                poolDebt:             0.000010281172862061 * 1e18,
                actualUtilization:    0.000000001027866512 * 1e18,
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
                htp:                  312.300000000000000144 * 1e18,
                lup:                  2_981.007422784467321543 * 1e18,
                poolSize:             29_998.63013698630137 * 1e18,
                pledgedCollateral:    50 * 1e18,
                encumberedCollateral: 5.238162065834277229 * 1e18,
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
                htp:                  312.301782539333725867 * 1e18,
                lup:                  2_981.007422784467321543 * 1e18,
                poolSize:             29_998.63013698630137 * 1e18,
                pledgedCollateral:    50 * 1e18,
                encumberedCollateral: 5.238191964104910529 * 1e18,
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
                poolSize:             19_999.08675799086758 * 1e18,
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
            depositEma:   9_999.54337899543379 * 1e18
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
                htp:                  10.410000000000000005 * 1e18,
                lup:                  327.188250324085203338 * 1e18,
                poolSize:             19_999.08675799086758 * 1e18,
                pledgedCollateral:    50 * 1e18,
                encumberedCollateral: 1.590827297387471623 * 1e18,
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
            depositEma:   9_999.54337899543379 * 1e18
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
                htp:                  10.410000000000000005 * 1e18,
                lup:                  327.188250324085203338 * 1e18,
                poolSize:             19_999.08675799086758 * 1e18,
                pledgedCollateral:    100 * 1e18,
                encumberedCollateral: 3.181654594774943245 * 1e18,
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
            depositEma:   9_999.54337899543379 * 1e18
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
                htp:                  10.632470045745030017 * 1e18,
                lup:                  327.188250324085203338 * 1e18,
                poolSize:             20_000.253059806567146479 * 1e18,
                pledgedCollateral:    100 * 1e18,
                encumberedCollateral: 3.217832558264702607 * 1e18,
                poolDebt:             1_012.343273629329809309 * 1e18,
                actualUtilization:    0.050050338461865504 * 1e18,
                targetUtilization:    0.030592832642066762 * 1e18,
                minDebtAmount:        50.617163681466490466 * 1e18,
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
            depositEma:   19_999.077221683171244387 * 1e18
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
                poolSize:             39_998.17351598173516 * 1e18,
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
            depositEma:   19_999.08675799086758 * 1e18
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
                htp:                  208.200000000000000096 * 1e18,
                lup:                  327.188250324085203338 * 1e18,
                poolSize:             39_998.17351598173516 * 1e18,
                pledgedCollateral:    50 * 1e18,
                encumberedCollateral: 31.816545947749432450 * 1e18,
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
            depositEma:   19_999.08675799086758 * 1e18
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
                htp:                  208.200000000000000096 * 1e18,
                lup:                  327.188250324085203338 * 1e18,
                poolSize:             39_998.17351598173516 * 1e18,
                pledgedCollateral:    100 * 1e18,
                encumberedCollateral: 60.451437300723921655 * 1e18,
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
            depositEma:   19_999.08675799086758 * 1e18
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
                htp:                  208.693600914900600334 * 1e18,
                lup:                  327.188250324085203338 * 1e18,
                poolSize:             40_020.333250480026923092 * 1e18,
                pledgedCollateral:    100 * 1e18,
                encumberedCollateral: 60.566120779969859747 * 1e18,
                poolDebt:             19_054.349122034189453678 * 1e18,
                actualUtilization:    0.475478215387722284 * 1e18,
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
            depositEma:   39_998.154443366342488772 * 1e18
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
                htp:                  208.979678458776745225 * 1e18,
                lup:                  327.188250324085203338 * 1e18,
                poolSize:             40_043.293270139495569883 * 1e18,
                pledgedCollateral:    50_100 * 1e18,
                encumberedCollateral: 60.687324776714189092 * 1e18,
                poolDebt:             19_092.480394752519489739 * 1e18,
                actualUtilization:    0.476116702437763762 * 1e18,
                targetUtilization:    0.583872645876088990 * 1e18,
                minDebtAmount:        954.624019737625974487 * 1e18,
                loans:                2,
                maxBorrower:          address(_borrower),
                interestRate:         0.05 * 1e18,
                interestRateUpdate:   _startTime
            })
        );
        _assertEMAs({
            debtColEma:   3_565_623.757561586266590894 * 1e18,
            lupt0DebtEma: 6_106_851.867005073649467356 * 1e18,
            debtEma:      19_054.349087608426800462 * 1e18,
            depositEma:   40_020.333229328668210248 * 1e18
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
                htp:                  209.008307772857429942 * 1e18,
                lup:                  327.188250324085203338 * 1e18,
                poolSize:             40_045.592577350080602020 * 1e18,
                pledgedCollateral:    50_100 * 1e18,
                encumberedCollateral: 60.705629073735289727 * 1e18,
                poolDebt:             19_098.239001402275530021 * 1e18,
                actualUtilization:    0.476626217493207138 * 1e18,
                targetUtilization:    0.584103777552299209 * 1e18, // big col. deposit barely affects
                minDebtAmount:        954.911950070113776501 * 1e18,
                loans:                2,
                maxBorrower:          address(_borrower),
                interestRate:         0.05 * 1e18,
                interestRateUpdate:   _startTime
            })
        );
        _assertEMAs({
            debtColEma:   3_579_931.895052572545685861 * 1e18, // big col. deposit barely affects 
            lupt0DebtEma: 6_128_931.249262523887589579 * 1e18,
            debtEma:      19_082.947567966496316465 * 1e18,
            depositEma:   40_037.553259936788729400 * 1e18
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
            collateralToPledge: 95_000_000 * 1e18
        });

        skip(100 days);

        assertGt(MAX_PRICE, _getHtp());

        uint256 expectedPoolDebt = 91329091841208027.611736396814389869 * 1e18;

        _assertPool(
            PoolParams({
                htp:                  999_813_215.945856302275851081 * 1e18,
                lup:                  999969141.897027226245329498 * 1e18,
                poolSize:             99_995_433_789_954_337.9 * 1e18,
                pledgedCollateral:    95_000_000 * 1e18,
                encumberedCollateral: 94_985_186.577524646099227793 * 1e18,
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
                htp:                  0.104100000000000000 * 1e18,
                lup:                  _p9_91,
                poolSize:             103_995.251141552511416 * 1e18,
                pledgedCollateral:    1_000 * 1e18,
                encumberedCollateral: 10.496930494232219012 * 1e18,
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
            lpBalance:    24_998.858447488584475 * 1e18,
            collateral:   0,
            deposit:      24_999.254907838704247316 * 1e18,
            exchangeRate: 1.000015859138166351 * 1e18
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
            amount:     9_000 * 1e18,
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
                htp:                  9.369000000000000004 * 1e18,
                lup:                  0.014854015662334135 * 1e18,
                poolSize:             103_995.251141552511416 * 1e18,
                pledgedCollateral:    10_001_000.0 * 1e18,
                encumberedCollateral: 5_186_072.355863869274873626 * 1e18,
                poolDebt:             74_071.153846153846188000 * 1e18,
                actualUtilization:    0,
                targetUtilization:    1 * 1e18,
                minDebtAmount:        3_703.557692307692309400 * 1e18,
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
            lpBalance:    999.954337899543379 * 1e18,
            collateral:   0,
            deposit:      999.954337899543379 * 1e18,
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
            lpBalance:    999.954337899543379 * 1e18,
            collateral:   0,
            deposit:      1_008.304402812066423762 * 1e18,
            exchangeRate: 1.008350446211436809 * 1e18
        });
    }

    function testAccruePoolInterestInterestUpdateFailureDueToExpLimit() external tearDown {
        _mintQuoteAndApproveTokens(_lender, 1_000_000_000 * 1e18);
        _mintCollateralAndApproveTokens(_borrower, 1_000_000_000 * 1e18);

        _addInitialLiquidity({
            from:   _lender,
            amount: 1_000_000_000 * 1e18, // 1 billion
            index:  _i1505_26
        });

        // draw 80% of liquidity as debt
        _drawDebt({
            from:               _borrower,
            borrower:           _borrower,
            amountToBorrow:     800_000_000 * 1e18,
            limitIndex:         _i1505_26,
            collateralToPledge: 1_000_000_000 * 1e18,
            newLup:             _p1505_26
        });

        _assertPool(
            PoolParams({
                htp:                  0.832800000000000001 * 1e18,
                lup:                  _p1505_26,
                poolSize:             999_954_337.899543379 * 1e18,
                pledgedCollateral:    1_000_000_000 * 1e18,
                encumberedCollateral: 553_258.531544502879307236 * 1e18,
                poolDebt:             800_769_230.7692307696 * 1e18,
                actualUtilization:    0,
                targetUtilization:    1e18,
                minDebtAmount:        80_076_923.07692307696 * 1e18,
                loans:                1,
                maxBorrower:          _borrower,
                interestRate:         0.05 * 1e18,
                interestRateUpdate:   _startTime
            })
        );

        // Update interest after 12 hours
        uint i = 0;
        while (i < 93) {
            // trigger an interest accumulation
            skip(12 hours);

            _updateInterest();

            unchecked { ++i; }
        }

        // confirm we hit 400% max rate
        _assertPool(
            PoolParams({
                htp:                  0.933310629587883290 * 1e18,
                lup:                  _p1505_26,
                poolSize:             1_088_282_545.280982499467572293 * 1e18,
                pledgedCollateral:    1_000_000_000 * 1e18,
                encumberedCollateral: 620_031.302114154381677443 * 1e18,
                poolDebt:             897_414_066.911426239994562461 * 1e18,
                actualUtilization:    0.822526771547753414 * 1e18,
                targetUtilization:    0.000573363809855153 * 1e18,
                minDebtAmount:        89_741_406.691142623999456246 * 1e18,
                loans:                1,
                maxBorrower:          _borrower,
                interestRate:         4 * 1e18,
                interestRateUpdate:   _startTime + 1104 hours
            })
        );

        // wait 32 years
        skip(365 days * 32);

        // Interest update should fail
        vm.expectEmit(true, true, false, true);
        emit InterestUpdateFailure();
        _updateInterest();

        // repay all borrower debt based on last inflator
        (uint256 inflator, ) = _pool.inflatorInfo();
        (uint256 debt, , ) = _pool.borrowerInfo(_borrower);

        _mintQuoteAndApproveTokens(_borrower, Maths.ceilWmul(inflator, debt));
        _repayDebt({
            from:             _borrower,
            borrower:         _borrower,
            amountToRepay:    type(uint256).max,
            amountRepaid:     Maths.ceilWmul(inflator, debt),
            collateralToPull: 0,
            newLup:           MAX_PRICE
        });
    }

    function testAccrueInterestInterestUpdateFailure() external tearDown {
        _mintQuoteAndApproveTokens(_lender, 1_000_000_000 * 1e18);
        _mintCollateralAndApproveTokens(_borrower, 1_000_000_000 * 1e18);

        _addInitialLiquidity({
            from:   _lender,
            amount: 1_000_000_000 * 1e18, // 1 billion
            index:  _i1505_26
        });

        // draw 80% of liquidity as debt
        _drawDebt({
            from:               _borrower,
            borrower:           _borrower,
            amountToBorrow:     800_000_000 * 1e18,
            limitIndex:         _i1505_26,
            collateralToPledge: 1_000_000_000 * 1e18,
            newLup:             _p1505_26
        });

        _assertPool(
            PoolParams({
                htp:                  0.832800000000000001 * 1e18,
                lup:                  _p1505_26,
                poolSize:             999_954_337.899543379000000000 * 1e18,
                pledgedCollateral:    1_000_000_000 * 1e18,
                encumberedCollateral: 553_258.531544502879307236 * 1e18,
                poolDebt:             800_769_230.7692307696 * 1e18,
                actualUtilization:    0,
                targetUtilization:    1e18,
                minDebtAmount:        80_076_923.07692307696 * 1e18,
                loans:                1,
                maxBorrower:          _borrower,
                interestRate:         0.05 * 1e18,
                interestRateUpdate:   _startTime
            })
        );

        // update interest rate after each 14 hours
        uint i = 0;
        while (i < 171) {
            // trigger an interest accumulation
            skip(14 hours);

            _updateInterest();

            unchecked { ++i; }
        }

        // Pledge some collateral to avoid tu overflow in `(((tu + mau102 - 1e18) / 1e9) ** 2)`
        _mintCollateralAndApproveTokens(_borrower, 1_000_000_000 * 1e24);
        IERC20Pool(address(_pool)).drawDebt(_borrower, 0, 0, 1_000_000_000 * 1e24);

        skip(14 hours);

        // Update interest rate after each 13 hours
        while (i < 11087) {
            // trigger an interest accumulation
            skip(13 hours);

            _updateInterest();

            unchecked { ++i; }
        }

        skip(13 hours);

        // Interest update should fail
        vm.expectEmit(true, true, false, true);
        emit InterestUpdateFailure();
        _updateInterest();
    }

    function testUpdateInterestZeroDebtToCollateral() external {
        _mintQuoteAndApproveTokens(_lender, 1_000_000_000 * 1e18);
        _mintCollateralAndApproveTokens(_borrower, 1_000_000_000 * 1e18);

        _addInitialLiquidity({
            from:   _lender,
            amount: 1_000_000_000 * 1e18, // 1 billion
            index:  _i1505_26
        });

        // draw 80% of liquidity as debt
        _drawDebt({
            from:               _borrower,
            borrower:           _borrower,
            amountToBorrow:     800_000_000 * 1e18,
            limitIndex:         _i1505_26,
            collateralToPledge: 1_000_000_000 * 1e18,
            newLup:             _p1505_26
        });

        _assertPool(
            PoolParams({
                htp:                  0.832800000000000001 * 1e18,
                lup:                  _p1505_26,
                poolSize:             999_954_337.899543379 * 1e18,
                pledgedCollateral:    1_000_000_000 * 1e18,
                encumberedCollateral: 553_258.531544502879307236 * 1e18,
                poolDebt:             800_769_230.7692307696 * 1e18,
                actualUtilization:    0,
                targetUtilization:    1e18,
                minDebtAmount:        80_076_923.07692307696 * 1e18,
                loans:                1,
                maxBorrower:          _borrower,
                interestRate:         0.05 * 1e18,
                interestRateUpdate:   _startTime
            })
        );

        // update interest rate after each day
        uint i = 0;
        while (i < 104) {
            // trigger an interest accumulation
            skip(1 days);

            // check borrower collateralization and pledge more collateral if undercollateralized
            (uint256 debt, uint256 collateralPledged, , ) = _poolUtils.borrowerInfo(address(_pool), _borrower);
            uint256 requiredCollateral = _requiredCollateral(debt, _lupIndex());

            if (requiredCollateral > collateralPledged ) {
                uint256 collateralToPledge = requiredCollateral - collateralPledged;
                _mintCollateralAndApproveTokens(_borrower, collateralToPledge);

                // Pledge collateral reverts with `ZeroDebtToCollateral()`
                if (i == 103) {
                    vm.expectRevert();
                }

                changePrank(_borrower);
                IERC20Pool(address(_pool)).drawDebt(_borrower, 0, 0, collateralToPledge);
            } else {
                _updateInterest();
            }

            unchecked { ++i; }
        }
    }

    function testTuLimitInterestUpdateFailure() external tearDown {
        _mintQuoteAndApproveTokens(_lender, 1_000_000_000 * 1e18);
        _mintCollateralAndApproveTokens(_borrower, 1_000_000_000 * 1e18);

        _addInitialLiquidity({
            from:   _lender,
            amount: 1_000_000_000 * 1e18, // 1 billion
            index:  _i1505_26
        });

        // draw 80% of liquidity as debt
        _drawDebt({
            from:               _borrower,
            borrower:           _borrower,
            amountToBorrow:     800_000_000 * 1e18,
            limitIndex:         _i1505_26,
            collateralToPledge: 1_000_000_000 * 1e18,
            newLup:             _p1505_26
        });

        _assertPool(
            PoolParams({
                htp:                  0.832800000000000001 * 1e18,
                lup:                  _p1505_26,
                poolSize:             999_954_337.899543379 * 1e18,
                pledgedCollateral:    1_000_000_000 * 1e18,
                encumberedCollateral: 553_258.531544502879307236 * 1e18,
                poolDebt:             800_769_230.7692307696 * 1e18,
                actualUtilization:    0,
                targetUtilization:    1e18,
                minDebtAmount:        80_076_923.07692307696 * 1e18,
                loans:                1,
                maxBorrower:          _borrower,
                interestRate:         0.05 * 1e18,
                interestRateUpdate:   _startTime
            })
        );

        // update interest rate after each day
        uint i = 0;
        while (i < 4865) {
            // trigger an interest accumulation
            skip(1 days);

            // stop pledging more collateral to avoid t0Tp becoming 0, i = 103 is the limit where t0tp becomes 0
            if (i < 100) {
                // check borrower collateralization and pledge more collateral if undercollateralized to avoid `(((tu + mau102 - 1e18) / 1e9) ** 2)` overflow
                (uint256 debt, uint256 collateralPledged, , ) = _poolUtils.borrowerInfo(address(_pool), _borrower);
                (uint256 poolDebt,,,) = _pool.debtInfo();
                uint256 lupIndex = _pool.depositIndex(poolDebt);
                uint256 requiredCollateral = _requiredCollateral(debt, lupIndex);
                
                if (requiredCollateral > collateralPledged) {
                    uint256 collateralToPledge = requiredCollateral - collateralPledged;
                    _mintCollateralAndApproveTokens(_borrower, collateralToPledge);

                    changePrank(_borrower);
                    IERC20Pool(address(_pool)).drawDebt(_borrower, 0, 0, collateralToPledge);
                }

            } else {
                _updateInterest();
            }

            unchecked { ++i; }
        }

        skip(1 days);

        // Interest update should fail
        vm.expectEmit(true, true, false, true);
        emit InterestUpdateFailure();
        _updateInterest();
    }
}
