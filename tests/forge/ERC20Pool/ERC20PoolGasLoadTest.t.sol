// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.14;

import { ERC20DSTestPlus } from './ERC20DSTestPlus.sol';

import '../utils/Tokens.sol';

import 'src/ERC20Pool.sol';
import 'src/ERC20PoolFactory.sol';

import 'src/PoolInfoUtils.sol';

contract ERC20PoolGasLoadTest is ERC20DSTestPlus {

    Token internal _collateral;
    Token internal _quote;

    address[] internal _lenders;
    address[] internal _borrowers;

    uint16 internal constant LENDERS     = 2_000;
    uint16 internal constant LOANS_COUNT = 8_000;

    function setUp() public {

        _collateral = new Token("Collateral", "C");
        _quote      = new Token("Quote", "Q");
        _pool       = ERC20Pool(new ERC20PoolFactory(_ajna).deployPool(address(_collateral), address(_quote), 0.05 * 10**18));
        _poolUtils  = new PoolInfoUtils();

        skip(1 hours); // avoid deposit time to be the same as bucket bankruptcy time

        _setupLendersAndDeposits(LENDERS);
        _setupBorrowersAndLoans(LOANS_COUNT);
    }

    /*************************/
    /*** Utility Functions ***/
    /*************************/

    function _setupLendersAndDeposits(uint256 count_) internal virtual {
        for (uint256 i; i < count_;) {
            address lender = address(uint160(uint256(keccak256(abi.encodePacked(i, 'lender')))));

            _mintQuoteAndApproveTokens(lender, 200_000 * 1e18);

            vm.startPrank(lender);
            _pool.addQuoteToken(100_000 * 1e18, 7388 - i);
            _pool.addQuoteToken(100_000 * 1e18, 1 + i);
            vm.stopPrank();

            _lenders.push(lender);

            unchecked {
                ++i;
            }
        }
    }

    function _setupBorrowersAndLoans(uint256 count_) internal {
        for (uint256 i; i < count_;) {
            address borrower = address(uint160(uint256(keccak256(abi.encodePacked(i, 'borrower')))));

            _mintQuoteAndApproveTokens(borrower,      2_000 * 1e18);
            _mintCollateralAndApproveTokens(borrower, 200 * 1e18);

            vm.startPrank(borrower);
            ERC20Pool(address(_pool)).drawDebt(borrower, 1_000 * 1e18 + i * 1e18, 5000, 100 * 1e18);
            vm.stopPrank();

            _borrowers.push(borrower);
            unchecked {
                ++i;
            }
        }
    }

    function _mintQuoteAndApproveTokens(address operator_, uint256 mintAmount_) internal {
        deal(address(_quote), operator_, mintAmount_);

        vm.prank(operator_);
        _quote.approve(address(_pool), type(uint256).max);
        vm.prank(operator_);
        _collateral.approve(address(_pool), type(uint256).max);
    }

    function _mintCollateralAndApproveTokens(address operator_, uint256 mintAmount_) internal {
        deal(address(_collateral), operator_, mintAmount_);

        vm.prank(operator_);
        _collateral.approve(address(_pool), type(uint256).max);
        vm.prank(operator_);
        _quote.approve(address(_pool), type(uint256).max);

    }

    function _noOfLoans() internal view returns (uint256 loans_) {
        (, , loans_) = _pool.loansInfo();
    }
}

