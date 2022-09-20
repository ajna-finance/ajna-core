// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.14;

import { ERC20Pool }        from "../../erc20/ERC20Pool.sol";
import { ERC20PoolFactory } from "../../erc20/ERC20PoolFactory.sol";

import { BucketMath }  from "../../libraries/BucketMath.sol";

import { ERC20HelperContract } from "./ERC20DSTestPlus.sol";
import { Token }               from "../utils/Tokens.sol";

contract ERC20PoolGasLoadTest is ERC20HelperContract {
    address[] private _lenders;
    address[] private _borrowers;
    uint16 private constant LENDERS     = 2_000;
    uint16 private constant LOANS_COUNT = 8_000;

    function setUp() public {
        _setupLendersAndDeposits(LENDERS);
        _setupBorrowersAndLoans(LOANS_COUNT);
    }

    function testLoadERC20PoolFuzzyPartialRepay(uint256 borrowerId_) public {
        assertEq(_loansCount(), LOANS_COUNT);

        vm.assume(borrowerId_ <= LOANS_COUNT);
        address borrower = _borrowers[borrowerId_];
        skip(15 hours);
        vm.prank(borrower);
        _pool.repay(borrower, 100 * 1e18);

        assertEq(_loansCount(), LOANS_COUNT);
    }

    function testLoadERC20PoolGasFuzzyFullRepay(uint256 borrowerId_) public {
        assertEq(_loansCount(), LOANS_COUNT);

        vm.assume(borrowerId_ <= LOANS_COUNT);
        skip(15 hours);
        address borrower = _borrowers[borrowerId_];
        (, uint256 pendingDebt, , , ) = _pool.borrowerInfo(borrower);
        vm.prank(borrower);
        _pool.repay(borrower, pendingDebt);

        assertEq(_loansCount(), LOANS_COUNT - 1);
    }

    function testLoadERC20PoolGasFuzzyBorrowExisting(uint256 borrowerId_) public {
        assertEq(_loansCount(), LOANS_COUNT);

        vm.assume(borrowerId_ <= LOANS_COUNT);
        skip(15 hours);
        address borrower = _borrowers[borrowerId_];
        vm.prank(borrower);
        _pool.borrow(1_000 * 1e18, 5_000);

        assertEq(_loansCount(), LOANS_COUNT);
    }

    function testLoadERC20PoolGasBorrowNew() public {
        uint256 snapshot = vm.snapshot();

        assertEq(_loansCount(), LOANS_COUNT);

        address newBorrower = makeAddr("newBorrower");

        _mintQuoteAndApproveTokens(newBorrower,      2_000 * 1e18);
        _mintCollateralAndApproveTokens(newBorrower, 2_000 * 1e18);

        vm.startPrank(newBorrower);
        skip(15 hours);
        _pool.pledgeCollateral(newBorrower, 1_000 * 1e18);
        skip(15 hours);
        _pool.borrow(1_000 * 1e18, 5_000);
        vm.stopPrank();

        assertEq(_loansCount(), LOANS_COUNT + 1);

        vm.revertTo(snapshot);
        assertEq(_loansCount(), LOANS_COUNT);
    }

    function testLoadERC20PoolGasExercisePartialRepayForAllBorrowers() public {
        assertEq(_loansCount(), LOANS_COUNT);

        for (uint256 i; i < LOANS_COUNT; i++) {
            uint256 snapshot = vm.snapshot();
            skip(15 hours);
            assertEq(_loansCount(), LOANS_COUNT);

            address borrower = _borrowers[i];
            vm.prank(borrower);
            _pool.repay(borrower, 100 * 1e18);

            assertEq(_loansCount(), LOANS_COUNT);
            vm.revertTo(snapshot);
        }

        assertEq(_loansCount(), LOANS_COUNT);
    }

    function testLoadERC20PoolGasExerciseRepayAllForAllBorrowers() public {
        assertEq(_loansCount(), LOANS_COUNT);

        for (uint256 i; i < LOANS_COUNT; i++) {
            uint256 snapshot = vm.snapshot();
            skip(15 hours);
            assertEq(_loansCount(), LOANS_COUNT);

            address borrower = _borrowers[i];
            (, uint256 pendingDebt, , , ) = _pool.borrowerInfo(borrower);
            vm.prank(borrower);
            _pool.repay(borrower, pendingDebt);

            assertEq(_loansCount(), LOANS_COUNT - 1);
            vm.revertTo(snapshot);
        }

        assertEq(_loansCount(), LOANS_COUNT);
    }

    function testLoadERC20PoolGasExerciseBorrowMoreForAllBorrowers() public {
        assertEq(_loansCount(), LOANS_COUNT);

        for (uint256 i; i < LOANS_COUNT; i++) {
            uint256 snapshot = vm.snapshot();
            skip(15 hours);
            assertEq(_loansCount(), LOANS_COUNT);

            address borrower = _borrowers[i];
            vm.prank(borrower);
            _pool.borrow(1_000 * 1e18, 5_000);

            assertEq(_loansCount(), LOANS_COUNT);
            vm.revertTo(snapshot);
        }

        assertEq(_loansCount(), LOANS_COUNT);
    }

    function testLoadERC20PoolGasFuzzyAddRemoveQuoteToken(uint256 index_) public {
        vm.assume(index_ > 1 && index_ < 7388);

        address lender = _lenders[0];
        _mintQuoteAndApproveTokens(lender, 200_000 * 1e18);

        vm.startPrank(lender);
        skip(15 hours);
        _pool.addQuoteToken(10_000 * 1e18, index_);
        skip(15 hours);
        _pool.removeQuoteToken(5_000 * 1e18, index_);
        skip(15 hours);
        _pool.moveQuoteToken(1_000 * 1e18, index_, index_ + 1);
        skip(15 hours);
        _pool.removeAllQuoteToken(index_);
        vm.stopPrank();
    }

    function testLoadERC20PoolGasExerciseAddRemoveQuoteTokenForAllIndexes() public {
        address lender = _lenders[0];
        _mintQuoteAndApproveTokens(lender, 200_000 * 1e18);

        for (uint256 i = 1; i < LENDERS; i++) {
            uint256 snapshot = vm.snapshot();
            vm.startPrank(lender);
            skip(15 hours);
            _pool.addQuoteToken(10_000 * 1e18, 7388 - i);
            skip(15 hours);
            _pool.addQuoteToken(10_000 * 1e18, 1 + i);
            skip(15 hours);
            _pool.removeQuoteToken(5_000 * 1e18, 7388 - i);
            skip(15 hours);
            _pool.removeAllQuoteToken(1 + i);
            vm.stopPrank();
            vm.revertTo(snapshot);
        }
    }


    /*************************/
    /*** Utility Functions ***/
    /*************************/

    function _setupLendersAndDeposits(uint256 count_) internal {
        for (uint256 i; i < count_; i++) {
            address lender = address(uint160(uint256(keccak256(abi.encodePacked(i, 'lender')))));

            _mintQuoteAndApproveTokens(lender, 200_000 * 1e18);

            vm.startPrank(lender);
            _pool.addQuoteToken(100_000 * 1e18, 7388 - i);
            _pool.addQuoteToken(100_000 * 1e18, 1 + i);
            vm.stopPrank();

            _lenders.push(lender);
        }
    }

    function _setupBorrowersAndLoans(uint256 count_) internal {
        for (uint256 i; i < count_; i++) {
            address borrower = address(uint160(uint256(keccak256(abi.encodePacked(i, 'borrower')))));

            _mintQuoteAndApproveTokens(borrower,      2_000 * 1e18);
            _mintCollateralAndApproveTokens(borrower, 200 * 1e18);

            vm.startPrank(borrower);
            _pool.pledgeCollateral(borrower, 100 * 1e18);
            _pool.borrow(1_000 * 1e18 + i * 1e18, 5000);
            vm.stopPrank();

            _borrowers.push(borrower);
        }
    }
}
