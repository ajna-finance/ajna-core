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
        _mintCollateralAndApproveTokens(_borrower2, 1_000 * 1e18);

        _mintQuoteAndApproveTokens(_lender,   200_000 * 1e18);
        _mintQuoteAndApproveTokens(_lender1,  200_000 * 1e18);
    }

    function testPoolInterestRateIncrease() external {
        Liquidity[] memory amounts = new Liquidity[](5);
        amounts[0] = Liquidity({amount: 2_000 * 1e18, index: _i9_91, newLup: BucketMath.MAX_PRICE});
        amounts[1] = Liquidity({amount: 5_000 * 1e18, index: _i9_81, newLup: BucketMath.MAX_PRICE});
        amounts[2] = Liquidity({amount: 11_000 * 1e18, index: _i9_72, newLup: BucketMath.MAX_PRICE});
        amounts[3] = Liquidity({amount: 25_000 * 1e18, index: _i9_62, newLup: BucketMath.MAX_PRICE});
        amounts[4] = Liquidity({amount: 30_000 * 1e18, index: _i9_52, newLup: BucketMath.MAX_PRICE});
        _addLiquidity(
            AddLiquiditySpecs({
                from:    _lender,
                amounts: amounts
            })
        );
        vm.stopPrank();

        // Borrower adds collateral token and borrows
        vm.startPrank(_borrower);
        _collateral.approve(address(_pool), 20 * 1e18);
        _pool.pledgeCollateral(_borrower, 2 * 1e18);
        _pool.borrow(19.25 * 1e18, _i9_91);
        vm.stopPrank();

        // Borrower2 adds collateral token and borrows
        vm.startPrank(_borrower2);
        _collateral.approve(address(_pool), 50 * 1e18);
        _pool.pledgeCollateral(_borrower2, 20 * 1e18);
        _pool.borrow(50 * 1e18, _i9_72);
        vm.stopPrank();

        _assertPool(
            PoolState({
                htp:                  9.634254807692307697 * 1e18,
                lup:                  _p9_91,
                poolSize:             73_000 * 1e18,
                pledgedCollateral:    22.0 * 1e18,
                encumberedCollateral: 6.989542660822895832 * 1e18,
                borrowerDebt:         69.316586538461538494 * 1e18,
                actualUtilization:    0.000949542281348788 * 1e18,
                targetUtilization:    1e18,
                minDebtAmount:        3.465829326923076925* 1e18,
                loans:                2,
                maxBorrower:          address(_borrower),
                inflatorSnapshot:     1e18,
                pendingInflator:      1e18,
                interestRate:         0.05 * 1e18,
                interestRateUpdate:   0
            })
        );

        _assertBorrower(
            BorrowerState({
               borrower:          _borrower,
               debt:              19.268509615384615394 * 1e18,
               pendingDebt:       19.268509615384615394 * 1e18,
               collateral:        2e18,
               collateralization: 1.029367090801636643 * 1e18,
               mompFactor:        9.917184843435912074 * 1e18,
               inflator:          1e18
            })
        );

        skip(100 days);

        // Pool wasn't touched, nothing changes.
        _assertPool(
            PoolState({
                htp:                  9.634254807692307697 * 1e18,
                lup:                  _p9_91,
                poolSize:             73_000 * 1e18,
                pledgedCollateral:    22.0 * 1e18,
                encumberedCollateral: 6.989542660822895832 * 1e18,
                borrowerDebt:         69.316586538461538494 * 1e18,
                actualUtilization:    0.000949542281348788 * 1e18,
                targetUtilization:    1e18,
                minDebtAmount:        3.465829326923076925 * 1e18,
                loans:                2,
                maxBorrower:          address(_borrower),
                inflatorSnapshot:     1 * 1e18,
                pendingInflator:      1.013792886272348689 * 1e18,
                interestRate:         0.05 * 1e18,
                interestRateUpdate:   0
            })
        );

        _assertBorrower(
            BorrowerState({
               borrower:          _borrower,
               debt:              19.268509615384615394 * 1e18,
               pendingDebt:       19.534277977147272573 * 1e18,
               collateral:        2e18,
               collateralization: 1.029367090801636643 * 1e18,
               mompFactor:        9.917184843435912074 * 1e18,
               inflator:          1 * 1e18
            })
        );

        // Borrower2 borrows to accumulate interest / debt
        vm.startPrank(_borrower);
        _pool.repay(_borrower, 1 * 1e18);
        vm.stopPrank();

        _assertPool(
            PoolState({
                htp:                  9.267138988573636287 * 1e18,
                lup:                  _p9_91,
                poolSize:             73_000.812709831769829000 * 1e18,
                pledgedCollateral:    22.0 * 1e18,
                encumberedCollateral: 6.985113560651726096 * 1e18,
                borrowerDebt:         69.272662333373954580 * 1e18,
                actualUtilization:    0.000948930015460558 * 1e18,
                targetUtilization:    0.317505161847805732 * 1e18,
                minDebtAmount:        3.463633116668697729 * 1e18,
                loans:                2,
                maxBorrower:          address(_borrower), // TODO: this is incorrect
                inflatorSnapshot:     1.013792886272348689 * 1e18,
                pendingInflator:      1.013792886272348689 * 1e18,
                interestRate:         0.045 * 1e18,
                interestRateUpdate:   block.timestamp
            })
        );

        _assertBorrower(
            BorrowerState({
               borrower:          _borrower,
               debt:              18.534277977147272573 * 1e18,
               pendingDebt:       18.534277977147272573 * 1e18,
               collateral:        2e18,
               collateralization: 1.070145257955425188 * 1e18,
               mompFactor:        9.782259254058058749 * 1e18,
               inflator:          1.013792886272348689 * 1e18
            })
        );
    }


    function testPoolInterestRateIncreaseDecrease() external {
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

        skip(864000);

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
                inflatorSnapshot:     1e18,
                pendingInflator:      1.001370801704613834 * 1e18,
                interestRate:         0.05 * 1e18,
                interestRateUpdate:   0
            })
        );
        // enforce EMA and target utilization update
        _borrow(
            BorrowSpecs({
                from:         _borrower,
                borrower:     _borrower,
                pledgeAmount: 100 * 1e18,
                borrowAmount: 46_000 * 1e18,
                indexLimit:   4300,
                price:        2_981.007422784467321543 * 1e18
            })
        );
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
                inflatorSnapshot:     1e18,
                pendingInflator:      1.001507985182953253 * 1e18,
                interestRate:         0.055 * 1e18,
                interestRateUpdate:   864000
            })
        );

        // repay entire loan
        deal(address(_quote), _borrower,  _quote.balanceOf(_borrower) + 200 * 1e18);
        _repay(
            RepaySpecs({
                from:        _borrower,
                borrower:    _borrower,
                repayAmount: 46_113.664786991249514684 * 1e18,
                price:       BucketMath.MAX_PRICE
            })
        );

        skip(864000);

        // enforce EMA and target utilization update
        amounts = new Liquidity[](1);
        amounts[0] = Liquidity({amount: 100 * 1e18, index: 5, newLup: BucketMath.MAX_PRICE});
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
                poolSize:             110_164.962888730221500000 * 1e18,
                pledgedCollateral:    100 * 1e18,
                encumberedCollateral: 0,
                borrowerDebt:         0,
                actualUtilization:    0,
                targetUtilization:    0.000000227963980381 * 1e18,
                minDebtAmount:        0,
                loans:                0,
                maxBorrower:          address(0),
                inflatorSnapshot:     1.001507985182953253 * 1e18,
                pendingInflator:      1.003018244385218513 * 1e18,
                interestRate:         0.055 * 1e18, // FIXME here it should decrease
                interestRateUpdate:   864000
            })
        );
        _assertBorrower(
            BorrowerState({
                borrower:          _borrower,
                debt:              0,
                pendingDebt:       0,
                collateral:        100 * 1e18,
                collateralization: 1e18,
                mompFactor:        0 * 1e18,
                inflator:          1.001507985182953253 * 1e18
            })
        );

        assertEq(_poolUtils.lenderInterestMargin(address(_pool)), 0.85 * 1e18);
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
                inflatorSnapshot:     1e18,
                pendingInflator:      1.000005707778846384 * 1e18,
                interestRate:         0.05 * 1e18,
                interestRateUpdate:   0
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
                inflatorSnapshot:     1e18,
                pendingInflator:      1.000011415590271509 * 1e18,
                interestRate:         0.05 * 1e18,
                interestRateUpdate:   0
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
                inflatorSnapshot:     1e18,
                pendingInflator:      1e18,
                interestRate:         0.05 * 1e18,
                interestRateUpdate:   0
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
                inflatorSnapshot:     1e18,
                pendingInflator:      1e18,
                interestRate:         0.05 * 1e18,
                interestRateUpdate:   0
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
                inflatorSnapshot:     1e18,
                pendingInflator:      1e18,
                interestRate:         0.05 * 1e18,
                interestRateUpdate:   0
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
                inflatorSnapshot:     1.001370801704613834 * 1e18,
                pendingInflator:      1.001370801704613834 * 1e18,
                interestRate:         0.05 * 1e18,
                interestRateUpdate:   864000
            })
        );
        assertEq(_pool.debtEma(),   95.440014344854493304 * 1e18);
        assertEq(_pool.lupColEma(), 3_084.610933645840358918 * 1e18);
    }

}