contract ERC20PoolCommonActionsGasLoadTest is ERC20PoolGasLoadTest {
    function testLoadERC20PoolFuzzyPartialRepay(uint256 borrowerId_) public {
        assertEq(_noOfLoans(), LOANS_COUNT);

        vm.assume(borrowerId_ <= LOANS_COUNT);
        address borrower = _borrowers[borrowerId_];
        skip(15 hours);
        vm.prank(borrower);
        ERC20Pool(address(_pool)).repayDebt(borrower, 100 * 1e18, 0);

        assertEq(_noOfLoans(), LOANS_COUNT);
    }

    function testLoadERC20PoolGasFuzzyFullRepay(uint256 borrowerId_) public {
        assertEq(_noOfLoans(), LOANS_COUNT);

        vm.assume(borrowerId_ <= LOANS_COUNT);
        skip(15 hours);
        address borrower = _borrowers[borrowerId_];
        (uint256 debt, , ) = _poolUtils.borrowerInfo(address(_pool), borrower);
        vm.prank(borrower);
        ERC20Pool(address(_pool)).repayDebt(borrower, debt, 0);

        assertEq(_noOfLoans(), LOANS_COUNT - 1);
    }

    function testLoadERC20PoolGasFuzzyBorrowExisting(uint256 borrowerId_) public {
        assertEq(_noOfLoans(), LOANS_COUNT);

        vm.assume(borrowerId_ <= LOANS_COUNT);
        skip(15 hours);
        address borrower = _borrowers[borrowerId_];
        vm.prank(borrower);
        _drawDebtNoLupCheck(
            {
                from:               borrower,
                borrower:           borrower,
                amountToBorrow:     1_000 * 1e18,
                limitIndex:         5000,
                collateralToPledge: 0
            }
        );

        assertEq(_noOfLoans(), LOANS_COUNT);
    }

    function testLoadERC20PoolGasBorrowNew() public {
        uint256 snapshot = vm.snapshot();

        assertEq(_noOfLoans(), LOANS_COUNT);

        address newBorrower = makeAddr("newBorrower");

        _mintQuoteAndApproveTokens(newBorrower,      2_000 * 1e18);
        _mintCollateralAndApproveTokens(newBorrower, 2_000 * 1e18);

        vm.startPrank(newBorrower);
        skip(15 hours);
        _drawDebtNoLupCheck(
            {
                from:               newBorrower,
                borrower:           newBorrower,
                amountToBorrow:     0,
                limitIndex:         0,
                collateralToPledge: 1_000 * 1e18
            }
        );
        skip(15 hours);
        _drawDebtNoLupCheck(
            {
                from:               newBorrower,
                borrower:           newBorrower,
                amountToBorrow:     1_000 * 1e18,
                limitIndex:         5000,
                collateralToPledge: 0
            }
        );
        vm.stopPrank();

        assertEq(_noOfLoans(), LOANS_COUNT + 1);

        vm.revertTo(snapshot);
        assertEq(_noOfLoans(), LOANS_COUNT);
    }

    function testLoadERC20PoolGasExercisePartialRepayForAllBorrowers() public {
        assertEq(_noOfLoans(), LOANS_COUNT);

        for (uint256 i; i < LOANS_COUNT; i++) {
            uint256 snapshot = vm.snapshot();
            skip(15 hours);
            assertEq(_noOfLoans(), LOANS_COUNT);

            address borrower = _borrowers[i];
            vm.prank(borrower);
            ERC20Pool(address(_pool)).repayDebt(borrower, 100 * 1e18, 0);

            assertEq(_noOfLoans(), LOANS_COUNT);
            vm.revertTo(snapshot);
        }

        assertEq(_noOfLoans(), LOANS_COUNT);
    }

    function testLoadERC20PoolGasExerciseRepayAllForAllBorrowers() public {
        assertEq(_noOfLoans(), LOANS_COUNT);

        for (uint256 i; i < LOANS_COUNT; i++) {
            uint256 snapshot = vm.snapshot();
            skip(15 hours);
            assertEq(_noOfLoans(), LOANS_COUNT);

            address borrower = _borrowers[i];
            (uint256 debt, , ) = _poolUtils.borrowerInfo(address(_pool), borrower);
            vm.prank(borrower);
            ERC20Pool(address(_pool)).repayDebt(borrower, debt, 0);

            assertEq(_noOfLoans(), LOANS_COUNT - 1);
            vm.revertTo(snapshot);
        }

        assertEq(_noOfLoans(), LOANS_COUNT);
    }

    function testLoadERC20PoolGasExerciseBorrowMoreForAllBorrowers() public {
        assertEq(_noOfLoans(), LOANS_COUNT);

        for (uint256 i; i < LOANS_COUNT; i++) {
            uint256 snapshot = vm.snapshot();
            skip(15 hours);
            assertEq(_noOfLoans(), LOANS_COUNT);

            address borrower = _borrowers[i];
            _drawDebtNoLupCheck(
                {
                    from:               borrower,
                    borrower:           borrower,
                    amountToBorrow:     1_000 * 1e18,
                    limitIndex:         5000,
                    collateralToPledge: 0
                }
            );
            assertEq(_noOfLoans(), LOANS_COUNT);
            vm.revertTo(snapshot);
        }

        assertEq(_noOfLoans(), LOANS_COUNT);
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
        _pool.removeQuoteToken(type(uint256).max, index_);
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
            _pool.removeQuoteToken(type(uint256).max, 1 + i);
            vm.stopPrank();
            vm.revertTo(snapshot);
        }
    }

    function testLoadERC20PoolGasKickAndTakeAllLoansFromLowestTP() public {
        address kicker = makeAddr("kicker");
        _mintQuoteAndApproveTokens(kicker, type(uint256).max); // mint enough to cover bonds

        vm.warp(100_000 days);
        vm.startPrank(kicker);
        for (uint256 i; i < LOANS_COUNT; i ++) {
            _pool.kick(_borrowers[i]);
        }
        skip(2 hours);
        for (uint256 i; i < LOANS_COUNT - 1; i ++) {
            ERC20Pool(address(_pool)).take(_borrowers[i], 100 * 1e18, kicker, new bytes(0));
        }
        vm.stopPrank();
    }

    function testLoadERC20PoolGasKickAndTakeAllLoansFromHighestTP() public {
        address kicker = makeAddr("kicker");
        _mintQuoteAndApproveTokens(kicker, type(uint256).max); // mint enough to cover bonds

        vm.warp(100_000 days);
        vm.startPrank(kicker);
        for (uint256 i; i < LOANS_COUNT; i ++) {
            _pool.kick(_borrowers[LOANS_COUNT - 1 - i]);
        }
        skip(2 hours);
        for (uint256 i; i < LOANS_COUNT - 1; i ++) {
            ERC20Pool(address(_pool)).take(_borrowers[LOANS_COUNT - 1 - i], 100 * 1e18, kicker, new bytes(0));
        }
        vm.stopPrank();
    }

    function testLoadERC20PoolGasKickWithDepositAndSettleHighestTP() public {
        address kicker = makeAddr("kicker");
        _mintQuoteAndApproveTokens(kicker, type(uint256).max); // mint enough to cover bonds

        vm.startPrank(kicker);
        _pool.addQuoteToken(500_000_000_000_000 * 1e18, 3_000);
        vm.warp(100_000 days);
        _pool.kickWithDeposit(3_000); // worst case scenario, pool interest accrues
        skip(80 hours);
        _pool.settle(_borrowers[LOANS_COUNT - 1], 10);
        // kick remaining loans with deposit to get average gas cost
        for (uint256 i; i < LOANS_COUNT - 1; i ++) {
            _pool.kickWithDeposit(3_000);
        }
        vm.stopPrank();
    }
}

