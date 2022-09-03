// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.14;

import { ERC20Pool }        from "../../erc20/ERC20Pool.sol";
import { ERC20PoolFactory } from "../../erc20/ERC20PoolFactory.sol";

import { BucketMath } from "../../libraries/BucketMath.sol";
import { Maths }      from "../../libraries/Maths.sol";

import { ERC20HelperContract } from "./ERC20DSTestPlus.sol";

contract ERC20ScaledCollateralTest is ERC20HelperContract {

    address internal _borrower;
    address internal _borrower2;
    address internal _lender;
    address internal _bidder;

    function setUp() external {
        _borrower  = makeAddr("borrower");
        _borrower2 = makeAddr("borrower2");
        _lender    = makeAddr("lender");
        _bidder    = makeAddr("bidder");

        _mintCollateralAndApproveTokens(_borrower,  150 * 1e18);
        _mintCollateralAndApproveTokens(_borrower2,  100 * 1e18);

        _mintQuoteAndApproveTokens(_lender,   200_000 * 1e18);
        _mintQuoteAndApproveTokens(_bidder,  200_000 * 1e18);
    }

    /**
     *  @notice With 1 lender and 1 borrower test pledgeCollateral, borrow, and pullCollateral.
     */
    function testAddPullCollateral() external {
        uint256 depositIndexHighest = 2550;
        uint256 depositIndexHigh    = 2551;
        uint256 depositIndexMed     = 2552;

        // lender deposits 10000 Quote into 3 buckets
        changePrank(_lender);
        _pool.addQuoteToken(10_000 * 1e18, depositIndexHighest);
        _pool.addQuoteToken(10_000 * 1e18, depositIndexHigh);
        _pool.addQuoteToken(10_000 * 1e18, depositIndexMed);

        // check initial pool state
        assertEq(_pool.htp(), 0);
        assertEq(_pool.lup(), BucketMath.MAX_PRICE);

        assertEq(_pool.poolSize(),     30_000 * 1e18);
        assertEq(_pool.borrowerDebt(), 0);

        assertEq(_pool.pledgedCollateral(),   0);
        assertEq(_collateral.balanceOf(_borrower), 150 * 1e18);

        // borrower deposits 100 collateral
        changePrank(_borrower);
        vm.expectEmit(true, true, false, true);
        emit PledgeCollateral(_borrower, 100 * 1e18);
        _pool.pledgeCollateral(_borrower, 100 * 1e18, address(0), address(0));

        // check pool state collateral accounting updated successfully
        assertEq(_pool.pledgedCollateral(),        100 * 1e18);
        assertEq(_collateral.balanceOf(_borrower), 50 * 1e18);

        // get a 21_000 Quote loan
        vm.expectEmit(true, true, false, true);
        emit Borrow(_borrower, 2_981.007422784467321543 * 1e18, 21_000 * 1e18);
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(_pool), _borrower, 21_000 * 1e18);
        _pool.borrow(21_000 * 1e18, 3000, address(0), address(0));

        // check pool state
        assertEq(_pool.htp(), 210.201923076923077020 * 1e18);
        assertEq(_pool.lup(), 2_981.007422784467321543 * 1e18);

        assertEq(_pool.poolSize(),          30_000 * 1e18);
        assertEq(_pool.borrowerDebt(),      21_020.192307692307702000 * 1e18);
        assertEq(_pool.pledgedCollateral(), 100 * 1e18);

        assertEq(_pool.encumberedCollateral(_pool.borrowerDebt(), _pool.lup()), 7.051372011699988577 * 1e18);

        // check borrower state
        (uint256 borrowerDebt, , uint256 borrowerCollateral, ) = _pool.borrowerInfo(_borrower);
        assertEq(borrowerDebt,       _pool.borrowerDebt());
        assertEq(borrowerCollateral, _pool.pledgedCollateral());
        assertEq(
            _pool.encumberedCollateral(_pool.borrowerDebt(), _pool.lup()),
            _pool.encumberedCollateral(borrowerDebt, _pool.lup())
        );
        assertEq(_collateral.balanceOf(_borrower), 50 * 1e18);

        assertEq(_pool.borrowerCollateralization(borrowerDebt, borrowerCollateral, _pool.lup()), _pool.poolCollateralization());

        // pass time to allow interest to accrue
        skip(864000);

        // remove some of the collateral
        vm.expectEmit(true, true, false, true);
        emit PullCollateral(_borrower, 50 * 1e18);
        _pool.pullCollateral(50 * 1e18, address(0), address(0));

        // check borrower state
        (borrowerDebt, , borrowerCollateral, ) = _pool.borrowerInfo(_borrower);
        assertEq(borrowerDebt,       _pool.borrowerDebt());
        assertEq(borrowerCollateral, _pool.pledgedCollateral());
        assertEq(
            _pool.encumberedCollateral(_pool.borrowerDebt(), _pool.lup()),
            _pool.encumberedCollateral(borrowerDebt, _pool.lup())
        );
        assertEq(_collateral.balanceOf(_borrower), 100 * 1e18);

        assertEq(_pool.borrowerCollateralization(borrowerDebt, borrowerCollateral, _pool.lup()), _pool.poolCollateralization());

        // remove all of the remaining unencumbered collateral
        uint256 unencumberedCollateral = borrowerCollateral - _pool.encumberedCollateral(borrowerDebt, _pool.lup());
        vm.expectEmit(true, true, false, true);
        emit PullCollateral(_borrower, unencumberedCollateral);
        _pool.pullCollateral(unencumberedCollateral, address(0), address(0));

        // check t0 TP
        assertEq(_pool.loanQueueHead(), _borrower);
        (uint256 t0Tp, ) = _pool.loans(_borrower);
        assertEq(t0Tp, 2_976.926646662711731447 * 1e18);

        // check pool state
        assertEq(_pool.htp(), 2_981.007422784467321393 * 1e18); // HTP should be different than t0 TP recorded in TP queue
        assertEq(_pool.lup(), 2_981.007422784467321543 * 1e18);

        assertEq(_pool.poolSize(),          30_025.933063902025680000 * 1e18);
        assertEq(_pool.borrowerDebt(),      21_049.006823139002918431 * 1e18);
        assertEq(_pool.pledgedCollateral(), _pool.encumberedCollateral(_pool.borrowerDebt(), _pool.lup()));

        assertEq(_pool.encumberedCollateral(_pool.borrowerDebt(), _pool.lup()), 7.061038044473493202 * 1e18);

        // check borrower state
        (borrowerDebt, , borrowerCollateral, ) = _pool.borrowerInfo(_borrower);
        assertEq(borrowerDebt,       _pool.borrowerDebt());
        assertEq(borrowerCollateral, _pool.pledgedCollateral());
        assertEq(
            _pool.encumberedCollateral(_pool.borrowerDebt(), _pool.lup()),
            _pool.encumberedCollateral(borrowerDebt, _pool.lup())
        );
        assertEq(_collateral.balanceOf(_borrower), 142.938961955526506798 * 1e18);

        assertEq(_pool.borrowerCollateralization(borrowerDebt, borrowerCollateral, _pool.lup()), _pool.poolCollateralization());
    }

    /**
     *  @notice 1 borrower tests reverts in pullCollateral.
     *          Reverts:
     *              Attempts to remove more than available unencumbered collateral.
     */
    function testPullCollateralRequireEnoughCollateral() external {
        uint256 testCollateralAmount = 100 * 1e18;

        changePrank(_borrower);
        // should revert if trying to remove more collateral than is available
        vm.expectRevert("S:PC:NOT_ENOUGH_COLLATERAL");
        _pool.pullCollateral(testCollateralAmount, address(0), address(0));

        // borrower deposits 100 collateral
        vm.expectEmit(true, true, true, true);
        emit PledgeCollateral(_borrower, testCollateralAmount);
        _pool.pledgeCollateral(_borrower, testCollateralAmount, address(0), address(0));

        // should be able to now remove collateral
        vm.expectEmit(true, true, true, true);
        emit PullCollateral(_borrower, testCollateralAmount);
        _pool.pullCollateral(testCollateralAmount, address(0), address(0));
    }

    /**
     *  @notice 1 actor tests addCollateral and removeCollateral.
     */
    function testRemoveCollateral() external {
        // test setup
        uint256 testIndex = 2550;
        uint256 priceAtTestIndex = _pool.indexToPrice(testIndex);
        deal(address(_collateral), _bidder,  100 * 1e18);

        changePrank(_bidder);
        _collateral.approve(address(_pool), 100 * 1e18);

        // actor deposits collateral into a bucket
        uint256 collateralToDeposit = 4 * 1e18;
        vm.expectEmit(true, true, false, true);
        emit AddCollateral(_bidder, priceAtTestIndex, collateralToDeposit);
        vm.expectEmit(true, true, false, true);
        emit Transfer(_bidder, address(_pool), collateralToDeposit);
        _pool.addCollateral(collateralToDeposit, testIndex);

        // check bucket state
        (uint256 lpAccumulator, uint256 availableCollateral) = _pool.buckets(testIndex);
        assertEq(availableCollateral, collateralToDeposit);
        (uint256 lpBalance, ) = _pool.bucketLenders(testIndex, _bidder);
        assertEq(lpBalance, 12_043.56808879152623138 * 1e27);
        assertEq(lpAccumulator, lpBalance);

        // check pool state and balances
        assertEq(_collateral.balanceOf(_lender),        0);
        assertEq(_collateral.balanceOf(address(_pool)), collateralToDeposit);
        assertEq(_quote.balanceOf(address(_pool)),      0);

        // actor withdraws some of their collateral
        uint256 collateralToWithdraw = 1.53 * 1e18;
        vm.expectEmit(true, true, true, true);
        emit RemoveCollateral(_bidder, priceAtTestIndex, collateralToWithdraw);
        vm.expectEmit(true, true, true, true);
        emit Transfer(address(_pool), _bidder, collateralToWithdraw);
        uint256 lpRedeemed = _pool.removeCollateral(collateralToWithdraw, testIndex);
        assertEq(lpRedeemed, 4_606.664793962758783502850000000 * 1e27);

        // actor withdraws remainder of their _collateral
        collateralToWithdraw = 2.47 * 1e18;
        vm.expectEmit(true, true, true, true);
        emit RemoveCollateral(_bidder, priceAtTestIndex, collateralToWithdraw);
        vm.expectEmit(true, true, true, true);
        emit Transfer(address(_pool), _bidder, collateralToWithdraw);
        uint256 collateralRemoved;
        (collateralRemoved, lpRedeemed) = _pool.removeAllCollateral(testIndex);
        assertEq(collateralRemoved, collateralToWithdraw);
        assertEq(lpRedeemed, 7_436.90329482876744787715 * 1e27);
    }

    function testRemoveCollateralRequireChecks() external {
        uint256 testIndex = 6348;

        // should revert if no collateral in the bucket
        changePrank(_lender);
        vm.expectRevert("S:RAC:NO_COL");
        _pool.removeAllCollateral(testIndex);
        vm.expectRevert("S:RC:INSUF_COL");
        _pool.removeCollateral(3.50 * 1e18, testIndex);

        // another actor deposits some collateral
        deal(address(_collateral), _bidder,  100 * 1e18);
        changePrank(_bidder);
        _collateral.approve(address(_pool), 100 * 1e18);
        _pool.addCollateral(0.65 * 1e18, testIndex);

        // should revert if insufficient collateral in the bucket
        changePrank(_lender);
        vm.expectRevert("S:RC:INSUF_COL");
        _pool.removeCollateral(1.25 * 1e18, testIndex);

        // should revert if actor does not have LP
        vm.expectRevert("S:RAC:NO_CLAIM");
        _pool.removeAllCollateral(testIndex);
        vm.expectRevert("S:RC:INSUF_LPS");
        _pool.removeCollateral(0.32 * 1e18, testIndex);
    }

    function testMoveCollateral() external {
        // actor deposits collateral into two buckets
        changePrank(_lender);
        deal(address(_collateral), _lender, 20 * 1e18);
        _collateral.approve(address(_pool), 20 * 1e18);
        _pool.addCollateral(16.3 * 1e18, 3333);
        _pool.addCollateral(3.7 * 1e18, 3334);
        skip(2 hours);

        // should revert if bucket doesn't have enough collateral to move
        vm.expectRevert("S:MC:INSUF_COL");
        _pool.moveCollateral(5 * 1e18, 3334, 3333);

        // should revert if actor doesn't have enough LP to move specified amount
        changePrank(_borrower);
        _pool.addCollateral(1.3 * 1e18, 3334);
        changePrank(_lender);
        vm.expectRevert("S:MC:INSUF_LPS");
        _pool.moveCollateral(5 * 1e18, 3334, 3333);

        // actor moves all their LP into one bucket
        vm.expectEmit(true, true, true, true);
        emit MoveCollateral(_lender, 3334, 3333, 3.7 * 1e18);
        _pool.moveCollateral(3.7 * 1e18, 3334, 3333);

        // check buckets
        (, uint256 collateral, uint256 lpb, ) = _pool.bucketAt(3333);
        assertEq(collateral, 20 * 1e18);
        assertEq(lpb, 1212.5476695591403933005 * 1e27);
        (, collateral, lpb, ) = _pool.bucketAt(3334);
        assertEq(collateral, 1.3 * 1e18);
        assertEq(lpb, 78.423481115765299705 * 1e27);

        // check actor LP
        (uint256 lpBalance, ) = _pool.bucketLenders(3333, address(_lender));
        assertEq(lpBalance, 1212.5476695591403933005 * 1e27);
        (lpBalance, ) = _pool.bucketLenders(3334, address(_lender));
        assertEq(lpBalance, 0);
    }

    function testPledgeCollateralFromDifferentActor() external {
        // check initial pool state
        assertEq(_pool.pledgedCollateral(),   0);
        assertEq(_collateral.balanceOf(_borrower),  150 * 1e18);
        assertEq(_collateral.balanceOf(_borrower2), 100 * 1e18);

        // borrower deposits 100 collateral
        changePrank(_borrower2);
        vm.expectEmit(true, true, false, true);
        emit PledgeCollateral(_borrower, 100 * 1e18);
        vm.expectEmit(true, true, false, true);
        emit Transfer(_borrower2, address(_pool), 100 * 1e18);
        _pool.pledgeCollateral(_borrower, 100 * 1e18, address(0), address(0));

        // check pool state collateral accounting updated properly
        assertEq(_pool.pledgedCollateral(),         100 * 1e18);
        assertEq(_collateral.balanceOf(_borrower),  150 * 1e18);
        assertEq(_collateral.balanceOf(_borrower2), 0);
    }

    // TODO: add collateralization, utilization and encumberance test? -> use hardcoded amounts in pure functions without creaitng whole pool flows
}
