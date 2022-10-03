// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.14;

import { ERC20HelperContract } from './ERC20DSTestPlus.sol';

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

    function testPoolInterestRateIncrease() external {
        Liquidity[] memory amounts = new Liquidity[](5);
        amounts[0] = Liquidity({amount: 10_000 * 1e18, index: 2550, newLup: BucketMath.MAX_PRICE});
        amounts[1] = Liquidity({amount: 20_000 * 1e18, index: 2551, newLup: BucketMath.MAX_PRICE});
        amounts[2] = Liquidity({amount: 20_000 * 1e18, index: 2552, newLup: BucketMath.MAX_PRICE});
        amounts[3] = Liquidity({amount: 50_000 * 1e18, index: 3900, newLup: BucketMath.MAX_PRICE});
        amounts[4] = Liquidity({amount: 10_000 * 1e18, index: 4200, newLup: BucketMath.MAX_PRICE});
        _addLiquidity(
            AddLiquiditySpecs({
                from:    _lender,
                amounts: amounts
            })
        );

        skip(10 days);

        _assertPool(
            PoolState({
                htp:                  0,
                lup:                  BucketMath.MAX_PRICE,
                poolSize:             110_000 * 1e18,
                pledgedCollateral:    0,
                encumberedCollateral: 0,
                borrowerDebt:         0,
                actualUtilization:    0,
                targetUtilization:    1e18,
                minDebtAmount:        0,
                loans:                0,
                maxBorrower:          address(0),
                interestRate:         0.05 * 1e18,
                interestRateUpdate:   _startTime
            })
        );

        // enforce EMA and target utilization update, increasing interest rate from 0.05 to 0.055
        changePrank(_borrower);
        _pool.pledgeCollateral(_borrower, 100 * 1e18);

        vm.expectEmit(true, true, false, true);
        emit UpdateInterestRate(0.05 * 1e18, 0.055 * 1e18);
        _pool.borrow(46_000 * 1e18, 4_300);

        _assertPool(
            PoolState({
                htp:                  460.442307692307692520 * 1e18,
                lup:                  2_981.007422784467321543 * 1e18,
                poolSize:             110_000 * 1e18,
                pledgedCollateral:    100 * 1e18,
                encumberedCollateral: 15.445862501819022598 * 1e18,
                borrowerDebt:         46_044.23076923076925200 * 1e18,
                actualUtilization:    0.920884615384615385 * 1e18,
                targetUtilization:    0.000000505854275034 * 1e18,
                minDebtAmount:        4_604.423076923076925200 * 1e18,
                loans:                1,
                maxBorrower:          _borrower,
                interestRate:         0.055 * 1e18,
                interestRateUpdate:   _startTime + 10 days
            })
        );
    }

    function testPoolInterestRateDecrease() external {
        // lender makes an initial deposit
        skip(1 hours);
        Liquidity[] memory amounts = new Liquidity[](1);
        amounts[0] = Liquidity({amount: 10_000 * 1e18, index: 2873, newLup: BucketMath.MAX_PRICE});
        _addLiquidity(
            AddLiquiditySpecs({
                from:    _lender,
                amounts: amounts
            })
        );
        // borrower draws debt
        skip(2 hours);
        _borrow(
            BorrowSpecs({
                from:         _borrower,
                borrower:     _borrower,
                pledgeAmount: 10 * 1e18,
                borrowAmount: 5_000 * 1e18,
                indexLimit:   3000,
                price:        601.252968524772188572 * 1e18
            })
        );
        _assertPool(
            PoolState({
                htp:                  500.480769230769231000 * 1e18,
                lup:                  601.252968524772188572 * 1e18,
                poolSize:             10_000 * 1e18,
                pledgedCollateral:    10 * 1e18,
                encumberedCollateral: 8.323963380317995918 * 1e18,
                borrowerDebt:         5_004.80769230769231 * 1e18,
                actualUtilization:    0.500480769230769231 * 1e18,
                targetUtilization:    1e18,
                minDebtAmount:        500.480769230769231 * 1e18,
                loans:                1,
                maxBorrower:          _borrower,
                interestRate:         0.05 * 1e18,
                interestRateUpdate:   _startTime
            })
        );

        // another lender provides liquidity, decresing interest rate from 0.05 to 0.045
        skip(12 hours);

        changePrank(_lender1);
        vm.expectEmit(true, true, false, true);
        emit UpdateInterestRate(0.05 * 1e18, 0.045 * 1e18);
        _pool.addQuoteToken(1_000 * 1e18, 2873);

        _assertPool(
            PoolState({
                htp:                  500.523620446054562664 * 1e18,
                lup:                  601.252968524772188572 * 1e18,
                poolSize:             11_000.377511961388180000 * 1e18,
                pledgedCollateral:    10 * 1e18,
                encumberedCollateral: 8.324676078924548679 * 1e18,
                borrowerDebt:         5_005.23620446054562664 * 1e18,
                actualUtilization:    0.455005857664252335 * 1e18,
                targetUtilization:    0.832467607892454868 * 1e18,
                minDebtAmount:        500.523620446054562664 * 1e18,
                loans:                1,
                maxBorrower:          _borrower,
                interestRate:         0.045 * 1e18,
                interestRateUpdate:   54000
            })
        );
    }

    function testPendingInflator() external {
        // add liquidity
        Liquidity[] memory amounts = new Liquidity[](3);
        amounts[0] = Liquidity({amount: 10_000 * 1e18, index: 2550, newLup: BucketMath.MAX_PRICE});
        amounts[1] = Liquidity({amount: 10_000 * 1e18, index: 2552, newLup: BucketMath.MAX_PRICE});
        amounts[2] = Liquidity({amount: 10_000 * 1e18, index: 4200, newLup: BucketMath.MAX_PRICE});
        _addLiquidity(
            AddLiquiditySpecs({
                from:    _lender,
                amounts: amounts
            })
        );

        skip(3600);

        // draw debt
        _borrow(
            BorrowSpecs({
                from:         _borrower,
                borrower:     _borrower,
                pledgeAmount: 50 * 1e18,
                borrowAmount: 15_000 * 1e18,
                indexLimit:   4300,
                price:        2_981.007422784467321543 * 1e18
            })
        );
        _assertPool(
            PoolState({
                htp:                  300.288461538461538600 * 1e18,
                lup:                  2_981.007422784467321543 * 1e18,
                poolSize:             30_000 * 1e18,
                pledgedCollateral:    50 * 1e18,
                encumberedCollateral: 5.036694294071420412 * 1e18,
                borrowerDebt:         15_014.423076923076930000 * 1e18,
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
                encumberedCollateral: 5.036694294071420412 * 1e18,
                borrowerDebt:         15_014.423076923076930000 * 1e18,
                actualUtilization:    0.750721153846153847 * 1e18,
                targetUtilization:    1e18,
                minDebtAmount:        1_501.442307692307693000 * 1e18,
                loans:                1,
                maxBorrower:          _borrower,
                interestRate:         0.05 * 1e18,
                interestRateUpdate:   _startTime
            })
        );
    }

    function testPoolEMAAndTargetUtilizationUpdate() external {

        // add initial quote to the pool
        Liquidity[] memory amounts = new Liquidity[](2);
        amounts[0] = Liquidity({amount: 10_000 * 1e18, index: 3_010, newLup: BucketMath.MAX_PRICE});
        amounts[1] = Liquidity({amount: 10_000 * 1e18, index: 2_995, newLup: BucketMath.MAX_PRICE});
        _addLiquidity(
            AddLiquiditySpecs({
                from:    _lender,
                amounts: amounts
            })
        );

        _assertPool(
            PoolState({
                htp:                  0,
                lup:                  BucketMath.MAX_PRICE,
                poolSize:             20_000 * 1e18,
                pledgedCollateral:    0,
                encumberedCollateral: 0,
                borrowerDebt:         0,
                actualUtilization:    0,
                targetUtilization:    1e18,
                minDebtAmount:        0,
                loans:                0,
                maxBorrower:          address(0),
                interestRate:         0.05 * 1e18,
                interestRateUpdate:   _startTime
            })
        );
        assertEq(_pool.debtEma(),   0);
        assertEq(_pool.lupColEma(), 0);

        // borrower 1 borrows 500 quote from the pool
        _borrow(
            BorrowSpecs({
                from:         _borrower,
                borrower:     _borrower,
                pledgeAmount: 50 * 1e18,
                borrowAmount: 500 * 1e18,
                indexLimit:   3_010,
                price:        327.188250324085203338 * 1e18
            })
        );

        _assertPool(
            PoolState({
                htp:                  10.009615384615384620 * 1e18,
                lup:                  327.188250324085203338 * 1e18,
                poolSize:             20_000 * 1e18,
                pledgedCollateral:    50 * 1e18,
                encumberedCollateral: 1.529641632103338099 * 1e18,
                borrowerDebt:         500.480769230769231000 * 1e18,
                actualUtilization:    0.025024038461538462 * 1e18,
                targetUtilization:    1e18,
                minDebtAmount:        50.048076923076923100 * 1e18,
                loans:                1,
                maxBorrower:          address(_borrower),
                interestRate:         0.05 * 1e18,
                interestRateUpdate:   _startTime
            })
        );
        assertEq(_pool.debtEma(),   0);
        assertEq(_pool.lupColEma(), 0);

        _borrow(
            BorrowSpecs({
                from:         _borrower2,
                borrower:     _borrower2,
                pledgeAmount: 50 * 1e18,
                borrowAmount: 500 * 1e18,
                indexLimit:   3_010,
                price:        327.188250324085203338 * 1e18
            })
        ); 

        _assertPool(
            PoolState({
                htp:                  10.009615384615384620 * 1e18,
                lup:                  327.188250324085203338 * 1e18,
                poolSize:             20_000 * 1e18,
                pledgedCollateral:    100 * 1e18,
                encumberedCollateral: 3.059283264206676197 * 1e18,
                borrowerDebt:         1000.961538461538462000 * 1e18,
                actualUtilization:    0.050048076923076923 * 1e18,
                targetUtilization:    1e18,
                minDebtAmount:        50.048076923076923100 * 1e18,
                loans:                2,
                maxBorrower:          address(_borrower),
                interestRate:         0.05 * 1e18,
                interestRateUpdate:   _startTime
            })
        );
        assertEq(_pool.debtEma(),   0);
        assertEq(_pool.lupColEma(), 0);

        skip(10 days);

        // borrower 1 borrows 500 quote from the pool
        _borrow(
            BorrowSpecs({
                from:         _borrower,
                borrower:     _borrower,
                pledgeAmount: 0,
                borrowAmount: 10 * 1e18,
                indexLimit:   3_010,
                price:        327.188250324085203338 * 1e18
            })
        );

        _assertPool(
            PoolState({
                htp:                  10.223528890139451939 * 1e18,
                lup:                  327.188250324085203338 * 1e18,
                poolSize:             20_001.169794343035540000 * 1e18,
                pledgedCollateral:    100 * 1e18,
                encumberedCollateral: 3.094069767562214045 * 1e18,
                borrowerDebt:         1012.343273629329809307 * 1e18,
                actualUtilization:    0.050614203271033305 * 1e18,
                targetUtilization:    0.030940697675622140 * 1e18,
                minDebtAmount:        50.617163681466490465 * 1e18,
                loans:                2,
                maxBorrower:          address(_borrower),
                interestRate:         0.05 * 1e18,
                interestRateUpdate:   _startTime
            })
        );
        assertEq(_pool.debtEma(),   95.440014344854493304 * 1e18);
        assertEq(_pool.lupColEma(), 3_084.610933645840358918 * 1e18);
    }

}
