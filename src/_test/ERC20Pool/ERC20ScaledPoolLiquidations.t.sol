// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.14;

import { ERC20Pool }        from "../../erc20/ERC20Pool.sol";
import { ERC20PoolFactory } from "../../erc20/ERC20PoolFactory.sol";

import { Maths } from "../../libraries/Maths.sol";

import { ERC20HelperContract } from "./ERC20DSTestPlus.sol";

contract ERC20PoolKickSuccessTest is ERC20HelperContract {

    address internal _borrower;
    address internal _borrower2;
    address internal _lender;

    uint256 HPB        = 1987;  // _p49910
    uint256 LEND_PRICE = 2309;  // _p10016
    uint256 START      = block.timestamp;

    function setUp() external {
        _borrower  = makeAddr("borrower");
        _borrower2 = makeAddr("borrower2");
        _lender    = makeAddr("lender");

        _mintQuoteAndApproveTokens(_lender, 21_000 * 1e18);

        // Lender adds quote token in two price buckets
        vm.startPrank(_lender);
        _pool.addQuoteToken(10_000e18, HPB);
        _pool.addQuoteToken(11_000e18, LEND_PRICE);
        vm.stopPrank();

        _mintCollateralAndApproveTokens(_borrower,  1 * 1e18);
        _mintCollateralAndApproveTokens(_borrower2, 1 * 1e18);

        // Borrower adds collateral token and borrows at HPB
        vm.startPrank(_borrower);
        _collateral.approve(address(_pool), 10_000e18);
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
    }

    function test_liquidate() external {

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

        ( uint256 kickTime, uint256 referencePrice, uint256 remainingCollateral, uint256 remainingDebt ) = _pool.liquidations(_borrower2);

        assertEq(kickTime,            0);
        assertEq(referencePrice,      0);
        assertEq(remainingCollateral, 0);

        /************/
        /*** Kick ***/
        /************/

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

        assertEq(borrowerDebt,         10_030.204233142901661009 * 1e18);  // Updated to reflect debt
        assertEq(borrowerPendingDebt,  10_030.204233142901661009 * 1e18);  // Pending debt is unchanged
        assertEq(collateralDeposited,  1e18);                              // Unchanged
        assertEq(_pool.encumberedCollateral(borrowerDebt, _pool.lup()), 1.001368006956135433 * 1e18);  // Unencumbered collateral is unchanged because based off pending debt
        assertEq(_pool.borrowerCollateralization(borrowerDebt, collateralDeposited, _pool.lup()), 0.998633861930247030 * 1e18);  // Unchanged because based off pending debt
        assertEq(borrowerInflator,     1.002056907057504104 * 1e18);       // Inflator is updated to reflect new debt

        ( kickTime, referencePrice, remainingCollateral, remainingDebt ) = _pool.liquidations(_borrower2);

        assertEq(kickTime,            block.timestamp);
        assertEq(referencePrice,      HPB);
        assertEq(remainingCollateral, 1e18);
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
