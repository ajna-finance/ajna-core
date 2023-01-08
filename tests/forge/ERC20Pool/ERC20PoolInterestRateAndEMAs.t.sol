// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.14;

import '@openzeppelin/contracts/utils/structs/EnumerableSet.sol';

import { ERC20HelperContract } from './ERC20DSTestPlus.sol';

import 'src/libraries/helpers/PoolHelper.sol';
import 'src/interfaces/pool/erc20/IERC20Pool.sol';

contract ERC20PoolInterestRateTestAndEMAs is ERC20HelperContract {

    using EnumerableSet for EnumerableSet.AddressSet;

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
        _addInitialLiquidity(
            {
                from:   _lender,
                amount: 10_000 * 1e18,
                index:  2550
            }
        );
        _addInitialLiquidity(
            {
                from:   _lender,
                amount: 20_000 * 1e18,
                index:  2551
            }
        );
        _addInitialLiquidity(
            {
                from:   _lender,
                amount: 20_000 * 1e18,
                index:  2552
            }
        );
        _addInitialLiquidity(
            {
                from:   _lender,
                amount: 50_000 * 1e18,
                index:  3900
            }
        );
        _addInitialLiquidity(
            {
                from:   _lender,
                amount: 10_000 * 1e18,
                index:  4200
            }
        );

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
        emit UpdateInterestRate(0.05 * 1e18, 0.055 * 1e18);
        _drawDebtNoLupCheck(
            {
                from:               _borrower,
                borrower:           _borrower,
                amountToBorrow:     46_000 * 1e18,
                limitIndex:         4_300,
                collateralToPledge: 100 * 1e18
            }
        );

        _assertPool(
            PoolParams({
                htp:                  460.442307692307692520 * 1e18,
                lup:                  2_981.007422784467321543 * 1e18,
                poolSize:             110_000 * 1e18,
                pledgedCollateral:    100 * 1e18,
                encumberedCollateral: 15.469154633609698947 * 1e18,
                poolDebt:             46_113.664786991249514684 * 1e18,
                actualUtilization:    0.922273295739824990 * 1e18,
                targetUtilization:    0.154458625018190226 * 1e18,
                minDebtAmount:        4_611.366478699124951468 * 1e18,
                loans:                1,
                maxBorrower:          _borrower,
                interestRate:         0.055 * 1e18,
                interestRateUpdate:   _startTime + 10 days
            })
        );
        _assertEMAs(
            {
                debtEma:   4_340.881358710158802477 * 1e18,
                lupColEma: 28_103.845662221475161347 * 1e18
            }
        );

        skip(14 hours);

        uint256 snapshot = vm.snapshot();
        // force interest rate update by calling repay debt with 0 amounts
        _repayDebtNoLupCheck({
            from:             _borrower,
            borrower:         _borrower,
            amountToRepay:    0,
            amountRepaid:     0,
            collateralToPull: 0
        });

        _assertPool(
            PoolParams({
                htp:                  461.913231889174987773 * 1e18,
                lup:                  2_981.007422784467321543 * 1e18,
                poolSize:             110_068.755413072118050000 * 1e18,
                pledgedCollateral:    100 * 1e18,
                encumberedCollateral: 15.470514425000097931 * 1e18,
                poolDebt:             46_117.718335219467295955 * 1e18,
                actualUtilization:    0.921087771300560413 * 1e18,
                targetUtilization:    0.154587982299328870 * 1e18,
                minDebtAmount:        4_611.771833521946729596 * 1e18,
                loans:                1,
                maxBorrower:          _borrower,
                interestRate:         0.0605 * 1e18,
                interestRateUpdate:   _startTime + 10 days + 14 hours
            })
        );
        _assertEMAs(
            {
                debtEma:   8_279.448467499588505755 * 1e18,
                lupColEma: 53_558.163735316008374982 * 1e18
            }
        );

        vm.revertTo(snapshot);
        // repay entire loan
        deal(address(_quote), _borrower,  _quote.balanceOf(_borrower) + 200 * 1e18);
        _repayDebt({
            from:             _borrower,
            borrower:         _borrower,
            amountToRepay:    46_200 * 1e18,
            amountRepaid:     46_117.718335219467295955 * 1e18,
            collateralToPull: 0,
            newLup:           MAX_PRICE
        });

        _assertPool(
            PoolParams({
                htp:                  0,
                lup:                  MAX_PRICE,
                poolSize:             110_068.755413072118050000 * 1e18,
                pledgedCollateral:    100 * 1e18,
                encumberedCollateral: 0,
                poolDebt:             0,
                actualUtilization:    0,
                targetUtilization:    0.154458625018190226 * 1e18,
                minDebtAmount:        0,
                loans:                0,
                maxBorrower:          address(0),
                interestRate:         0.0495 * 1e18,
                interestRateUpdate:   _startTime + 10 days + 14 hours
            })
        );
        _assertEMAs(
            {
                debtEma:   4_340.881358710158802477 * 1e18,
                lupColEma: 28_103.845662221475161347 * 1e18
            }
        );
    }

    function testOverutilizedPoolInterestRateIncrease() external tearDown {
        // lender deposits 1000
        _addInitialLiquidity(
            {
                from:   _lender,
                amount: 1_000 * 1e18,
                index:  3232
            }
        );

        // borrower draws 9100
        _pledgeCollateral(
            {
                from:     _borrower,
                borrower: _borrower,
                amount:    1_500 * 1e18
            }
        );
        _borrow(
            {
                from:       _borrower,
                amount:     995 * 1e18,
                indexLimit: 3300,
                newLup:     100.332368143282009890 * 1e18
            }
        );
        _assertPool(
            PoolParams({
                htp:                  0.663971153846153846 * 1e18,
                lup:                  100.332368143282009890 * 1e18,
                poolSize:             1_000 * 1e18,
                pledgedCollateral:    1_500 * 1e18,
                encumberedCollateral: 9.926574536214785829 * 1e18,
                poolDebt:             995.956730769230769690 * 1e18,
                actualUtilization:    0.995956730769230770 * 1e18,
                targetUtilization:    1 * 1e18,
                minDebtAmount:        99.595673076923076969 * 1e18,
                loans:                1,
                maxBorrower:          _borrower,
                interestRate:         0.05 * 1e18,
                interestRateUpdate:   _startTime
            })
        );

        // force an interest rate update
        skip(13 hours);
        _addLiquidity(
            {
                from:    _lender,
                amount:  0,
                index:   3232,
                lpAward: 0,
                newLup:  100.332368143282009890 * 1e18
            }
        );
        _assertPool(
            PoolParams({
                htp:                  0.664069695689831259 * 1e18,
                lup:                  100.332368143282009890 * 1e18,
                poolSize:             1_000.072137597635984000 * 1e18,
                pledgedCollateral:    1_500 * 1e18,
                encumberedCollateral: 9.927311124438159308 * 1e18,
                poolDebt:             996.030634410028283604 * 1e18,
                actualUtilization:    0.995958788335693301 * 1e18,
                targetUtilization:    0.1 * 1e18,
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
        _addInitialLiquidity(
            {
                from:   _lender,
                amount: 10_000 * 1e18,
                index:  2873
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
            PoolParams({
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
        _addLiquidityNoEventCheck(
            {
                from:    _lender1,
                amount:  1_000 * 1e18,
                index:   2873
            }
        );

        _assertPool(
            PoolParams({
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

    function testMinInterestRate() external tearDown {
        _addInitialLiquidity(
            {
                from:   _lender,
                amount: 10_000 * 1e18,
                index:  _i1505_26
            }
        );

        // pledge a tiny amount of collateral and draw a tiny amount of debt
        _drawDebt(
            {
                from:               _borrower,
                borrower:           _borrower,
                amountToBorrow:     0.00001 * 1e18,
                limitIndex:         _i1505_26,
                collateralToPledge: 0.00001 * 1e18,
                newLup:             _p1505_26
            }
        );

        // confirm interest rate starts out at 5%
        _assertPool(
            PoolParams({
                htp:                  1.0009615384615 * 1e18,
                lup:                  _p1505_26,
                poolSize:             10_000 * 1e18,
                pledgedCollateral:    0.00001 * 1e18,
                encumberedCollateral: 0.000000006649741966 * 1e18,
                poolDebt:             0.000010009615384615 * 1e18,
                actualUtilization:    0.000000001000961538 * 1e18,
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
            _borrowZeroAmount(
                {
                    from:       _borrower,
                    amount:     0,
                    indexLimit: _i1505_26,
                    newLup:     _p1505_26
                }
            );
            unchecked {
                ++i;
            }
        }

        // show the rate bottoms out at 10 bps
        _assertPool(
            PoolParams({
                htp:                  1.003660230043452158 * 1e18,
                lup:                  _p1505_26,
                poolSize:             10_000.000000011461690000 * 1e18,
                pledgedCollateral:    0.00001 * 1e18,
                encumberedCollateral: 0.000000006658700114 * 1e18,
                poolDebt:             0.000010023099759839 * 1e18,
                actualUtilization:    0.000000001002309976 * 1e18,
                targetUtilization:    0.100000000000001021 * 1e18,
                minDebtAmount:        0.000001002309975984 * 1e18,
                loans:                1,
                maxBorrower:          _borrower,
                interestRate:         0.001 * 1e18,
                interestRateUpdate:   _startTime + (76*12 hours)
            })
        );
    }

    function testMaxInterestRate() external tearDown {
        _addInitialLiquidity(
            {
                from:   _lender,
                amount: 10_000 * 1e18,
                index:  _i1505_26
            }
        );

        // pledge a lot of collateral, but draw a tiny amount of debt
        _drawDebt(
            {
                from:               _borrower,
                borrower:           _borrower,
                amountToBorrow:     0.00001 * 1e18,
                limitIndex:         _i1505_26,
                collateralToPledge: 10_000 * 1e18,
                newLup:             _p1505_26
            }
        );

        // confirm interest rate starts out at 5%
        _assertPool(
            PoolParams({
                htp:                  0.000000001000961538 * 1e18,
                lup:                  _p1505_26,
                poolSize:             10_000 * 1e18,
                pledgedCollateral:    10_000 * 1e18,
                encumberedCollateral: 0.000000006649741966 * 1e18,
                poolDebt:             0.000010009615384615 * 1e18,
                actualUtilization:    0.000000001000961538 * 1e18,
                targetUtilization:    1e18,
                minDebtAmount:        0.000001000961538462 * 1e18,
                loans:                1,
                maxBorrower:          _borrower,
                interestRate:         0.05 * 1e18,
                interestRateUpdate:   _startTime
            })
        );

        uint i = 0;
        while (i < 196) {
            // trigger an interest accumulation
            skip(12 hours);
            _borrowZeroAmount(
                {
                    from:       _borrower,
                    amount:     0,
                    indexLimit: _i1505_26,
                    newLup:     _p1505_26
                }
            );
            unchecked {
                ++i;
            }
        }

        // show the rate maxed out at 50000%
        _assertPool(
            PoolParams({
                htp:                  0.000000001003987504 * 1e18,
                lup:                  _p1505_26,
                poolSize:             10_000.000000012850420000 * 1e18,
                pledgedCollateral:    10_000 * 1e18,
                encumberedCollateral: 0.000000006659785661 * 1e18,
                poolDebt:             0.000010024733795584 * 1e18,
                actualUtilization:    0.000000001002473380 * 1e18,
                targetUtilization:    0.099999999999988029 * 1e18,
                minDebtAmount:        0.000001002473379558 * 1e18,
                loans:                1,
                maxBorrower:          _borrower,
                interestRate:         0.001 * 1e18,
                interestRateUpdate:   _startTime + (76 * 12 hours)
            })
        );
    }

    function testPendingInflator() external tearDown {
        // add liquidity
        _addInitialLiquidity(
            {
                from:   _lender,
                amount: 10_000 * 1e18,
                index:  2550
            }
        );
        _addInitialLiquidity(
            {
                from:   _lender,
                amount: 10_000 * 1e18,
                index:  2552
            }
        );
        _addInitialLiquidity(
            {
                from:   _lender,
                amount: 10_000 * 1e18,
                index:  4200
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
            PoolParams({
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
            PoolParams({
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
        _addInitialLiquidity(
            {
                from:   _lender,
                amount: 10_000 * 1e18,
                index:  3_010
            }
        );
        _addInitialLiquidity(
            {
                from:   _lender,
                amount: 10_000 * 1e18,
                index:  2_995
            }
        );

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
            PoolParams({
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
            PoolParams({
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
            PoolParams({
                htp:                  10.237543320969223878 * 1e18,
                lup:                  327.188250324085203338 * 1e18,
                poolSize:             20_001.169794343035540000 * 1e18,
                pledgedCollateral:    100 * 1e18,
                encumberedCollateral: 3.094069767562214045 * 1e18,
                poolDebt:             1012.343273629329809307 * 1e18,
                actualUtilization:    0.050614203271033305 * 1e18,
                targetUtilization:    0.1 * 1e18,
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
                lupColEma: 954.400143448544933043 * 1e18
            }
        );
    }
}
