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
    uint16 private constant LOANS_COUNT = 8_500;

    function setUp() public {
        _setupLendersAndDeposits(1_000);
        _setupBorrowersAndLoans(LOANS_COUNT);
    }

    function testGasLoadERC20PoolFuzzyPartialRepay(uint256 borrowerId_) public {
        assertEq(_pool.loansCount(), LOANS_COUNT);

        vm.assume(borrowerId_ <= LOANS_COUNT);
        address borrower = _borrowers[borrowerId_];
        vm.prank(borrower);
        _pool.repay(borrower, 100 * 1e18);

        assertEq(_pool.loansCount(), LOANS_COUNT);
    }

    function testGasLoadERC20PoolGasFuzzyFullRepay(uint256 borrowerId_) public {
        assertEq(_pool.loansCount(), LOANS_COUNT);

        vm.assume(borrowerId_ <= LOANS_COUNT);
        address borrower = _borrowers[borrowerId_];
        (, uint256 pendingDebt, , ) = _pool.borrowerInfo(borrower);
        vm.prank(borrower);
        _pool.repay(borrower, pendingDebt);

        assertEq(_pool.loansCount(), LOANS_COUNT - 1);
    }

    function testGasLoadERC20PoolGasFuzzyBorrowExisting(uint256 borrowerId_) public {
        assertEq(_pool.loansCount(), LOANS_COUNT);

        vm.assume(borrowerId_ <= LOANS_COUNT);
        address borrower = _borrowers[borrowerId_];
        vm.prank(borrower);
        _pool.borrow(1_000 * 1e18, 5_000);

        assertEq(_pool.loansCount(), LOANS_COUNT);
    }

    function testGasLoadERC20PoolGasBorrowNew() public {
        uint256 snapshot = vm.snapshot();

        assertEq(_pool.loansCount(), LOANS_COUNT);

        address newBorrower = makeAddr("newBorrower");

        _mintQuoteAndApproveTokens(newBorrower,      2_000 * 1e18);
        _mintCollateralAndApproveTokens(newBorrower, 2_000 * 1e18);

        vm.startPrank(newBorrower);
        _pool.pledgeCollateral(newBorrower, 1_000 * 1e18);
        _pool.borrow(1_000 * 1e18, 5_000);
        vm.stopPrank();

        assertEq(_pool.loansCount(), LOANS_COUNT + 1);

        vm.revertTo(snapshot);
        assertEq(_pool.loansCount(), LOANS_COUNT);
    }

    function testGasLoadERC20PoolGasExercisePartialRepayForAllBorrowers() public {
        assertEq(_pool.loansCount(), LOANS_COUNT);

        for (uint256 i; i < LOANS_COUNT; i++) {
            uint256 snapshot = vm.snapshot();
            assertEq(_pool.loansCount(), LOANS_COUNT);

            address borrower = _borrowers[i];
            vm.prank(borrower);
            _pool.repay(borrower, 100 * 1e18);

            assertEq(_pool.loansCount(), LOANS_COUNT);
            vm.revertTo(snapshot);
        }

        assertEq(_pool.loansCount(), LOANS_COUNT);
    }

    function testGasLoadERC20PoolGasExerciseRepayAllForAllBorrowers() public {
        assertEq(_pool.loansCount(), LOANS_COUNT);

        for (uint256 i; i < LOANS_COUNT; i++) {
            uint256 snapshot = vm.snapshot();
            assertEq(_pool.loansCount(), LOANS_COUNT);

            address borrower = _borrowers[i];
            (, uint256 pendingDebt, , ) = _pool.borrowerInfo(borrower);
            vm.prank(borrower);
            _pool.repay(borrower, pendingDebt);

            assertEq(_pool.loansCount(), LOANS_COUNT - 1);
            vm.revertTo(snapshot);
        }

        assertEq(_pool.loansCount(), LOANS_COUNT);
    }

    function testGasLoadERC20PoolGasExerciseBorrowMoreForAllBorrowers() public {
        assertEq(_pool.loansCount(), LOANS_COUNT);

        for (uint256 i; i < LOANS_COUNT; i++) {
            uint256 snapshot = vm.snapshot();
            assertEq(_pool.loansCount(), LOANS_COUNT);

            address borrower = _borrowers[i];
            vm.prank(borrower);
            _pool.borrow(1_000 * 1e18, 5_000);

            assertEq(_pool.loansCount(), LOANS_COUNT);
            vm.revertTo(snapshot);
        }

        assertEq(_pool.loansCount(), LOANS_COUNT);
    }


    /*************************/
    /*** Utility Functions ***/
    /*************************/

    function _setupLendersAndDeposits(uint256 count_) internal {
        for (uint256 i; i < count_; i++) {
            vm.roll(1);

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

            vm.roll(1);

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
