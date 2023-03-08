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
        (uint256 debtColEma, uint256 lupt0DebtEma, uint256 debtEma, uint256 depositEma) = _pool.emasInfo();
        assertEq(debtColEma, 0);
        assertEq(lupt0DebtEma, 0);
        assertEq(debtEma, 0);
        assertEq(depositEma, 10_000 * 1e18);

        // add unmeaningful liquidity in same block; EMA should not update
        _addInitialLiquidity({
            from:   _lender,
            amount: 5_000 * 1e18,
            index:  7000
        });
        // here the deposit accumulator updated to 15_000, but the EMA remains unchanged because no time passed
        (debtColEma, lupt0DebtEma, debtEma, depositEma) = _pool.emasInfo();
        assertEq(debtColEma, 0);
        assertEq(lupt0DebtEma, 0);
        assertEq(debtEma, 0);
        assertEq(depositEma, 10_000 * 1e18);
        
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
                actualUtilization:    0.586829404159407881 * 1e18,      // 7_000 / 10_000 (meaningful) = 0.7
                targetUtilization:    0.769969644230769231 * 1e18,
                minDebtAmount:        695.436180841445842069 * 1e18,    // debt / 10; only one loan, so not enforced
                loans:                1,
                maxBorrower:          address(_borrower),
                interestRate:         0.05 * 1e18,
                interestRateUpdate:   _startTime
            })
        );
        (debtColEma, lupt0DebtEma, debtEma, depositEma) = _pool.emasInfo();
        assertEq(debtColEma,   8_059_788.606357480557372857 * 1e18);    // 7_000^2 / 6         ~=  8_166_666.66
        assertEq(lupt0DebtEma, 10_467_670.598117585349615039 * 1e18);   // 1_505.26 * 6_954.04 ~= 10_467_638.25
        assertEq(debtEma,      6_954.044264896858085302 * 1e18);        // current debt with origination fee
        // previous accumulator had updated to 15_000 before debt was drawn, but now 5_000 is no longer meaningful...
        assertEq(depositEma,   11_850.197375262816985000 * 1e18);       // ...so it is moving down toward 10_000
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
                actualUtilization:    0.586829404159407881 * 1e18,
                targetUtilization:    0.769969644230769231 * 1e18,      // debtColEma / lupt0DebtEma
                minDebtAmount:        695.448089097181325816 * 1e18,    // small increase due to pending interest
                loans:                1,
                maxBorrower:          address(_borrower),
                interestRate:         0.05 * 1e18,
                interestRateUpdate:   _startTime
            })
        );
        (uint256 debtColEma, uint256 lupt0DebtEma, uint256 debtEma, uint256 depositEma) = _pool.emasInfo();
        assertEq(debtColEma,   8_059_788.606357480557372857 * 1e18);    // unchanged from setup
        assertEq(lupt0DebtEma, 10_467_670.598117585349615039 * 1e18);   // unchanged from setup
        assertEq(debtEma,      6_954.044264896858085302 * 1e18);        // unchanged from setup
        assertEq(depositEma,   11_850.197375262816985000 * 1e18);       // unchanged from setup

        // touch the pool, triggering an interest accrual - EMAs should update
        _pool.updateInterest();
        _assertPool(
            PoolParams({
                htp:                  1_159.152924076894437152 * 1e18,
                lup:                  _p1505_26,
                poolSize:             15_000.38784582038918 * 1e18,     // first interest accrual
                pledgedCollateral:    6 * 1e18,
                encumberedCollateral: 4.620107931548236591 * 1e18,
                poolDebt:             6_954.480890971813258160 * 1e18,  // pending interest now equals current interest
                actualUtilization:    0.601778294656389596 * 1e18,
                targetUtilization:    0.769969644230769231 * 1e18,
                minDebtAmount:        695.448089097181325816 * 1e18,
                loans:                1,
                maxBorrower:          address(_borrower),
                interestRate:         0.05 * 1e18,
                interestRateUpdate:   _startTime
            })
        );
        (debtColEma, lupt0DebtEma, debtEma, depositEma) = _pool.emasInfo();
        assertEq(debtColEma,   8_059_788.606357480557372857 * 1e18);    // accumulator updated, no EMA change
        assertEq(lupt0DebtEma, 10_467_670.598117585349615039 * 1e18);   // accumulator updated, no EMA change
        assertEq(debtEma,      6_954.044264896858085302 * 1e18);        // accumulator updated, no EMA change
        assertEq(depositEma,   11_555.824340370334487364 * 1e18);       // still moving toward 10_000
        (uint256 interestRate, ) = _pool.interestRateInfo();
        assertEq(interestRate, 0.05 * 1e18);

        skip(9 hours);  // 12 hours since debt was drawn
        _pool.updateInterest();
        (debtColEma, lupt0DebtEma, debtEma, depositEma) = _pool.emasInfo();
        assertEq(debtColEma,   8_059_824.827133087800583978 * 1e18);    // updated for interest accrual
        assertEq(lupt0DebtEma, 10_467_670.598117585349615039 * 1e18);   // updated for interest accrual
        assertEq(debtEma,      6_954.221271554347056671 * 1e18);        // updated for interest accrual
        assertEq(depositEma,   10_925.255918947232279645 * 1e18);       // still moving toward 10_000
        (interestRate, ) = _pool.interestRateInfo();
        assertEq(interestRate, 0.05 * 1e18);

        skip(6 hours);

        // double the meaningful deposit
        _addLiquidityNoEventCheck({
            from:   _lender,
            amount: 10_000 * 1e18,
            index:  _i1505_26
        });

        _skipAndAccrue({
            time:   4 hours,
            mau:    0.552709628959737370 * 1e18,    // dropping from 60% to 35%
            tu:     0.769980648855063767 * 1e18,    // still at 77%
            rate:   0.05 * 1e18
        });
        (, , , depositEma) = _pool.emasInfo();
        assertEq(depositEma, 12_582.630574533185450994 * 1e18);         // now moving toward 20_000

        _skipAndAccrue({
            time:   20 hours,                       // 24 hours since liquidity was added
            mau:    0.393730664447534870 * 1e18,    // still dropping toward 35%
            tu:     0.769999034610545182 * 1e18,    // still at 77%
            rate:   0.045 * 1e18                    // first interest rate drop
        });
        (, , , depositEma) = _pool.emasInfo();
        assertEq(depositEma, 17_664.401438069534341122 * 1e18);         // still moving toward 20_000

        _skipAndAccrue({
            time:   2 days,                         // 3 days since liquidity was added
            mau:    0.350326278385275701 * 1e18,    // reached 35%
            tu:     0.770061298755197770 * 1e18,    // still at 77%
            rate:   0.0405 * 1e18                   // second interest rate drop
        });                  
        (, , , depositEma) = _pool.emasInfo();
        assertEq(depositEma, 19_855.678232854988936290 * 1e18);         // reached (sort of) 20_000
        _assertPool(
            PoolParams({
                htp:                  1_160.241132852523151748 * 1e18,
                lup:                  _p1505_26,
                poolSize:             25_003.260972741349848786 * 1e18, // reflects additional 10_000 deposit
                pledgedCollateral:    6 * 1e18,
                encumberedCollateral: 4.622276093514343199 * 1e18,
                poolDebt:             6_957.744546536839716358 * 1e18,
                actualUtilization:    0.350326278385275701 * 1e18,      // dropped to 35% as expected
                targetUtilization:    0.770061298755197770 * 1e18,
                minDebtAmount:        695.774454653683971636 * 1e18,
                loans:                1,
                maxBorrower:          address(_borrower),
                interestRate:         0.0405 * 1e18,                    // dropped twice
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
            mau:    0.438034189478303511 * 1e18,    // rising from 35% to 90%
            tu:     0.783712586574747919 * 1e18,    // increases as collateralization decreases
            rate:   0.0405 * 1e18
        });
        (, ,  debtEma, ) = _pool.emasInfo();
        assertEq(debtEma, 8_707.751377089437009807 * 1e18);             // increasing from 7_000 to 18_000

        _skipAndAccrue({
            time:   9 hours,
            mau:    0.625264252786034774 * 1e18,    // still rising to 90%
            tu:     0.817638199962595844 * 1e18,
            rate:   0.0405 * 1e18
        });
        (, ,  debtEma, ) = _pool.emasInfo();
        assertEq(debtEma, 12_461.239878735709484526 * 1e18);            // increasing from 7_000 to 18_000

        _skipAndAccrue({
            time:   4 days,
            mau:    0.897117712497350667 * 1e18,    // reached 90%
            tu:     0.947031347885781555 * 1e18,
            rate:   0.0405 * 1e18
        });
        (, ,  debtEma, ) = _pool.emasInfo();
        assertEq(debtEma, 17_945.800561906185304271 * 1e18);            // reached 18_000
        _assertPool(
            PoolParams({
                htp:                  1_499.486002669294859183 * 1e18,
                lup:                  _p1505_26,
                poolSize:             25_011.246566016078933954 * 1e18,
                pledgedCollateral:    12 * 1e18,                        // 6 additional NFTs deposited
                encumberedCollateral: 11.941618338706780744 * 1e18,     // all 12 NFTs are encumbered
                poolDebt:             17_975.284944476369220528 * 1e18, // includes new debt
                actualUtilization:    0.897117712497350667 * 1e18,
                targetUtilization:    0.947031347885781555 * 1e18,
                minDebtAmount:        1_797.528494447636922053 * 1e18,
                loans:                1,
                maxBorrower:          address(_borrower),
                interestRate:         0.0405 * 1e18,
                interestRateUpdate:   _startTime + 98 hours
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