contract ERC20PoolGasArbTakeLoadTest is ERC20PoolGasLoadTest {

    function testLoadERC20PoolGasKickAndArbTakeLowestTPLoan() public {
        _kickAndTakeLowestTPLoan(false);
    }

    function testLoadERC20PoolGasKickAndDepositTakeLowestTPLoan() public {
        _kickAndTakeLowestTPLoan(true);
    }

    function testLoadERC20PoolGasKickAndArbTakeHighestTPLoan() public {
        _kickAndTakeHighestTPLoan(false);
    }

    function testLoadERC20PoolGasKickAndDepositTakeHighestTPLoan() public {
        _kickAndTakeHighestTPLoan(true);
    }

    function _kickAndTakeLowestTPLoan(bool depositTake_) internal {
        address kicker = makeAddr("kicker");
        _mintQuoteAndApproveTokens(kicker, type(uint256).max); // mint enough to cover bonds

        vm.warp(100_000 days);
        vm.startPrank(kicker);
        for (uint256 i; i < LOANS_COUNT; i ++) {
            _pool.kick(_borrowers[i]);
        }
        // add quote tokens in bucket to arb
        _pool.addQuoteToken(100_000 * 1e18, 1_000);
        vm.stopPrank();

        assertEq(_noOfLoans(), 0); // assert all loans are kicked
        skip(14 hours);
        address taker = makeAddr("taker");
        vm.startPrank(taker);
        _pool.bucketTake(_borrowers[0], depositTake_, 1_000);
        vm.stopPrank();
    }

    function _kickAndTakeHighestTPLoan(bool depositTake_) internal {
        address kicker = makeAddr("kicker");
        _mintQuoteAndApproveTokens(kicker, type(uint256).max); // mint enough to cover bonds

        vm.warp(100_000 days);
        vm.startPrank(kicker);
        for (uint256 i; i < LOANS_COUNT; i ++) {
            _pool.kick(_borrowers[LOANS_COUNT - 1 - i]);
        }
        // add quote tokens in bucket to arb
        _pool.addQuoteToken(100_000 * 1e18, 1_000);
        vm.stopPrank();

        assertEq(_noOfLoans(), 0); // assert all loans are kicked
        skip(14 hours);
        address taker = makeAddr("taker");
        vm.startPrank(taker);
        _pool.bucketTake(_borrowers[LOANS_COUNT - 1], depositTake_, 1_000);
        vm.stopPrank();
    }

    /*************************/
    /*** Utility Functions ***/
    /*************************/

    /**
     *  @dev arb take deposits are set up differently to avoid auction price being greater than pool's max price
    */
    function _setupLendersAndDeposits(uint256 count_) internal override {
        for (uint256 i; i < count_; i++) {
            address lender = address(uint160(uint256(keccak256(abi.encodePacked(i, 'lender')))));

            _mintQuoteAndApproveTokens(lender, 200_000 * 1e18);

            vm.startPrank(lender);
            _pool.addQuoteToken(200_000 * 1e18, 5000 - i);
            vm.stopPrank();

            _lenders.push(lender);
        }
    }
}
