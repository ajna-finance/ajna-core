// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.14;

import { ERC20Pool }        from "../../erc20/ERC20Pool.sol";
import { ERC20PoolFactory } from "../../erc20/ERC20PoolFactory.sol";

import { Maths } from "../../libraries/Maths.sol";
import { BucketMath } from "../../libraries/BucketMath.sol";

import { ERC20HelperContract } from "./ERC20DSTestPlus.sol";


import "@std/console.sol";

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
        HPB        = _pool.priceToIndex(_p10016);
        HPB_PRICE  =  _p10016;
        LEND_PRICE = _pool.priceToIndex(_p100);
        START      = block.timestamp;

        _borrower  = makeAddr("borrower");
        _borrower2 = makeAddr("borrower2");
        _lender    = makeAddr("lender");

        _mintQuoteAndApproveTokens(_lender, 120_000 * 1e18);
        _mintCollateralAndApproveTokens(_borrower,  510 * 1e18);
        _mintCollateralAndApproveTokens(_borrower2, 2_000 * 1e18);

        // Lender adds quote token in two price buckets
    //    vm.startPrank(_lender);
    //    _pool.addQuoteToken(10_000e18, HPB);
    //    _pool.addQuoteToken(11_000e18, LEND_PRICE);
    //    vm.stopPrank();

    //    // Borrower adds collateral token and borrows at HPB
    //    vm.startPrank(_borrower);
    //    _collateral.approve(address(_pool), 10_000e18);
    //    _pool.pledgeCollateral(_borrower, 1e18);
    //    _pool.borrow(10_000e18, HPB);
    //    vm.stopPrank();

    //    // Borrower adds collateral token and borrows at LEND_PRICE
    //    vm.startPrank(_borrower2);
    //    _collateral.approve(address(_pool), 10_000e18);
    //    _pool.pledgeCollateral(_borrower2, 1e18);
    //    _pool.borrow(10_000e18, LEND_PRICE);
    //    vm.stopPrank();

    //    // Warp to make borrower undercollateralized
    //    vm.warp(START + 15 days);
    }


    function testKick() external {

        // Lender adds quote token in two price buckets
        vm.startPrank(_lender);
        _pool.addQuoteToken(10_000e18, HPB);
        _pool.addQuoteToken(11_000e18, LEND_PRICE);
        vm.stopPrank();

        _mintCollateralAndApproveTokens(_borrower,  460 * 1e18);
        _mintCollateralAndApproveTokens(_borrower2, 50 * 1e18);

        // Borrower adds collateral token and borrows at HPB
        vm.startPrank(_borrower);
        _collateral.approve(address(_pool), 50_000e18);
        _pool.pledgeCollateral(_borrower, 1e18);
        _pool.borrow(10_000e18, HPB);
        vm.stopPrank();

        // Borrower adds collateral token and borrows at LEND_PRICE
        vm.startPrank(_borrower2);
        _collateral.approve(address(_pool), 10_000e18);
        _pool.pledgeCollateral(_borrower2, 1e18);
        _pool.borrow(10_000e18, LEND_PRICE);
        vm.stopPrank();

        // Warp to make borrower undercollateralized
        vm.warp(START + 15 days);

        /**********************/
        /*** Pre-kick state ***/
        /**********************/

        (
            uint256 borrowerDebt,
            uint256 borrowerPendingDebt,
            uint256 collateralDeposited,
            uint256 borrowerInflator
        ) = _pool.borrowerInfo(_borrower2);

        assertEq(borrowerDebt,         10_009.615384615384620000 * 1e18);
        assertEq(borrowerPendingDebt,  10_030.204233142901661009 * 1e18);
        assertEq(_pool.encumberedCollateral(borrowerPendingDebt, _pool.lup()), 1.001368006956135433 * 1e18);
        assertEq(_pool.borrowerCollateralization(borrowerPendingDebt, collateralDeposited, _pool.lup()), 0.998633861930247030 * 1e18);
        assertEq(borrowerInflator,     1e18);

        (uint256 kickTime, uint256 referencePrice, uint256 remainingCollateral, uint256 remainingDebt, uint256 bondFactor, uint256 bondSize) = _pool.liquidations(_borrower2);

        assertEq(kickTime,            0);
        assertEq(referencePrice,      0);
        assertEq(remainingCollateral, 0);

        /************/
        /*** Kick ***/
        /************/
        vm.startPrank(_lender);
        _pool.kick(_borrower2);

        /***********************/
        /*** Post-kick state ***/
        /***********************/
        (
            borrowerDebt,
            borrowerPendingDebt,
            collateralDeposited,
            borrowerInflator
        ) = _pool.borrowerInfo(_borrower2);

        assertEq(borrowerDebt,         0);  // Updated to reflect debt
        assertEq(borrowerPendingDebt,  0);  // Pending debt is unchanged
        assertEq(collateralDeposited,  0);                              // Unchanged
        assertEq(_pool.encumberedCollateral(borrowerDebt, _pool.lup()), 0);  // Unencumbered collateral is unchanged because based off pending debt
        assertEq(_pool.borrowerCollateralization(borrowerDebt, collateralDeposited, _pool.lup()), 1 * 1e18);  // Unchanged because based off pending debt
        assertEq(borrowerInflator,   0);       // Inflator is updated to reflect new debt

        (kickTime, referencePrice, remainingCollateral, remainingDebt, bondFactor, bondSize) = _pool.liquidations(_borrower2);
        assertEq(kickTime,            block.timestamp);
        assertEq(referencePrice,      HPB_PRICE);
        assertEq(remainingCollateral, 1e18);
        assertEq(remainingDebt, 10_030.204233142901661009 * 1e18);
        assertEq(bondSize, 100.302042331429016610 * 1e18);

        skip(2 hours);
        /************/
        /*** Take ***/
        /************/
        
        bytes memory data = new bytes(0);
        _pool.take(_borrower2, 1e18, data);

    }

    function testGregTakeUsingQuoteTokenOutsidePool() external {

        // Lender adds quote token in two price buckets
        vm.startPrank(_lender);
        _pool.addQuoteToken(50_000e18, _i10016);
        _pool.addQuoteToken(51_000e18, _i100);
        vm.stopPrank();

        // Borrower2 adds collateral token and borrows at HPB
        vm.startPrank(_borrower2);
        _collateral.approve(address(_pool), 10_000e18);
        _pool.pledgeCollateral(_borrower2, 50 * 1e18);
        _pool.borrow(10_000e18, _i10016);
        vm.stopPrank();

        // Borrower adds collateral token and borrows 50K
        vm.startPrank(_borrower);
        _collateral.approve(address(_pool), 50_000e18);
        _pool.pledgeCollateral(_borrower, 500e18);
        _pool.borrow(50_000e18, _i100);
        vm.stopPrank();

        // Warp to make borrower undercollateralized
        vm.warp(START + 15 days);

        // Borrower adds collateral token and borrows at LEND_PRICE

        (
            uint256 borrowerDebt,
            uint256 borrowerPendingDebt,
            uint256 borrowerCollateral,
            uint256 borrowerInflator
        ) = _pool.borrowerInfo(_borrower);

        uint256 poolPrice = _pool.borrowerDebt() * Maths.WAD / _pool.pledgedCollateral();
        uint256 thresholdPrice = borrowerDebt * Maths.WAD / borrowerCollateral;
        int256 neutralPrice = int(Maths.wmul(thresholdPrice, Maths.wdiv(_pool.poolPriceEma(), _pool.lupEma())));

        //60K debt / 500 collateral = 120 PP
        assertEq(poolPrice, 120.324290034754058326e18);
        assertEq(thresholdPrice, 110.105769230758220243e18);
        assertEq(neutralPrice,   1.091600755592511982e18);

        //assertEq(_pool.lup(), 10_016.501589292607751220e18);
        //console.log(_pool.lup());
        //console.log(thresholdPrice);
        //console.log(_pool.borrowerCollateralization(borrowerDebt, borrowerCollateral, _pool.lup()));

        /////************/
        /////*** Kick ***/
        /////************/
        //vm.startPrank(_lender);
        //_pool.kick(_borrower);

        /////***********************/
        /////*** Post-kick state ***/
        /////***********************/
        //(
        //    borrowerDebt,
        //    borrowerPendingDebt,
        //    borrowerCollateral,
        //    borrowerInflator
        //) = _pool.borrowerInfo(_borrower2);

        //assertEq(borrowerDebt,         0);  // Updated to reflect debt
        //assertEq(borrowerPendingDebt,  0);  // Pending debt is unchanged
        //assertEq(borrowerCollateral,  0);                              // Unchanged
        //assertEq(_pool.encumberedCollateral(borrowerDebt, _pool.lup()), 0);  // Unencumbered collateral is unchanged because based off pending debt
        //assertEq(_pool.borrowerCollateralization(borrowerDebt, borrowerCollateral, _pool.lup()), 1 * 1e18);  // Unchanged because based off pending debt
        //assertEq(borrowerInflator,   0);       // Inflator is updated to reflect new debt

        //(
        //    uint256 kickTime,
        //    uint256 referencePrice,
        //    uint256 remainingCollateral,
        //    uint256 remainingDebt,
        //    uint256 bondFactor,
        //    uint256 bondSize
        //) = _pool.liquidations(_borrower2);

        //assertEq(kickTime,            block.timestamp);
        //assertEq(referencePrice,      HPB_PRICE);
        //assertEq(remainingCollateral, 1e18);
        //assertEq(remainingDebt, 10_030.204233142901661009 * 1e18);
        //assertEq(bondSize, 100.302042331429016610 * 1e18);


        /**********************/
        /*** Pre-kick state ***/
        /**********************/

        //(
        //    uint256 borrowerDebt,
        //    uint256 borrowerPendingDebt,
        //    uint256 collateralDeposited,
        //    uint256 borrowerInflator
        //) = _pool.borrowerInfo(_borrower2);

        //assertEq(borrowerDebt,         10_009.615384615384620000 * 1e18);
        //assertEq(borrowerPendingDebt,  10_030.204233142901661009 * 1e18);
        //assertEq(_pool.encumberedCollateral(borrowerPendingDebt, _pool.lup()), 1.001368006956135433 * 1e18);
        //assertEq(_pool.borrowerCollateralization(borrowerPendingDebt, collateralDeposited, _pool.lup()), 0.998633861930247030 * 1e18);
        //assertEq(borrowerInflator,     1e18);

        //(uint256 kickTime, uint256 referencePrice, uint256 remainingCollateral, uint256 remainingDebt, uint256 bondFactor, uint256 bondSize) = _pool.liquidations(_borrower2);

        //assertEq(kickTime,            0);
        //assertEq(referencePrice,      0);
        //assertEq(remainingCollateral, 0);

        ///************/
        ///*** Kick ***/
        ///************/
        //vm.startPrank(_lender);
        //_pool.kick(_borrower2);

        ///***********************/
        ///*** Post-kick state ***/
        ///***********************/
        //(
        //    borrowerDebt,
        //    borrowerPendingDebt,
        //    collateralDeposited,
        //    borrowerInflator
        //) = _pool.borrowerInfo(_borrower2);

        //assertEq(borrowerDebt,         0);  // Updated to reflect debt
        //assertEq(borrowerPendingDebt,  0);  // Pending debt is unchanged
        //assertEq(collateralDeposited,  0);                              // Unchanged
        //assertEq(_pool.encumberedCollateral(borrowerDebt, _pool.lup()), 0);  // Unencumbered collateral is unchanged because based off pending debt
        //assertEq(_pool.borrowerCollateralization(borrowerDebt, collateralDeposited, _pool.lup()), 1 * 1e18);  // Unchanged because based off pending debt
        //assertEq(borrowerInflator,   0);       // Inflator is updated to reflect new debt

        //(kickTime, referencePrice, remainingCollateral, remainingDebt, bondFactor, bondSize) = _pool.liquidations(_borrower2);
        //assertEq(kickTime,            block.timestamp);
        //assertEq(referencePrice,      HPB_PRICE);
        //assertEq(remainingCollateral, 1e18);
        //assertEq(remainingDebt, 10_030.204233142901661009 * 1e18);
        //assertEq(bondSize, 100.302042331429016610 * 1e18);

        //skip(2 hours);
        ///************/
        ///*** Take ***/
        ///************/
        
        //bytes memory data = new bytes(0);
        //_pool.take(_borrower2, 1e18, data);

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

        (
            uint256 borrowerDebt,
            uint256 borrowerPendingDebt,
            uint256 borrowerCollateral,
            uint256 borrowerInflator
        ) = _pool.borrowerInfo(_borrower);

        uint256 poolPrice = _pool.borrowerDebt() * Maths.WAD / _pool.pledgedCollateral();
        uint256 thresholdPrice = borrowerDebt * Maths.WAD / borrowerCollateral;

        vm.startPrank(_lender);
        _pool.kick(_borrower);

        skip(2 hours);
 
        bytes memory data = new bytes(0);
        _pool.take(_borrower, 2e18, data);
        
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


    // TODO: move to DSTestPlus?
    function _logBorrowerInfo(address borrower_) internal {
        (
            uint256 borrowerDebt,
            uint256 borrowerPendingDebt,
            uint256 collateralDeposited,
            uint256 borrowerInflator

        ) = _pool.borrowerInfo(address(borrower_));

        emit log_named_uint("borrowerDebt        ", borrowerDebt);
        emit log_named_uint("borrowerPendingDebt ", borrowerPendingDebt);
        emit log_named_uint("collateralDeposited ", collateralDeposited);
        emit log_named_uint("collateralEncumbered", _pool.encumberedCollateral(borrowerDebt, _pool.lup()));
        emit log_named_uint("collateralization   ", _pool.borrowerCollateralization(borrowerDebt, collateralDeposited, _pool.lup()));
        emit log_named_uint("borrowerInflator    ", borrowerInflator);
    }
}
