// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.14;

import { ERC20Pool }        from "../../erc20/ERC20Pool.sol";
import { ERC20PoolFactory } from "../../erc20/ERC20PoolFactory.sol";

import { BucketMath } from "../../libraries/BucketMath.sol";

import { ERC20HelperContract } from "./ERC20DSTestPlus.sol";

contract ERC20ScaledInterestRateTest is ERC20HelperContract {

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

    function testScaledPoolInterestRateIncreaseDecrease() external {
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

        // enforce rate update - decrease
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
                poolSize:             110_162.490615984432250000 * 1e18,
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
                inflator:          1.001507985182953253 * 1e18
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

}
