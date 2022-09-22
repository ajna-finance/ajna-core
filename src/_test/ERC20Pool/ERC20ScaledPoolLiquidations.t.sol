// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.14;

import { ERC20Pool }        from "../../erc20/ERC20Pool.sol";
import { ERC20PoolFactory } from "../../erc20/ERC20PoolFactory.sol";

import { IScaledPool } from "../../base/interfaces/IScaledPool.sol";

import { Maths } from "../../libraries/Maths.sol";
import { BucketMath } from "../../libraries/BucketMath.sol";

import { ERC20HelperContract } from "./ERC20DSTestPlus.sol";


contract ERC20PoolKickSuccessTest is ERC20HelperContract {

    address internal _borrower;
    address internal _borrower2;
    address internal _lender;

    function setUp() external {

        _borrower  = makeAddr("borrower");
        _borrower2 = makeAddr("borrower2");
        _lender    = makeAddr("lender");

        _mintQuoteAndApproveTokens(_lender, 120_000 * 1e18);
        _mintCollateralAndApproveTokens(_borrower,  2 * 1e18);
        _mintCollateralAndApproveTokens(_borrower2, 1_000 * 1e18);

        // Lender adds Quote token accross 5 prices
        vm.startPrank(_lender);
        _pool.addQuoteToken(2_000 * 1e18,  _i9_91);
        _pool.addQuoteToken(5_000 * 1e18,  _i9_81);
        _pool.addQuoteToken(11_000 * 1e18, _i9_72);
        _pool.addQuoteToken(25_000 * 1e18, _i9_62);
        _pool.addQuoteToken(30_000 * 1e18, _i9_52);
        vm.stopPrank();

        // Borrower adds collateral token and borrows
        vm.startPrank(_borrower);
        _collateral.approve(address(_pool), 20 * 1e18);
        _pool.pledgeCollateral(_borrower, 2 * 1e18);
        _pool.borrow(19.25 * 1e18, _i9_91);
        vm.stopPrank();

        // Borrower2 adds collateral token and borrows
        vm.startPrank(_borrower2);
        _collateral.approve(address(_pool), 7_980 * 1e18);
        _pool.pledgeCollateral(_borrower2, 1_000 * 1e18);
        _pool.borrow(7_980 * 1e18, _i9_72);
        vm.stopPrank();


        /**********************/
        /*** Pre-kick state ***/
        /**********************/

        _assertPool(
            PoolState({
                htp:                  9.634254807692307697 * 1e18,
                lup:                  _p9_72,
                poolSize:             73_000 * 1e18,
                pledgedCollateral:    1_002.0 * 1e18,
                encumberedCollateral: 823.649613971736296163 * 1e18,
                borrowerDebt:         8_006.941586538461542154 * 1e18,
                actualUtilization:    0.109684131322444679 * 1e18,
                targetUtilization:    1e18,
                minDebtAmount:        400.347079326923077108 * 1e18,
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
               collateralization: 1.009034539679184679 * 1e18,
               mompFactor:        9.917184843435912074 * 1e18,
               inflator:          1e18
            })
        );

         _assertAuction(
            AuctionState({
                borrower:       _borrower,
                kickTime:       0,
                price:          0,
                bpf:            0,
                referencePrice: 0,
                bondFactor:     0,
                bondSize:       0,
                next:           address(0),
                active:         false
            })
        );


    }


    function testKick() external {

        // Skip to make borrower undercollateralized
        skip(100 days);

        /************/
        /*** Kick ***/
        /************/
        vm.startPrank(_lender);
        _pool.kick(_borrower);
        vm.stopPrank();

        /**********************/
        /*** Post-kick state ***/
        /**********************/        
        _assertPool(
            PoolState({
                htp:                  8.097846143253778448 * 1e18,
                lup:                  _p9_72,
                poolSize:             73_099.394951223217762000 * 1e18,
                pledgedCollateral:    1_002.0 * 1e18,
                encumberedCollateral: 835.010119425512354679 * 1e18,
                borrowerDebt:         8_117.380421230925720814 * 1e18,
                actualUtilization:    0.111045794929593908 * 1e18,
                targetUtilization:    0.833343432560391572 * 1e18,
                minDebtAmount:        811.738042123092572081 * 1e18,
                loans:                1,
                maxBorrower:          address(_borrower2),
                inflatorSnapshot:     1.013792886272348689 * 1e18,
                pendingInflator:      1.013792886272348689 * 1e18,
                interestRate:         0.045 * 1e18,
                interestRateUpdate:   block.timestamp
            })
        );

        _assertBorrower(
            BorrowerState({
               borrower:          _borrower,
               debt:              19.268509615384615394 * 1e18,
               pendingDebt:       19.268509615384615394 * 1e18,
               collateral:        2e18,
               collateralization: 1.009034539679184679 * 1e18,
               mompFactor:        9.917184843435912074 * 1e18,
               inflator:          1e18
            })
        );

        _assertAuction(
            AuctionState({
                borrower:       _borrower,
                kickTime:       block.timestamp,
                price:          99.171848434359120740 * 1e18,
                bpf:            int256(-0.01 * 1e18),
                referencePrice: 9.917184843435912074 * 1e18,
                bondFactor:     0.01 * 1e18,
                bondSize:       0.195342779771472726 * 1e18,
                next:           address(0),
                active:         true
            })
        );


    }

    function testTakeGTNeutral() external {

        //TODO: assert lender state
        // Skip to make borrower undercollateralized
        skip(100 days);


        vm.startPrank(_lender);
        _pool.kick(_borrower);
        vm.stopPrank();

        //TODO: assert lender state

        _assertPool(
            PoolState({
                htp:                  8.097846143253778448 * 1e18,
                lup:                  _p9_72,
                poolSize:             73_099.394951223217762000 * 1e18,
                pledgedCollateral:    1_002.0 * 1e18,
                encumberedCollateral: 835.010119425512354679 * 1e18,
                borrowerDebt:         8_117.380421230925720814 * 1e18,
                actualUtilization:    0.111045794929593908 * 1e18,
                targetUtilization:    0.833343432560391572 * 1e18,
                minDebtAmount:        811.738042123092572081 * 1e18,
                loans:                1,
                maxBorrower:          address(_borrower2),
                inflatorSnapshot:     1.013792886272348689 * 1e18,
                pendingInflator:      1.013792886272348689 * 1e18,
                interestRate:         0.045 * 1e18,
                interestRateUpdate:   block.timestamp
            })
        );

        _assertBorrower(
            BorrowerState({
               borrower:          _borrower,
               debt:              19.268509615384615394 * 1e18,
               pendingDebt:       19.268509615384615394 * 1e18,
               collateral:        2 * 1e18,
               collateralization: 1.009034539679184679 * 1e18,
               mompFactor:        9.917184843435912074 * 1e18,
               inflator:          1e18
            })
        );

        _assertAuction(
            AuctionState({
                borrower: _borrower,
                kickTime:       block.timestamp,
                price:          99.171848434359120740 * 1e18,
                bpf:            int256(-0.01 * 1e18),
                referencePrice: 9.917184843435912074 * 1e18,
                bondFactor:     0.01 * 1e18,
                bondSize:       0.195342779771472726 * 1e18,
                next:           address(0),
                active:         true
            })
        );

        skip(2 hours);
 
        bytes memory data = new bytes(0);
        vm.startPrank(_lender);
        _pool.take(_borrower, 20e18, data);
        vm.stopPrank();


        _assertPool(
            PoolState({
                htp:                  8.097929340730578998 * 1e18,
                lup:                  _p9_72,
                poolSize:             73_099.470009578439232996 * 1e18,
                pledgedCollateral:    1_002.0 * 1e18,
                encumberedCollateral: 835.018698340672036186 * 1e18,
                borrowerDebt:         8_117.463819403393991095 * 1e18,
                actualUtilization:    0.111046821794190009 * 1e18,
                targetUtilization:    0.833343432560391572 * 1e18,
                minDebtAmount:        811.746381940339399110 * 1e18,
                loans:                1,
                maxBorrower:          address(_borrower2),
                inflatorSnapshot:     1.013803302006192493 * 1e18,
                pendingInflator:      1.013803302006192493 * 1e18,
                interestRate:         0.045 * 1e18,
                interestRateUpdate:   block.timestamp - 2 hours
            })
        );

        //TODO: assert lender state

        _assertBorrower(
            BorrowerState({
               borrower:          _borrower,
               debt:              0,
               pendingDebt:       0,
               collateral:        1.609948421891363734 * 1e18,
               collateralization: 1e18,
               mompFactor:        9.917184843435912074 * 1e18,
               inflator:          1e18
            })
        );

        _assertAuction(
            AuctionState({
                borrower:       _borrower,
                kickTime:       (block.timestamp - 2 hours),
                price:          49.585924217179560370 * 1e18,
                bpf:            int256(-0.01 * 1e18),
                referencePrice: 9.917184843435912074 * 1e18,
                bondFactor:     0.01 * 1e18,
                bondSize:       0.001932099842611407 * 1e18,
                next:           address(0),
                active:         false
            })
        );
        
    }

    function testTakeLTNeutral() external {
        

        // Skip to make borrower undercollateralized
        skip(100 days);

        //TODO: assert lender state

        vm.startPrank(_lender);
        _pool.kick(_borrower);
        vm.stopPrank();

        //TODO: assert lender state

        _assertPool(
            PoolState({
                htp:                  8.097846143253778448 * 1e18,
                lup:                  _p9_72,
                poolSize:             73_099.394951223217762000 * 1e18,
                pledgedCollateral:    1_002.0 * 1e18,
                encumberedCollateral: 835.010119425512354679 * 1e18,
                borrowerDebt:         8_117.380421230925720814 * 1e18,
                actualUtilization:    0.111045794929593908 * 1e18,
                targetUtilization:    0.833343432560391572 * 1e18,
                minDebtAmount:        811.738042123092572081 * 1e18,
                loans:                1,
                maxBorrower:          address(_borrower2),
                inflatorSnapshot:     1.013792886272348689 * 1e18,
                pendingInflator:      1.013792886272348689 * 1e18,
                interestRate:         0.045 * 1e18,
                interestRateUpdate:   block.timestamp
            })
        );

        _assertBorrower(
            BorrowerState({
               borrower:          _borrower,
               debt:              19.268509615384615394 * 1e18,
               pendingDebt:       19.268509615384615394 * 1e18,
               collateral:        2 * 1e18,
               collateralization: 1.009034539679184679 * 1e18,
               mompFactor:        9.917184843435912074 * 1e18,
               inflator:          1e18
            })
        );

        _assertAuction(
            AuctionState({
                borrower: _borrower,
                kickTime:       block.timestamp,
                price:          99.171848434359120740 * 1e18,
                bpf:            int256(-0.01 * 1e18),
                referencePrice: 9.917184843435912074 * 1e18,
                bondFactor:     0.01 * 1e18,
                bondSize:       0.195342779771472726 * 1e18,
                next:           address(0),
                active:         true
            })
        );

        skip(5 hours);
 
        bytes memory data = new bytes(0);
        vm.startPrank(_lender);
        _pool.take(_borrower, 20e18, data);
        vm.stopPrank();

        //TODO: assert lender state
        _assertPool(
            PoolState({
                htp:                  8.098054138548481935 * 1e18,
                lup:                  _p9_72,
                poolSize:             73_099.582598557182807882 * 1e18,
                pledgedCollateral:    1_002.0 * 1e18,
                encumberedCollateral: 835.031566878674328063 * 1e18,
                borrowerDebt:         8_117.588918268664675439 * 1e18,
                actualUtilization:    0.111048362106911499 * 1e18,
                targetUtilization:    0.833343432560391572 * 1e18,
                minDebtAmount:        811.758891826866467544 * 1e18,
                loans:                1,
                maxBorrower:          address(_borrower2),
                inflatorSnapshot:     1.013818925807605133 * 1e18,
                pendingInflator:      1.013818925807605133 * 1e18,
                interestRate:         0.045 * 1e18,
                interestRateUpdate:   block.timestamp - 5 hours
            })
        );

        _assertBorrower(
            BorrowerState({
               borrower:          _borrower,
               debt:              7.262263476430800312 * 1e18,
               pendingDebt:       7.262263476430800312 * 1e18,
               collateral:        0,
               collateralization: 1e18,
               mompFactor:        9.917184843435912074 * 1e18,
               inflator:          1e18
            })
        );

        _assertAuction(
            AuctionState({
                borrower:       _borrower,
                kickTime:       (block.timestamp - 5 hours),
                price:          6.198240527147445050 * 1e18,
                bpf:            0,
                referencePrice: 9.917184843435912074 * 1e18,
                bondFactor:     0.01 * 1e18,
                bondSize:       0.319307590314421627 * 1e18,
                next:           address(0),
                active:         false
            })
        );
        
    }        


    function testBondFactorFormula() external {
        // threshold price (100) greater than the pool price (50)
        // min(0.3, max(0.01, 1 - 2)) = min(0.3, max(0.01, -1)) = min(0.3, 0.01) = 0.01
        assertEq(_bondFactorFormula(100 * 1e18, 50 * 1e18), 0.01 * 1e18);

        // threshold price (100) equals pool price (100)
        // min(0.3, max(0.01, 1 - 1)) = min(0.3, max(0.01, 0)) = min(0.3, 0.01) = 0.01
        assertEq(_bondFactorFormula(100 * 1e18, 50 * 1e18), 0.01 * 1e18);

        // threshold price (100) less than pool price (110)
        // min(0.3, max(0.01, 1 - 0.909090909)) = min(0.3, max(0.01, 0.090909091)) = min(0.3, 0.090909091) = 0.090909091
        assertEq(_bondFactorFormula(100 * 1e18, 110 * 1e18), 0.090909090909090909 * 1e18);

        // threshold price 80, pool price 100
        // min(0.3, max(0.01, 1 - 0.8)) = min(0.3, max(0.01, 0.2)) = min(0.3, 0.2) = 0.2
        assertEq(_bondFactorFormula(80 * 1e18, 100 * 1e18), 0.2 * 1e18);

        // threshold price 30, pool price 100
        // min(0.3, max(0.01, 1 - 0.3)) = min(0.3, max(0.01, 0.7)) = min(0.3, 0.7) = 0.3
        assertEq(_bondFactorFormula(30 * 1e18, 100 * 1e18), 0.3 * 1e18);
    }

    function _bondFactorFormula(uint256 thresholdPrice_, uint256 poolPrice_) internal pure returns (uint256 bondFactor_) {
        bondFactor_= thresholdPrice_ >= poolPrice_ ? 0.01 * 1e18 : Maths.min(0.3 * 1e18, Maths.max(0.01 * 1e18, 1 * 1e18 - Maths.wdiv(thresholdPrice_, poolPrice_)));
    }


    function testAuctionPrice() external {
        skip(6238);
        uint256 referencePrice = 8_678.5 * 1e18;
        uint256 kickTime = block.timestamp;
        assertEq(_pool.auctionPrice(referencePrice, kickTime), 86_785.0 * 1e18);
        skip(1444); // price should not change in the first hour
        assertEq(_pool.auctionPrice(referencePrice, kickTime), 86_785.0 * 1e18);

        skip(5756);     // 2 hours
        assertEq(_pool.auctionPrice(referencePrice, kickTime), 43_392.5 * 1e18);
        skip(2394);     // 2 hours, 39 minutes, 54 seconds
        assertEq(_pool.auctionPrice(referencePrice, kickTime), 27_367.159606354998613290 * 1e18);
        skip(2586);     // 3 hours, 23 minutes
        assertEq(_pool.auctionPrice(referencePrice, kickTime), 16_633.737549018910661740 * 1e18);
        skip(3);        // 3 seconds later
        assertEq(_pool.auctionPrice(referencePrice, kickTime), 16_624.132299820494703920 * 1e18);
        skip(20153);    // 8 hours, 35 minutes, 53 seconds
        assertEq(_pool.auctionPrice(referencePrice, kickTime), 343.207165783609045700 * 1e18);
        skip(97264);    // 36 hours
        assertEq(_pool.auctionPrice(referencePrice, kickTime), 0.00000252577588655 * 1e18);
        skip(129600);   // 72 hours
        assertEq(_pool.auctionPrice(referencePrice, kickTime), 0);
    }

    // TODO: move to DSTestPlus?
    function _logBorrowerInfo(address borrower_) internal {
        (
            uint256 borrowerDebt,
            uint256 borrowerPendingDebt,
            uint256 collateralDeposited,
            uint256 mompFactor,
            uint256 borrowerInflator

        ) = _pool.borrowerInfo(address(borrower_));

        emit log_named_uint("borrowerDebt        ", borrowerDebt);
        emit log_named_uint("borrowerPendingDebt ", borrowerPendingDebt);
        emit log_named_uint("collateralDeposited ", collateralDeposited);
        emit log_named_uint("mompFactor ",           mompFactor);
        emit log_named_uint("collateralEncumbered", _pool.encumberedCollateral(borrowerDebt, _pool.lup()));
        emit log_named_uint("collateralization   ", _pool.borrowerCollateralization(borrowerDebt, collateralDeposited, _pool.lup()));
        emit log_named_uint("borrowerInflator    ", borrowerInflator);
    }
}
