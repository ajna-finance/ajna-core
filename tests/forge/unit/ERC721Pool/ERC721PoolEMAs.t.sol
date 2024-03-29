// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.18;

import { ERC721HelperContract } from './ERC721DSTestPlus.sol';

import 'src/libraries/helpers/PoolHelper.sol';

contract ERC721PoolEMAsTest is ERC721HelperContract {

    address internal _attacker;
    address internal _borrower;
    address internal _lender;

    function setUp() external {
        _startTest();

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
            depositEma:     9_999.543378995433790000 * 1e18
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
            depositEma:     9_999.543378995433790000 * 1e18
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
                htp:                  1_205.367672582122068119 * 1e18,  // 7000 / 6 = 1166.66
                lup:                  _p1505_26,
                poolSize:             14_999.315068493150685000 * 1e18,
                pledgedCollateral:    6 * 1e18,
                encumberedCollateral: 4.804610580000000002 * 1e18,      // 6 / 1.3 = 4.62
                poolDebt:             6_954.044264896858085302 * 1e18,
                actualUtilization:    0.000000000000000000 * 1e18,      // moving -> 6_947 / 10_000 (meaningful) = 0.7
                targetUtilization:    1.000000000000000000 * 1e18,
                minDebtAmount:        695.404426489685808530 * 1e18,    // debt / 10; only one loan, so not enforced
                loans:                1,
                maxBorrower:          address(_borrower),
                interestRate:         0.05 * 1e18,
                interestRateUpdate:   _startTime
            })
        );
        _assertEMAs({
            debtColEma:     0.000000000000000000 * 1e18,       // 6_954^2 / 6         ~=  8_059_686
            lupt0DebtEma:   0.000000000000000000 * 1e18,       // 1_505.26 * 6_954.04 ~= 10_467_638.25
            debtEma:        0.000000000000000000 * 1e18,       // current debt with origination fee
            // previous accumulator had updated to 15_000 before debt was drawn, but now 5_000 is no longer meaningful...
            depositEma:     11_849.656270359836947749 * 1e18   // ...so it is moving down toward 10_000
        });
    }

    function testEMAAdjustmentTime() external tearDown {
        skip(3 hours);  // 11 hours passed since liquidity added

        // since pool was not touched since debt was drawn, debt EMAs should remain unchanged
        // debtColEma / lupt0DebtEma ~= 8_059_788.6 / 10_467_670.6 ~= 0.77 expected target utilization
        _assertPool(
            PoolParams({
                htp:                  1_205.388312616241411607 * 1e18,
                lup:                  _p1505_26,
                poolSize:             14_999.315068493150685000 * 1e18,
                pledgedCollateral:    6 * 1e18,
                encumberedCollateral: 4.804692851433486288 * 1e18,      // small increase due to pending interest
                poolDebt:             6_954.163342016777374652 * 1e18,  // small increase due to pending interest
                actualUtilization:    0.000000000000000000 * 1e18,
                targetUtilization:    1.000000000000000000 * 1e18,      // debtColEma / lupt0DebtEma
                minDebtAmount:        695.416334201677737465 * 1e18,    // small increase due to pending interest
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
            depositEma:     11_849.656270359836947749 * 1e18   // unchanged from setup
        });

        // touch the pool, triggering an interest accrual - EMAs should update
        _pool.updateInterest();
        _assertPool(
            PoolParams({
                htp:                  1_205.388312616241411607 * 1e18,
                lup:                  _p1505_26,
                poolSize:             14_999.416284045082078099 * 1e18, // first interest accrual
                pledgedCollateral:    6 * 1e18,
                encumberedCollateral: 4.804692851433486288 * 1e18,
                poolDebt:             6_954.163342016777374652 * 1e18,  // pending interest now equals current interest
                actualUtilization:    0.095749456023617633 * 1e18,
                targetUtilization:    0.769969644230769231 * 1e18,
                minDebtAmount:        695.416334201677737465 * 1e18,
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
            depositEma:     11_555.296677158445431048 * 1e18   // still moving toward 10_000
        });
        (uint256 interestRate, ) = _pool.interestRateInfo();
        assertEq(interestRate, 0.05 * 1e18);

        skip(9 hours);  // 12 hours since debt was drawn
        _pool.updateInterest();
        _assertEMAs({
            debtColEma:     759_857.214782711948426497 * 1e18, // updated for interest accrual
            lupt0DebtEma:   986_853.627682966275217023 * 1e18, // updated for interest accrual
            debtEma:        3_477.070405889227128676 * 1e18,   // updated for interest accrual
            depositEma:     10_924.640857102313939222 * 1e18   // still moving toward 10_000
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
            mau:    0.397628845831341404 * 1e18,    // dropping from 60% to 35%
            tu:     0.770004681960247602 * 1e18,    // still at 77%
            rate:   0.045 * 1e18
        });
        (, , , uint256 depositEma) = _pool.emasInfo();
        assertEq(depositEma, 12_581.863548293381640088 * 1e18);         // now moving toward 20_000

        _skipAndAccrue({
            time:   20 hours,                       // 24 hours since liquidity was added
            mau:    0.358938366072679811 * 1e18,    // still dropping toward 35%
            tu:     0.770034423541948909 * 1e18,    // still at 77%
            rate:   0.0405 * 1e18                   // dropping at 4.05%
        });
        (, , , depositEma) = _pool.emasInfo();
        assertEq(depositEma, 17_663.330795414242803827 * 1e18);         // still moving toward 20_000

        _skipAndAccrue({
            time:   2 days,                         // 3 days since liquidity was added
            mau:    0.348392289978865214 * 1e18,    // reached 35%
            tu:     0.770100960789580357 * 1e18,    // still at 77%
            rate:   0.03645 * 1e18                  // second interest rate drop
        });                  
        (, , , depositEma) = _pool.emasInfo();
        assertEq(depositEma, 19_854.402758785373904546 * 1e18);         // reached (sort of) 20_000
        _assertPool(
            PoolParams({
                htp:                  1_205.903602387494165119 * 1e18,
                lup:                  _p1505_26,
                poolSize:             25_001.589989976322339749 * 1e18, // reflects additional 10_000 deposit
                pledgedCollateral:    6 * 1e18,
                encumberedCollateral: 4.806746802889993501 * 1e18,
                poolDebt:             6_957.136167620158644917 * 1e18,
                actualUtilization:    0.348392289978865214 * 1e18,      // dropped to 35% as expected
                targetUtilization:    0.770100960789580357 * 1e18,
                minDebtAmount:        695.713616762015864492 * 1e18,
                loans:                1,
                maxBorrower:          address(_borrower),
                interestRate:         0.03645 * 1e18,                   // dropped twice
                interestRateUpdate:   _startTime + 98 hours
            })
        );

        // draw additional debt
        _mintAndApproveCollateralTokens(_borrower,  6);
        uint256[] memory tokenIdsToAdd = new uint256[](6);
        for (uint i=0; i<6; ++i) {
            tokenIdsToAdd[i] = i + 7;
        }
        _drawDebt({
            from:           _borrower,
            borrower:       _borrower,
            amountToBorrow: 10_000 * 1e18,          // total ~17_000 principal / 20_0000 meaningful liquidity
            limitIndex:     _i1505_26,
            tokenIds:       tokenIdsToAdd,
            newLup:         _p1505_26
        });

        _skipAndAccrue({
            time:   3 hours,
            mau:    0.428398216388973547 * 1e18,    // rising from 35% to 90%
            tu:     0.787754460637874784 * 1e18,    // increases as collateralization decreases
            rate:   0.03645 * 1e18
        });
        (, , uint256 debtEma, ) = _pool.emasInfo();
        assertEq(debtEma, 8_515.638527238944097371 * 1e18);             // increasing from 7_000 to 17_000

        _skipAndAccrue({
            time:   9 hours,
            mau:    0.599187484109433390 * 1e18,    // still rising to 90%
            tu:     0.825258290067261584 * 1e18,
            rate:   0.03645 * 1e18
        });
        (, ,  debtEma, ) = _pool.emasInfo();
        assertEq(debtEma, 11_940.719160980199574337 * 1e18);            // increasing from 7_000 to 17_000

        _skipAndAccrue({
            time:   4 days,
            mau:    0.847172260351887090 * 1e18,    // reached 90%
            tu:     0.917210771098065732 * 1e18,
            rate:   0.036450 * 1e18
        });
        (, , debtEma, ) = _pool.emasInfo();
        assertEq(debtEma, 16_945.366780417774837920 * 1e18);            // reached 17_000
        _assertPool(
            PoolParams({
                htp:                  1_470.886811717333959369 * 1e18,
                lup:                  _p1505_26,
                poolSize:             25_008.358862466871008035 * 1e18,
                pledgedCollateral:    12 * 1e18,                        // 6 additional NFTs deposited
                encumberedCollateral: 11.725946361943917541 * 1e18,     // all 12 NFTs are encumbered
                poolDebt:             16_971.770904430776454251 * 1e18, // includes new debt
                actualUtilization:    0.847172260351887090 * 1e18,
                targetUtilization:    0.917210771098065732 * 1e18,
                minDebtAmount:        1_697.177090443077645425 * 1e18,
                loans:                1,
                maxBorrower:          address(_borrower),
                interestRate:         0.036450 * 1e18,
                interestRateUpdate:   _startTime + 2 hours + 4 days
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
            mau:    0.677129230433596332 * 1e18,    // 7_647 / 10_000 ~= 76%
            tu:     0.847549967163692311 * 1e18,    // starting at 77%
            rate:   0.05 * 1e18
        });
        _assertEMAs({
            debtColEma:     2_745_421.852361791542203581 * 1e18,        // reflects newly drawn debt
            lupt0DebtEma:   3_239_244.833610561710979058 * 1e18,       // unchanged from setup
            debtEma:        6_895.273194262173362837 * 1e18,            // increasing toward 7_647
            depositEma:     10_183.097825871170114674 * 1e18            // decreasing toward 10_000
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
            amount:   149_993.153747734144698972 * 1e18,
            index:    _i1505_26,
            newLup:   _p1505_26,
            lpRedeem: 149_970.868883961819887409 * 1e18
        });

        uint256 rateChangeTs = block.timestamp;
        _skipAndAccrue({
            time:   12,                             // skip a single block
            mau:    0.632808456612359556 * 1e18,    // impacted, enough to cause rate change
            tu:     0.847550458437217496 * 1e18,
            rate:   0.045 * 1e18                    // rate changed
        });
        _assertEMAs({
            debtColEma:     2_750_442.276033142114157597 * 1e18,
            lupt0DebtEma:   3_245_166.407088766607440379 * 1e18,
            debtEma:        6_899.074247951901688984 * 1e18,
            depositEma:     10_902.310447753826633283 * 1e18            // still noticably impacted
        });

        _skipAndAccrue({
            time:   12 hours,
            mau:    0.696326201382970553 * 1e18,    // moving back toward 75%
            tu:     0.847602661886974316 * 1e18,
            rate:   0.045 * 1e18
        });
        _assertEMAs({
            debtColEma:     3_412_033.566087523366578909 * 1e18,
            lupt0DebtEma:   4_025_510.677953143880612044 * 1e18,
            debtEma:        7_277.771607265212861084 * 1e18,
            depositEma:     10_451.669911042929514005 * 1e18            // moving down back to 10_000
        });
        _assertPool(
            PoolParams({
                htp:                  1_327.203098908327068572 * 1e18,
                lup:                  _p1505_26,
                poolSize:             15_001.222354932647619025 * 1e18,
                pledgedCollateral:    6 * 1e18,
                encumberedCollateral: 5.290248109245926845 * 1e18,
                poolDebt:             7_656.940955240348472526 * 1e18,  // 7_647 principal plus some interest
                actualUtilization:    0.696326201382970553 * 1e18,
                targetUtilization:    0.847602661886974316 * 1e18,
                minDebtAmount:        765.694095524034847253 * 1e18,
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