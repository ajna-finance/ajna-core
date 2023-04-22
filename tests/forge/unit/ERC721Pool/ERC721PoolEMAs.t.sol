// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.14;

import { ERC721HelperContract } from './ERC721DSTestPlus.sol';

import 'src/libraries/helpers/PoolHelper.sol';

contract ERC721PoolEMAsTest is ERC721HelperContract {

    address internal _attacker;
    address internal _borrower;
    address internal _lender;

    function setUp() external {
        _lender    = makeAddr("lender");
        _borrower  = makeAddr("borrower");
        _attacker  = makeAddr("attacker");

        // deploy subset pool
        _pool = _deployCollectionPool();

        _mintAndApproveQuoteTokens(_lender,  25_000 * 1e18);
        _mintAndApproveQuoteTokens(_borrower, 2_000 * 1e18);
        _mintAndApproveCollateralTokens(_borrower,  6);
        _mintAndApproveQuoteTokens(_attacker,  300_000_000 * 1e18);

        // add meaningful liquidity; EMA should initialize
        _addInitialLiquidity({
            from:   _lender,
            amount: 10_000 * 1e18,
            index:  _i1505_26
        });
        _assertEMAs({
            debtColEma:     0,
            lupt0DebtEma:   0,
            debtEma:        0,
            depositEma:     10_000 * 1e18
        });

        // add unmeaningful liquidity in same block; EMA should not update
        _addInitialLiquidity({
            from:   _lender,
            amount: 5_000 * 1e18,
            index:  7000
        });
        // deposit accumulator updated to 15_000, but the EMA remains unchanged because no time passed
        _assertEMAs({
            debtColEma:     0,
            lupt0DebtEma:   0,
            debtEma:        0,
            depositEma:     10_000 * 1e18
        });
        
        skip(8 hours);

        // borrower pledges 6 nfts and draws debt to maintain 130% collateralization ratio
        uint256[] memory tokenIdsToAdd = new uint256[](6);
        uint256 borrowAmount = Maths.wmul(6 * _p1505_26, 0.76923 * 1e18);
        assertEq(borrowAmount, 6_947.364107101568112756 * 1e18);
        for (uint i=0; i<6; ++i) {
            tokenIdsToAdd[i] = i + 1;
        }
        _drawDebt({
            from:           _borrower,
            borrower:       _borrower,
            amountToBorrow: borrowAmount,
            limitIndex:     _i1505_26,
            tokenIds:       tokenIdsToAdd,
            newLup:         _p1505_26
        });

        _assertPool(
            PoolParams({
                htp:                  1_159.007377482809680884 * 1e18,  // 7000 / 6 = 1166.66
                lup:                  _p1505_26,
                poolSize:             15_000 * 1e18,
                pledgedCollateral:    6 * 1e18,
                encumberedCollateral: 4.620028820788372636 * 1e18,      // 6 / 1.3 = 4.62
                poolDebt:             6_954.361808414458420694 * 1e18,
                actualUtilization:    0.000000000000000000 * 1e18,      // moving -> 6_947 / 10_000 (meaningful) = 0.7
                targetUtilization:    1.000000000000000000 * 1e18,
                minDebtAmount:        695.436180841445842069 * 1e18,    // debt / 10; only one loan, so not enforced
                loans:                1,
                maxBorrower:          address(_borrower),
                interestRate:         0.05 * 1e18,
                interestRateUpdate:   _startTime
            })
        );
        _assertEMAs({
            debtColEma:     0.000000000000000000 * 1e18,        // 6_954^2 / 6         ~=  8_059_686
            lupt0DebtEma:   0.000000000000000000 * 1e18,       // 1_505.26 * 6_954.04 ~= 10_467_638.25
            debtEma:        0.000000000000000000 * 1e18,            // current debt with origination fee
            // previous accumulator had updated to 15_000 before debt was drawn, but now 5_000 is no longer meaningful...
            depositEma:     11_850.197375262816985000 * 1e18            // ...so it is moving down toward 10_000
        });
    }

    function testEMAAdjustmentTime() external tearDown {
        skip(3 hours);  // 11 hours passed since liquidity added

        // since pool was not touched since debt was drawn, debt EMAs should remain unchanged
        // debtColEma / lupt0DebtEma ~= 8_059_788.6 / 10_467_670.6 ~= 0.77 expected target utilization
        _assertPool(
            PoolParams({
                htp:                  1_159.007377482809680884 * 1e18,
                lup:                  _p1505_26,
                poolSize:             15_000 * 1e18,
                pledgedCollateral:    6 * 1e18,
                encumberedCollateral: 4.620107931548236591 * 1e18,      // small increase due to pending interest
                poolDebt:             6_954.480890971813258160 * 1e18,  // small increase due to pending interest
                actualUtilization:    0.000000000000000000 * 1e18,
                targetUtilization:    1.000000000000000000 * 1e18,      // debtColEma / lupt0DebtEma
                minDebtAmount:        695.448089097181325816 * 1e18,    // small increase due to pending interest
                loans:                1,
                maxBorrower:          address(_borrower),
                interestRate:         0.05 * 1e18,
                interestRateUpdate:   _startTime
            })
        );
        _assertEMAs({
            debtColEma:     0.000000000000000000 * 1e18,       // unchanged from setup
            lupt0DebtEma:   0.000000000000000000 * 1e18,       // unchanged from setup
            debtEma:        0.000000000000000000 * 1e18,       // unchanged from setup
            depositEma:     11_850.197375262816985000 * 1e18   // unchanged from setup
        });

        // touch the pool, triggering an interest accrual - EMAs should update
        _pool.updateInterest();
        _assertPool(
            PoolParams({
                htp:                  1_159.080148495302209694 * 1e18,
                lup:                  _p1505_26,
                poolSize:             15_000.371132163711890000 * 1e18,     // first interest accrual
                pledgedCollateral:    6 * 1e18,
                encumberedCollateral: 4.620107931548236591 * 1e18,
                poolDebt:             6_954.480890971813258160 * 1e18,  // pending interest now equals current interest
                actualUtilization:    0.095745083902338016 * 1e18,
                targetUtilization:    0.769969644230769231 * 1e18,
                minDebtAmount:        695.448089097181325816 * 1e18,
                loans:                1,
                maxBorrower:          address(_borrower),
                interestRate:         0.05 * 1e18,
                interestRateUpdate:   _startTime
            })
        );
        _assertEMAs({
            debtColEma:     197_072.776194638866068935 * 1e18, // accumulator updated, EMA initialized
            lupt0DebtEma:   255_948.760670328150445660 * 1e18, // accumulator updated, EMA initialized
            debtEma:        1_106.413371029437537443 * 1e18,   // accumulator updated, EMA initialized
            depositEma:     11_555.824340370334487364 * 1e18   // still moving toward 10_000
        });
        (uint256 interestRate, ) = _pool.interestRateInfo();
        assertEq(interestRate, 0.05 * 1e18);

        skip(9 hours);  // 12 hours since debt was drawn
        _pool.updateInterest();
        _assertEMAs({
            debtColEma:     759_883.557390504783896613 * 1e18, // updated for interest accrual
            lupt0DebtEma:   986_853.627682966275217023 * 1e18, // updated for interest accrual
            debtEma:        3_477.199139105917836267 * 1e18,   // updated for interest accrual
            depositEma:     10_925.249143290274162648 * 1e18   // still moving toward 10_000
        });
        (interestRate, ) = _pool.interestRateInfo();
        assertEq(interestRate, 0.045 * 1e18);

        skip(6 hours);

        // double the meaningful deposit
        _addLiquidityNoEventCheck({
            from:   _lender,
            amount: 10_000 * 1e18,
            index:  _i1505_26
        });

        _skipAndAccrue({
            time:   4 hours,
            mau:    0.397622119994472546 * 1e18,    // dropping from 60% to 35%
            tu:     0.770035415811601449 * 1e18,    // still at 77%
            rate:   0.045 * 1e18
        });
        (, , , uint256 depositEma) = _pool.emasInfo();
        assertEq(depositEma, 12_582.608507963702724933 * 1e18);         // now moving toward 20_000

        _skipAndAccrue({
            time:   20 hours,                       // 24 hours since liquidity was added
            mau:    0.358933852890687729 * 1e18,    // still dropping toward 35%
            tu:     0.770067458236015074 * 1e18,    // still at 77%
            rate:   0.0405 * 1e18                   // dropping at 4.05%
        });
        (, , , depositEma) = _pool.emasInfo();
        assertEq(depositEma, 17_664.344669688571758689 * 1e18);         // still moving toward 20_000

        _skipAndAccrue({
            time:   2 days,                         // 3 days since liquidity was added
            mau:    0.348388356770742011 * 1e18,    // reached 35%
            tu:     0.770135325994564531 * 1e18,    // still at 77%
            rate:   0.03645 * 1e18                  // second interest rate drop
        });                  
        (, , , depositEma) = _pool.emasInfo();
        assertEq(depositEma, 19_855.532581473734007629 * 1e18);         // reached (sort of) 20_000
        _assertPool(
            PoolParams({
                htp:                  1_159.575642053959188547 * 1e18,
                lup:                  _p1505_26,
                poolSize:             25_002.955913967460376246 * 1e18, // reflects additional 10_000 deposit
                pledgedCollateral:    6 * 1e18,
                encumberedCollateral: 4.622082975054377226 * 1e18,
                poolDebt:             6_957.453852323755131280 * 1e18,
                actualUtilization:    0.348388356770742011 * 1e18,      // dropped to 35% as expected
                targetUtilization:    0.770135325994564531 * 1e18,
                minDebtAmount:        695.745385232375513128* 1e18,
                loans:                1,
                maxBorrower:          address(_borrower),
                interestRate:         0.03645 * 1e18,                    // dropped twice
                interestRateUpdate:   _startTime + 98 hours
            })
        );

        // draw additional debt
        vm.stopPrank();
        _mintAndApproveCollateralTokens(_borrower,  6);
        uint256[] memory tokenIdsToAdd = new uint256[](6);
        for (uint i=0; i<6; ++i) {
            tokenIdsToAdd[i] = i + 7;
        }
        _drawDebt({
            from:           _borrower,
            borrower:       _borrower,
            amountToBorrow: 11_000 * 1e18,          // total ~18_000 principal / 20_0000 meaningful liquidity
            limitIndex:     _i1505_26,
            tokenIds:       tokenIdsToAdd,
            newLup:         _p1505_26
        });

        _skipAndAccrue({
            time:   3 hours,
            mau:    0.436398947261022405 * 1e18,    // rising from 35% to 90%
            tu:     0.794802131238362891 * 1e18,    // increases as collateralization decreases
            rate:   0.03645 * 1e18
        });
        (, , uint256 debtEma, ) = _pool.emasInfo();
        assertEq(debtEma, 8_675.169506576032073392 * 1e18);             // increasing from 7_000 to 18_000

        _skipAndAccrue({
            time:   9 hours,
            mau:    0.624275651572709578 * 1e18,    // still rising to 90%
            tu:     0.846215553223533151 * 1e18,
            rate:   0.03645 * 1e18
        });
        (, ,  debtEma, ) = _pool.emasInfo();
        assertEq(debtEma, 12_441.391312587344397940 * 1e18);            // increasing from 7_000 to 18_000

        _skipAndAccrue({
            time:   4 days,
            mau:    0.897069303670436098 * 1e18,    // reached 90%
            tu:     0.966852816219664605 * 1e18,
            rate:   0.032805 * 1e18
        });
        (, , debtEma, ) = _pool.emasInfo();
        assertEq(debtEma, 17_944.480736533919717209 * 1e18);            // reached 18_000
        _assertPool(
            PoolParams({
                htp:                  1_497.769957757345433425 * 1e18,
                lup:                  _p1505_26,
                poolSize:             25_010.141517477798670592 * 1e18,
                pledgedCollateral:    12 * 1e18,                        // 6 additional NFTs deposited
                encumberedCollateral: 11.940259472915000621 * 1e18,     // all 12 NFTs are encumbered
                poolDebt:             17_973.239493088145201104 * 1e18, // includes new debt
                actualUtilization:    0.897069303670436098 * 1e18,
                targetUtilization:    0.966852816219664605 * 1e18,
                minDebtAmount:        1_797.323949308814520110 * 1e18,
                loans:                1,
                maxBorrower:          address(_borrower),
                interestRate:         0.032805 * 1e18,
                interestRateUpdate:   _startTime + 110 hours + 4 days
            })
        );
    }

    function testDepositShockResistance() external tearDown {
        // add some debt to bring MAU closer to TU (77%)
        _drawDebt({
            from:           _borrower,
            borrower:       _borrower,
            amountToBorrow: 700 * 1e18,             // total 7_647 principal
            limitIndex:     _i1505_26,
            tokenIds:       new uint256[](0),
            newLup:         _p1505_26
        });
        _skipAndAccrue({
            time:   40 hours,                       // 2 days after liquidity was added
            mau:    0.677110233556701963 * 1e18,    // 7_647 / 10_000 ~= 76%
            tu:     0.847585126397651853 * 1e18,    // starting at 77%
            rate:   0.05 * 1e18
        });
        _assertEMAs({
            debtColEma:     2_745_524.266553065584517923 * 1e18,        // reflects newly drawn debt
            lupt0DebtEma:   3_239_231.294940137090747973 * 1e18,       // unchanged from setup
            debtEma:        6_895.559233472655919795 * 1e18,            // increasing toward 7_647
            depositEma:     10_183.805962068972523753 * 1e18            // decreasing toward 10_000
        });

        // bad actor comes along and deposits large amount for 5 minutes, and then withdraws
        _addLiquidityNoEventCheck({
            from:   _attacker,
            amount: 150000 * 1e18,
            index:  _i1505_26
        });
        skip(5 minutes);
        _pool.updateInterest();     // not really needed, since removing liquidity will trigger rate update
        _removeAllLiquidity({
            from:     _attacker,
            amount:   150_000.003062917635863985 * 1e18,
            index:    _i1505_26,
            newLup:   _p1505_26,
            lpRedeem: 149_973.669906855426845472 * 1e18
        });

        uint256 rateChangeTs = block.timestamp;
        _skipAndAccrue({
            time:   12,                             // skip a single block
            mau:    0.632791692026653958 * 1e18,    // impacted, enough to cause rate change
            tu:     0.847585617691556722 * 1e18,
            rate:   0.045 * 1e18                    // rate changed
        });
        _assertEMAs({
            debtColEma:     2_750_544.877504425497154098 * 1e18,
            lupt0DebtEma:   3_245_152.843668674754668559 * 1e18,
            debtEma:        6_899.360444842923621304 * 1e18,
            depositEma:     10_903.051559899926973925 * 1e18            // still noticably impacted
        });

        _skipAndAccrue({
            time:   12 hours,
            mau:    0.696306196911713144 * 1e18,    // moving back toward 75%
            tu:     0.847637823306888876 * 1e18,
            rate:   0.045 * 1e18
        });
        _assertEMAs({
            debtColEma:     3_412_160.847313164565839074 * 1e18,
            lupt0DebtEma:   4_025_493.853024754985190842 * 1e18,
            debtEma:        7_278.073513801178223507 * 1e18,
            depositEma:     10_452.403764437541109495 * 1e18            // moving down back to 10_000
        });
        _assertPool(
            PoolParams({
                htp:                  1_276.209765166823398404 * 1e18,
                lup:                  _p1505_26,
                poolSize:             15_002.177276783057210000 * 1e18,
                pledgedCollateral:    6 * 1e18,
                encumberedCollateral: 5.086988044805126619 * 1e18,
                poolDebt:             7_657.258591000940390422 * 1e18,  // 7_647 principal plus some interest
                actualUtilization:    0.696306196911713144 * 1e18,
                targetUtilization:    0.847637823306888876 * 1e18,
                minDebtAmount:        765.725859100094039042 * 1e18,
                loans:                1,
                maxBorrower:          address(_borrower),
                interestRate:         0.045 * 1e18,
                interestRateUpdate:   rateChangeTs
            })
        );
    }

    function _skipAndAccrue(
        uint256 time,   // amount of time to skip
        uint256 mau,    // expected meaningful actual utilization
        uint256 tu,     // expected target utilization
        uint256 rate    // interest rate
    ) internal {
        skip(time);
        _pool.updateInterest();
        (, , uint256 mauActual, uint256 tuActual) = _poolUtils.poolUtilizationInfo(address(_pool));
        assertEq(mauActual, mau);
        assertEq(tuActual, tu);
        (uint256 rateActual, ) = _pool.interestRateInfo();
        assertEq(rateActual, rate);
    }
}