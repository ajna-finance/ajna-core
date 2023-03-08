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

        _mintAndApproveQuoteTokens(_lender,  15_000 * 1e18);
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
        assertEq(debtColEma,   8_059_788.606357480557372857 * 1e18);  // 7_000^2 / 6         ~=  8_166_666.66
        assertEq(lupt0DebtEma, 10_467_670.598117585349615039 * 1e18); // 1_505.26 * 6_954.04 ~= 10_467_638.25
        assertEq(debtEma,      6_954.044264896858085302 * 1e18);      // current debt with origination fee
        assertEq(depositEma,   11_850.197375262816985000 * 1e18);     // moving toward 15_000
    }

    function testEMAAdjustmentTime() external {
        skip(3 hours);  // 11 hours passed since liquidity added

        // since pool was not touched since debt was drawn, debt EMAs should remain unchanged
        _assertPool(
            PoolParams({
                htp:                  1_159.007377482809680884 * 1e18,
                lup:                  _p1505_26,
                poolSize:             15_000 * 1e18,
                pledgedCollateral:    6 * 1e18,
                encumberedCollateral: 4.620107931548236591 * 1e18,      // small increase due to interest accrual
                poolDebt:             6_954.480890971813258160 * 1e18,  // small increase due to interest accrual
                actualUtilization:    0.586829404159407881 * 1e18,
                targetUtilization:    0.769969644230769231 * 1e18,
                minDebtAmount:        695.448089097181325816 * 1e18,    // small increase due to interest accrual
                loans:                1,
                maxBorrower:          address(_borrower),
                interestRate:         0.05 * 1e18,
                interestRateUpdate:   _startTime
            })
        );
        (uint256 debtColEma, uint256 lupt0DebtEma, uint256 debtEma, uint256 depositEma) = _pool.emasInfo();
        assertEq(debtColEma,   8_059_788.606357480557372857 * 1e18);
        assertEq(lupt0DebtEma, 10_467_670.598117585349615039 * 1e18);
        assertEq(debtEma,      6_954.044264896858085302 * 1e18);
        assertEq(depositEma,   11_850.197375262816985000 * 1e18);
    }

    // (, , uint256 mau, uint256 tu) = _poolUtils.poolUtilizationInfo(address(_pool));
}