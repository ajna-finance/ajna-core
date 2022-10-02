// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.14;

import { ERC20HelperContract } from './ERC20DSTestPlus.sol';

import '../../erc20/ERC20Pool.sol';
import '../../erc20/ERC20PoolFactory.sol';

import '../../libraries/Actors.sol';
import '../../libraries/Maths.sol';
import '../../libraries/PoolUtils.sol';

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

        _mintCollateralAndApproveTokens(_borrower,  1 * 1e18);
        _mintCollateralAndApproveTokens(_borrower2, 1 * 1e18);

        // Lender adds quote token in two price buckets
        _addLiquidity(
            {
                from:   _lender,
                amount: 10_000 * 1e18,
                index:  HPB,
                newLup: BucketMath.MAX_PRICE
            }
        );
        _addLiquidity(
            {
                from:   _lender,
                amount: 11_000 * 1e18,
                index:  LEND_PRICE,
                newLup: BucketMath.MAX_PRICE
            }
        );

        // Borrower adds collateral token and borrows at HPB
        _pledgeCollateral(
            {
                from:     _borrower,
                borrower: _borrower,
                amount:   1e18
            }
        );
        _borrow(
            {
                from:       _borrower,
                amount:     10_000 * 1e18,
                indexLimit: HPB,
                newLup:     49_910.043670274810022205 * 1e18
            }
        );

        // Borrower adds collateral token and borrows at LEND_PRICE
        _pledgeCollateral(
            {
                from:     _borrower2,
                borrower: _borrower2,
                amount:   1e18
            }
        );
        _borrow(
            {
                from:       _borrower2,
                amount:     10_000e18,
                indexLimit: LEND_PRICE,
                newLup:     10_016.501589292607751220 * 1e18
            }
        );

    }

    function test_liquidate() external {

        // Warp to make borrower undercollateralized
        vm.warp(START + 15 days);
        /**********************/
        /*** Pre-kick state ***/
        /**********************/

        _assertBorrower(
            {
                borrower:                  _borrower2,
                borrowerDebt:              10_009.615384615384620000 * 1e18,
                borrowerCollateral:        1 * 1e18,
                borrowerMompFactor:        10_016.501589292607751220 * 1e18,
                borrowerInflator:          1 * 1e18,
                borrowerCollateralization: 1.000687958968713934 * 1e18,
                borrowerPendingDebt:       10_030.204233142901661009 * 1e18
            }
        );
        assertEq(PoolUtils.encumberance(10_030.204233142901661009 * 1e18, _lup()), 1.001368006956135433 * 1e18);

        ( uint256 kickTime, uint256 referencePrice, uint256 remainingCollateral, uint256 remainingDebt ) = ERC20Pool(address(_pool)).liquidations(_borrower2);

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

        _assertBorrower(
            {
                borrower:                  _borrower2,
                borrowerDebt:              10_030.204233142901661009 * 1e18, // Updated to reflect debt
                borrowerCollateral:        1 * 1e18,                         // Unchanged
                borrowerMompFactor:        10_016.501589292607751220 * 1e18,
                borrowerInflator:          1.002056907057504104 * 1e18,      // Inflator is updated to reflect new deb
                borrowerCollateralization: 0.998633861930247030 * 1e18,      // Unchanged because based off pending debt
                borrowerPendingDebt:       10_030.204233142901661009 * 1e18  // Pending debt is unchanged
            }
        );
        assertEq(PoolUtils.encumberance(10_030.204233142901661009 * 1e18, _lup()), 1.001368006956135433 * 1e18);  // Unencumbered collateral is unchanged because based off pending debt

        ( kickTime, referencePrice, remainingCollateral, remainingDebt ) = ERC20Pool(address(_pool)).liquidations(_borrower2);

        assertEq(kickTime,            block.timestamp);
        assertEq(referencePrice,      HPB);
        assertEq(remainingCollateral, 1e18);
    }

    function testAuctionPrice() external {
        skip(6238);
        uint256 referencePrice = 8_678.5 * 1e18;
        uint256 kickTime = block.timestamp;
        assertEq(PoolUtils.auctionPrice(referencePrice, kickTime), 86_785.0 * 1e18);
        skip(1444); // price should not change in the first hour
        assertEq(PoolUtils.auctionPrice(referencePrice, kickTime), 86_785.0 * 1e18);

        skip(5756);     // 2 hours
        assertEq(PoolUtils.auctionPrice(referencePrice, kickTime), 43_392.5 * 1e18);
        skip(2394);     // 2 hours, 39 minutes, 54 seconds
        assertEq(PoolUtils.auctionPrice(referencePrice, kickTime), 27_367.159606354998613290 * 1e18);
        skip(2586);     // 3 hours, 23 minutes
        assertEq(PoolUtils.auctionPrice(referencePrice, kickTime), 16_633.737549018910661740 * 1e18);
        skip(3);        // 3 seconds later
        assertEq(PoolUtils.auctionPrice(referencePrice, kickTime), 16_624.132299820494703920 * 1e18);
        skip(20153);    // 8 hours, 35 minutes, 53 seconds
        assertEq(PoolUtils.auctionPrice(referencePrice, kickTime), 343.207165783609045700 * 1e18);
        skip(97264);    // 36 hours
        assertEq(PoolUtils.auctionPrice(referencePrice, kickTime), 0.00000252577588655 * 1e18);
        skip(129600);   // 72 hours
        assertEq(PoolUtils.auctionPrice(referencePrice, kickTime), 0);
    }

    // TODO: move to DSTestPlus?
    function _logBorrowerInfo(address borrower_) internal {
        (
            uint256 borrowerDebt,
            uint256 borrowerPendingDebt,
            uint256 collateralDeposited,
            uint256 mompFactor,
            uint256 borrowerInflator

        ) = _poolUtils.borrowerInfo(address(_pool), borrower_);

        emit log_named_uint("borrowerDebt        ", borrowerDebt);
        emit log_named_uint("borrowerPendingDebt ", borrowerPendingDebt);
        emit log_named_uint("collateralDeposited ", collateralDeposited);
        emit log_named_uint("mompFactor ",           mompFactor);
        emit log_named_uint("collateralEncumbered", PoolUtils.encumberance(borrowerDebt, _lup()));
        emit log_named_uint("collateralization   ", PoolUtils.collateralization(borrowerDebt, collateralDeposited, _lup()));
        emit log_named_uint("borrowerInflator    ", borrowerInflator);
    }
}
