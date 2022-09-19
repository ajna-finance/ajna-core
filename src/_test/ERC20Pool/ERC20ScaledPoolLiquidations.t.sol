// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.14;

import { ERC20Pool }        from "../../erc20/ERC20Pool.sol";
import { ERC20PoolFactory } from "../../erc20/ERC20PoolFactory.sol";

import { Maths } from "../../libraries/Maths.sol";
import { BucketMath } from "../../libraries/BucketMath.sol";

import { ERC20HelperContract } from "./ERC20DSTestPlus.sol";


contract ERC20PoolKickSuccessTest is ERC20HelperContract {

    address internal _borrower;
    address internal _borrower2;
    address internal _lender;

    //uint256 HPB        = 1987;  // _p49910
    //uint256 HPB_PRICE  =  _p49910;
    //uint256 LEND_PRICE = 2309;  // _p10016
    //uint256 START      = block.timestamp;


    uint256 HPB;
    uint256 HPB_PRICE;
    uint256 LEND_PRICE;
    uint256 START; 



    function setUp() external {

        _borrower  = makeAddr("borrower");
        _borrower2 = makeAddr("borrower2");
        _lender    = makeAddr("lender");

        _mintQuoteAndApproveTokens(_lender, 120_000 * 1e18);
        _mintCollateralAndApproveTokens(_borrower,  2 * 1e18);
        _mintCollateralAndApproveTokens(_borrower2, 1_000 * 1e18);
    }


    function testKick() external {

        // Lender adds quote token in two price buckets
        vm.startPrank(_lender);
        _pool.addQuoteToken(10_000e18, _i49910);
        _pool.addQuoteToken(11_000e18, _i10016);
        vm.stopPrank();

        _mintCollateralAndApproveTokens(_borrower,  1 * 1e18);
        _mintCollateralAndApproveTokens(_borrower2, 1 * 1e18);

        // Borrower adds collateral token and borrows at HPB
        vm.startPrank(_borrower);
        _collateral.approve(address(_pool), 10_000e18);
        _pool.pledgeCollateral(_borrower, 1e18);
        _pool.borrow(10_000e18, _i49910);
        vm.stopPrank();

        // Borrower adds collateral token and borrows at LEND_PRICE
        vm.startPrank(_borrower2);
        _collateral.approve(address(_pool), 10_000e18);
        _pool.pledgeCollateral(_borrower2, 1e18);
        _pool.borrow(10_000e18, _i10016);
        vm.stopPrank();

        // Warp to make borrower undercollateralized
        vm.warp(START + 15 days);


        /**********************/
        /*** Pre-kick state ***/
        /**********************/
        _assertBorrower(
            BorrowerState({
               borrower: _borrower2,
               debt: 10_009.615384615384620000 * 1e18,
               pendingDebt:  10_030.204233142901661009 * 1e18,
               collateral:  1e18,
               collateralization:  1.000687958968713934 * 1e18,
               mompFactor: 10_016.501589292607751220 * 1e18,
               inflator:     1e18
            })
        );

        _assertAuction(
            AuctionState({
                borrower: _borrower2,
                kickTime: 0,
                referencePrice: 0,
                bondFactor: 0,
                bondSize: 0,
                next: address(0),
                active: true
            })
        );


        /************/
        /*** Kick ***/
        /************/
        vm.startPrank(_lender);
        _pool.kick(_borrower2, address(0));


        /**********************/
        /*** Post-kick state ***/
        /**********************/        
        _assertBorrower(
            BorrowerState({
               borrower: _borrower2,
               debt: 10_009.615384615384620000 * 1e18,
               pendingDebt:  10_009.615384615384620000 * 1e18,
               collateral:  1e18,
               collateralization:  1.000687958968713934 * 1e18,
               mompFactor: 10_016.501589292607751220 * 1e18,
               inflator:     1e18
            })
        );

        _assertAuction(
            AuctionState({
                borrower: _borrower2,
                kickTime: block.timestamp,
                referencePrice: 49_910.043670274810022205 * 1e18,
                bondFactor: 0.01 * 1e18,
                bondSize: 100.302042331429016610 * 1e18,
                next: address(0),
                active: true
            })
        );


    }

    function testTakeUsingQuoteTokenOutsidePool() external {

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
        _pool.borrow(19.75 * 1e18, _i9_91);
        vm.stopPrank();

        // Borrower2 adds collateral token and borrows
        vm.startPrank(_borrower2);
        _collateral.approve(address(_pool), 7_980 * 1e18);
        _pool.pledgeCollateral(_borrower2, 1_000 * 1e18);
        _pool.borrow(7_980 * 1e18, _i9_72);
        vm.stopPrank();

        // Warp to make borrower undercollateralized
        vm.warp(START + 10 days);

        _assertBorrower(
            BorrowerState({
               borrower: _borrower,
               debt: 19.768990384615384625 * 1e18,
               pendingDebt:  19.796089750333109888 * 1e18,
               collateral:  2e18,
               collateralization:  0.983489361459458484 * 1e18,
               mompFactor: 9.917184843435912074 * 1e18,
               inflator:     1e18
            })
        );

        //TODO: assert lender state


        vm.startPrank(_lender);
        _pool.kick(_borrower, address(0));
        vm.stopPrank();

        //TODO: assert lender state

        _assertBorrower(
            BorrowerState({
               borrower: _borrower,
               debt: 19.768990384615384625 * 1e18,
               pendingDebt:  19.768990384615384625 * 1e18,
               collateral:  2 * 1e18,
               collateralization:  0.983489361459458484 * 1e18,
               mompFactor: 9.917184843435912074 * 1e18,
               inflator:     1e18
            })
        );

        _assertAuction(
            AuctionState({
                borrower: _borrower,
                kickTime: block.timestamp,
                referencePrice: 9.917184843435912074 * 1e18,
                bondFactor: 0.01 * 1e18,
                bondSize: 0.197960897503331099 * 1e18,
                next: address(0),
                active: true
            })
        );

        skip(2 hours);
 
        bytes memory data = new bytes(0);
        vm.startPrank(_lender);
        _pool.take(_borrower, 20e18, data);
        vm.stopPrank();

        //TODO: assert lender state

        _assertBorrower(
            BorrowerState({
               borrower: _borrower,
               debt: 0,
               pendingDebt:  0,
               collateral:  1.604720683481066499 * 1e18,
               collateralization:  1e18,
               mompFactor: 9.917184843435912074 * 1e18,
               inflator:  1e18
            })
        );

        _assertAuction(
            AuctionState({
                borrower: _borrower,
                kickTime: (block.timestamp - 2 hours),
                referencePrice: 9.917184843435912074 * 1e18,
                bondFactor: 0.01 * 1e18,
                bondSize: 0.197960897503331099 * 1e18,
                next: address(0),
                active: false
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
