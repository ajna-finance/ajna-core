// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.14;

import { ERC721Pool }        from "../../erc721/ERC721Pool.sol";
import { ERC721PoolFactory } from "../../erc721/ERC721PoolFactory.sol";

import { IScaledPool } from "../../base/interfaces/IScaledPool.sol";

import { Maths } from "../../libraries/Maths.sol";
import { BucketMath } from "../../libraries/BucketMath.sol";

import { ERC721HelperContract } from "./ERC721DSTestPlus.sol";

import "@std/console.sol";


contract ERC721PoolKickSuccessTest is ERC721HelperContract {

    address internal _borrower;
    address internal _borrower2;
    address internal _lender;

    function setUp() external {

        _borrower  = makeAddr("borrower");
        _borrower2 = makeAddr("borrower2");
        _lender    = makeAddr("lender");

        // deploy subset pool
        uint256[] memory subsetTokenIds = new uint256[](6);
        subsetTokenIds[0] = 1;
        subsetTokenIds[1] = 3;
        subsetTokenIds[2] = 5;
        subsetTokenIds[3] = 51;
        subsetTokenIds[4] = 53;
        subsetTokenIds[5] = 73;
        _subsetPool = _deploySubsetPool(subsetTokenIds);

        address[] memory _poolAddresses = new address[](1);
        _poolAddresses[0] = address(_subsetPool);

       _mintAndApproveQuoteTokens(_poolAddresses, _lender, 120_000 * 1e18);
       _mintAndApproveQuoteTokens(_poolAddresses, _borrower, 100 * 1e18);
       _mintAndApproveQuoteTokens(_poolAddresses, _borrower2, 8_000 * 1e18);

       _mintAndApproveCollateralTokens(_poolAddresses, _borrower, 6);
       _mintAndApproveCollateralTokens(_poolAddresses, _borrower2, 74);

       vm.prank(_borrower);
       _quote.approve(address(_subsetPool), 200_000 * 1e18);
       vm.stopPrank();

       vm.prank(_borrower2);
       _quote.approve(address(_subsetPool), 200_000 * 1e18);
       vm.stopPrank();

       // Lender adds Quote token accross 5 prices
       vm.startPrank(_lender);
       _subsetPool.addQuoteToken(2_000 * 1e18,  _i9_91);
       _subsetPool.addQuoteToken(5_000 * 1e18,  _i9_81);
       _subsetPool.addQuoteToken(11_000 * 1e18, _i9_72);
       _subsetPool.addQuoteToken(25_000 * 1e18, _i9_62);
       _subsetPool.addQuoteToken(30_000 * 1e18, _i9_52);
       vm.stopPrank();

       // Borrower adds collateral token and borrows
       vm.startPrank(_borrower);
       uint256[] memory tokenIdsToAdd = new uint256[](2);
       tokenIdsToAdd[0] = 1;
       tokenIdsToAdd[1] = 3;
       _subsetPool.pledgeCollateral(_borrower, tokenIdsToAdd);
       _subsetPool.borrow(19.8 * 1e18, _i9_91);
       vm.stopPrank();
        

       // Borrower2 adds collateral token and borrows
       vm.startPrank(_borrower2);
       tokenIdsToAdd = new uint256[](3);
       tokenIdsToAdd[0] = 51;
       tokenIdsToAdd[1] = 53;
       tokenIdsToAdd[2] = 73;
       _subsetPool.pledgeCollateral(_borrower2, tokenIdsToAdd);
       _subsetPool.borrow(15 * 1e18, _i9_72);
       vm.stopPrank();

       ///**********************/
       ///*** Pre-kick state ***/
       ///**********************/

       _assertPool(
           PoolState({
               htp:                  9.909519230769230774 * 1e18,
               lup:                  _p9_91,
               poolSize:             73_000 * 1e18,
               pledgedCollateral:    5.0 * 1e18,
               encumberedCollateral: 3.512434434608473285 * 1e18,
               borrowerDebt:         34.833461538461538478 * 1e18,
               actualUtilization:    0.000477170706006322 * 1e18,
               targetUtilization:    1e18,
               minDebtAmount:        1.741673076923076924 * 1e18,
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
              debt:              19.819038461538461548 * 1e18,
              pendingDebt:       19.819038461538461548 * 1e18,
              collateral:        2e18,
              collateralization: 1.000773560501591181 * 1e18,
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


    function testSubsetKick() external {

        // Skip to make borrower undercollateralized
        skip(100 days);

        /************/
        /*** Kick ***/
        /************/
        vm.startPrank(_lender);
        _subsetPool.kick(_borrower);
        vm.stopPrank();

        /**********************/
        /*** Post-kick state ***/
        /**********************/        
        _assertPool(
            PoolState({
                htp:                  5.073838435622668201 * 1e18,
                lup:                  _p9_91,
                poolSize:             73_000.0 * 1e18,
                pledgedCollateral:    5.0 * 1e18,
                encumberedCollateral: 3.560881043304109325 * 1e18,
                borrowerDebt:         35.313915511933770677 * 1e18,
                actualUtilization:    0.000483752267286764 * 1e18,
                targetUtilization:    0.712176208660821865 * 1e18,
                minDebtAmount:        3.531391551193377068 * 1e18,
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
               debt:              19.819038461538461548 * 1e18,
               pendingDebt:       19.819038461538461548 * 1e18,
               collateral:        2e18,
               collateralization: 1.000773560501591181 * 1e18,
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
                bondSize:       0.200924002050657661 * 1e18,
                next:           address(0),
                active:         true
            })
        );
    }

    function testSubsetTakeGTNeutral() external {

        //TODO: assert lender state
        // Skip to make borrower undercollateralized
        skip(100 days);


        vm.startPrank(_lender);
        _subsetPool.kick(_borrower);
        vm.stopPrank();

        //TODO: assert lender state

        _assertPool(
            PoolState({
                htp:                  5.073838435622668201 * 1e18,
                lup:                  _p9_91,
                poolSize:             73_000.0 * 1e18,
                pledgedCollateral:    5.0 * 1e18,
                encumberedCollateral: 3.560881043304109325 * 1e18,
                borrowerDebt:         35.313915511933770677 * 1e18,
                actualUtilization:    0.000483752267286764 * 1e18,
                targetUtilization:    0.712176208660821865 * 1e18,
                minDebtAmount:        3.531391551193377068 * 1e18,
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
               debt:              19.819038461538461548 * 1e18,
               pendingDebt:       19.819038461538461548 * 1e18,
               collateral:        2 * 1e18,
               collateralization: 1.000773560501591181 * 1e18,
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
                bondSize:       0.200924002050657661 * 1e18,
                next:           address(0),
                active:         true
            })
        );

        skip(2 hours);
 
        bytes memory data = new bytes(0);
        // vm.startPrank(_lender);
        // _subsetPool.take(_borrower, 20e18, data);
        // vm.stopPrank();


        // _assertPool(
        //    PoolState({
        //        htp:                  8.097929340730578998 * 1e18,
        //        lup:                  _p9_72,
        //        poolSize:             73_099.470009578439232996 * 1e18,
        //        pledgedCollateral:    1_002.0 * 1e18,
        //        encumberedCollateral: 835.018698340672036186 * 1e18,
        //        borrowerDebt:         8_117.463819403393991095 * 1e18,
        //        actualUtilization:    0.111046821794190009 * 1e18,
        //        targetUtilization:    0.833343432560391572 * 1e18,
        //        minDebtAmount:        811.746381940339399110 * 1e18,
        //        loans:                1,
        //        maxBorrower:          address(_borrower2),
        //        inflatorSnapshot:     1.013803302006192493 * 1e18,
        //        pendingInflator:      1.013803302006192493 * 1e18,
        //        interestRate:         0.045 * 1e18,
        //        interestRateUpdate:   block.timestamp - 2 hours
        //    })
        // );

        // //TODO: assert lender state

        // _assertBorrower(
        //    BorrowerState({
        //       borrower:          _borrower,
        //       debt:              0,
        //       pendingDebt:       0,
        //       collateral:        1.609948421891363734 * 1e18,
        //       collateralization: 1e18,
        //       mompFactor:        9.917184843435912074 * 1e18,
        //       inflator:          1e18
        //    })
        // );

//         //_assertAuction(
//         //    AuctionState({
//         //        borrower:       _borrower,
//         //        kickTime:       (block.timestamp - 2 hours),
//         //        price:          49.585924217179560370 * 1e18,
//         //        bpf:            int256(-0.01 * 1e18),
//         //        referencePrice: 9.917184843435912074 * 1e18,
//         //        bondFactor:     0.01 * 1e18,
//         //        bondSize:       0.001932099842611407 * 1e18,
//         //        next:           address(0),
//         //        active:         false
//         //    })
//         //);
        
//    }

//     function testTakeLTNeutralCollection() external {
        

//         // Skip to make borrower undercollateralized
//         skip(100 days);

//         //TODO: assert lender state

//         vm.startPrank(_lender);
//         _subsetPool.kick(_borrower);
//         vm.stopPrank();

//         //TODO: assert lender state

//         _assertPool(
//             PoolState({
//                 htp:                  8.097846143253778448 * 1e18,
//                 lup:                  _p9_72,
//                 poolSize:             73_099.394951223217762000 * 1e18,
//                 pledgedCollateral:    1_002.0 * 1e18,
//                 encumberedCollateral: 835.010119425512354679 * 1e18,
//                 borrowerDebt:         8_117.380421230925720814 * 1e18,
//                 actualUtilization:    0.111045794929593908 * 1e18,
//                 targetUtilization:    0.833343432560391572 * 1e18,
//                 minDebtAmount:        811.738042123092572081 * 1e18,
//                 loans:                1,
//                 maxBorrower:          address(_borrower2),
//                 inflatorSnapshot:     1.013792886272348689 * 1e18,
//                 pendingInflator:      1.013792886272348689 * 1e18,
//                 interestRate:         0.045 * 1e18,
//                 interestRateUpdate:   block.timestamp
//             })
//         );

//         _assertBorrower(
//             BorrowerState({
//                borrower:          _borrower,
//                debt:              19.268509615384615394 * 1e18,
//                pendingDebt:       19.268509615384615394 * 1e18,
//                collateral:        2 * 1e18,
//                collateralization: 1.009034539679184679 * 1e18,
//                mompFactor:        9.917184843435912074 * 1e18,
//                inflator:          1e18
//             })
//         );

//         _assertAuction(
//             AuctionState({
//                 borrower: _borrower,
//                 kickTime:       block.timestamp,
//                 price:          99.171848434359120740 * 1e18,
//                 bpf:            int256(-0.01 * 1e18),
//                 referencePrice: 9.917184843435912074 * 1e18,
//                 bondFactor:     0.01 * 1e18,
//                 bondSize:       0.195342779771472726 * 1e18,
//                 next:           address(0),
//                 active:         true
//             })
//         );

//         skip(5 hours);
 
//         bytes memory data = new bytes(0);
//         //vm.startPrank(_lender);
//         //_subsetPool.take(_borrower, 20e18, data);
//         //vm.stopPrank();

//         ////TODO: assert lender state
//         //_assertPool(
//         //    PoolState({
//         //        htp:                  8.098054138548481935 * 1e18,
//         //        lup:                  _p9_72,
//         //        poolSize:             73_099.582598557182807882 * 1e18,
//         //        pledgedCollateral:    1_002.0 * 1e18,
//         //        encumberedCollateral: 835.031566878674328063 * 1e18,
//         //        borrowerDebt:         8_117.588918268664675439 * 1e18,
//         //        actualUtilization:    0.111048362106911499 * 1e18,
//         //        targetUtilization:    0.833343432560391572 * 1e18,
//         //        minDebtAmount:        811.758891826866467544 * 1e18,
//         //        loans:                1,
//         //        maxBorrower:          address(_borrower2),
//         //        inflatorSnapshot:     1.013818925807605133 * 1e18,
//         //        pendingInflator:      1.013818925807605133 * 1e18,
//         //        interestRate:         0.045 * 1e18,
//         //        interestRateUpdate:   block.timestamp - 5 hours
//         //    })
//         //);

//         //_assertBorrower(
//         //    BorrowerState({
//         //       borrower:          _borrower,
//         //       debt:              7.262263476430800312 * 1e18,
//         //       pendingDebt:       7.262263476430800312 * 1e18,
//         //       collateral:        0,
//         //       collateralization: 1e18,
//         //       mompFactor:        9.917184843435912074 * 1e18,
//         //       inflator:          1e18
//         //    })
//         //);

//         //_assertAuction(
//         //    AuctionState({
//         //        borrower:       _borrower,
//         //        kickTime:       (block.timestamp - 5 hours),
//         //        price:          6.198240527147445050 * 1e18,
//         //        bpf:            0,
//         //        referencePrice: 9.917184843435912074 * 1e18,
//         //        bondFactor:     0.01 * 1e18,
//         //        bondSize:       0.319307590314421627 * 1e18,
//         //        next:           address(0),
//         //        active:         false
//         //    })
//         //);
        
     }        

}