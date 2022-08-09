// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.14;

import { ERC20Pool }        from "../../erc20/ERC20Pool.sol";
import { ERC20PoolFactory } from "../../erc20/ERC20PoolFactory.sol";

import { BucketMath } from "../../libraries/BucketMath.sol";
import { Maths }      from "../../libraries/Maths.sol";

import { DSTestPlus }                             from "../utils/DSTestPlus.sol";
import { CollateralToken, QuoteToken }            from "../utils/Tokens.sol";
import { UserWithCollateral, UserWithQuoteToken } from "../utils/Users.sol";

contract ERC20ScaledCollateralTest is DSTestPlus {

    uint256 public constant LARGEST_AMOUNT = type(uint256).max / 10**27;

    address            internal _poolAddress;
    CollateralToken    internal _collateral;
    ERC20Pool          internal _pool;
    QuoteToken         internal _quote;
    UserWithCollateral internal _borrower;
    UserWithCollateral internal _borrower2;
    UserWithQuoteToken internal _lender;
    UserWithCollateral internal _bidder;

    function setUp() external {
        _collateral  = new CollateralToken();
        _quote       = new QuoteToken();
        _poolAddress = new ERC20PoolFactory().deployPool(address(_collateral), address(_quote), 0.05 * 10**18);
        _pool        = ERC20Pool(_poolAddress);

        _borrower   = new UserWithCollateral();
        _bidder     = new UserWithCollateral();
        _lender     = new UserWithQuoteToken();

        _collateral.mint(address(_borrower), 150 * 1e18);
        _quote.mint(address(_bidder), 200_000 * 1e18);
        _quote.mint(address(_lender), 200_000 * 1e18);

        _borrower.approveToken(_collateral, address(_pool), 150 * 1e18);
        _borrower.approveToken(_quote,      address(_pool), 200_000 * 1e18);

        _bidder.approveToken(_quote,  address(_pool), 200_000 * 1e18);
        _lender.approveToken(_quote,  address(_pool), 200_000 * 1e18);
    }

    /**
     *  @notice With 1 lender and 1 borrower test pledgeCollateral, borrow, and pullCollateral.
     */
    function testAddPullCollateral() external {
        uint256 depositPriceHighest = 2550;
        uint256 depositPriceHigh    = 2551;
        uint256 depositPriceMed     = 2552;

        // lender deposits 10000 Quote into 3 buckets
        _lender.addQuoteToken(_pool, 10_000 * 1e18, depositPriceHighest);
        _lender.addQuoteToken(_pool, 10_000 * 1e18, depositPriceHigh);
        _lender.addQuoteToken(_pool, 10_000 * 1e18, depositPriceMed);

        // check initial pool state
        assertEq(_pool.htp(), 0);
        assertEq(_pool.lup(), BucketMath.MAX_PRICE);

        assertEq(_pool.treeSum(),      30_000 * 1e18);
        assertEq(_pool.borrowerDebt(), 0);
        assertEq(_pool.lenderDebt(),   0);

        assertEq(_pool.pledgedCollateral(),   0);
        assertEq(_collateral.balanceOf(address(_borrower)), 150 * 1e18);

        // borrower deposits 100 collateral
        vm.expectEmit(true, true, false, true);
        emit PledgeCollateral(address(_borrower), 100 * 1e18);
        _borrower.pledgeCollateral(_pool, 100 * 1e18, address(0), address(0));

        // check pool state collateral accounting updated successfully
        assertEq(_pool.pledgedCollateral(), 100 * 1e18);
        assertEq(_collateral.balanceOf(address(_borrower)), 50 * 1e18);

        // get a 21_000 Quote loan
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(_pool), address(_borrower), 21_000 * 1e18);
        vm.expectEmit(true, true, false, true);
        emit Borrow(address(_borrower), 2_981.007422784467321543 * 1e18, 21_000 * 1e18);
        _borrower.borrow(_pool, 21_000 * 1e18, 3000, address(0), address(0));

        // check pool state
        assertEq(_pool.htp(), 210.201923076923077020 * 1e18);
        assertEq(_pool.lup(), 2_981.007422784467321543 * 1e18);

        assertEq(_pool.treeSum(),           30_000 * 1e18);
        assertEq(_pool.borrowerDebt(),      21_020.192307692307702000 * 1e18);
        assertEq(_pool.lenderDebt(),        21_000 * 1e18);
        assertEq(_pool.pledgedCollateral(), 100 * 1e18);

        assertEq(_pool.encumberedCollateral(_pool.borrowerDebt(), _pool.lup()), 7.051372011699988577 * 1e18);
        assertEq(_pool.encumberedCollateral(_pool.lenderDebt(), _pool.lup()),   7.044598359431304627 * 1e18);

        // check borrower state
        (uint256 borrowerDebt, , uint256 borrowerCollateral, ) = _pool.borrowerInfo(address(_borrower));
        assertEq(borrowerDebt,       _pool.borrowerDebt());
        assertEq(borrowerCollateral, _pool.pledgedCollateral());
        assertEq(
            _pool.encumberedCollateral(_pool.borrowerDebt(), _pool.lup()),
            _pool.encumberedCollateral(borrowerDebt, _pool.lup())
        );
        assertEq(_collateral.balanceOf(address(_borrower)), 50 * 1e18);

        assertEq(_pool.borrowerCollateralization(borrowerDebt, borrowerCollateral, _pool.lup()), _pool.poolCollateralization());

        // pass time to allow interest to accrue
        skip(864000);

        // remove some of the collateral
        vm.expectEmit(true, true, false, true);
        emit PullCollateral(address(_borrower), 50 * 1e18);
        _borrower.pullCollateral(_pool, 50 * 1e18, address(0), address(0));

        // check borrower state
        (borrowerDebt, , borrowerCollateral, ) = _pool.borrowerInfo(address(_borrower));
        assertEq(borrowerDebt,       _pool.borrowerDebt());
        assertEq(borrowerCollateral, _pool.pledgedCollateral());
        assertEq(
            _pool.encumberedCollateral(_pool.borrowerDebt(), _pool.lup()),
            _pool.encumberedCollateral(borrowerDebt, _pool.lup())
        );
        assertEq(_collateral.balanceOf(address(_borrower)), 100 * 1e18);

        assertEq(_pool.borrowerCollateralization(borrowerDebt, borrowerCollateral, _pool.lup()), _pool.poolCollateralization());

        // remove all of the remaining unencumbered collateral
        uint256 unencumberedCollateral = borrowerCollateral - _pool.encumberedCollateral(borrowerDebt, _pool.lup());
        vm.expectEmit(true, true, false, true);
        emit PullCollateral(address(_borrower), unencumberedCollateral);
        _borrower.pullCollateral(_pool, unencumberedCollateral, address(0), address(0));

        // check pool state
        assertEq(_pool.htp(), 2_989.185764499773229142 * 1e18);
        assertEq(_pool.lup(), 2_981.007422784467321543 * 1e18);

        assertEq(_pool.treeSum(),           30_025.933063898944800000 * 1e18);
        assertEq(_pool.borrowerDebt(),      21_049.006823135579696033 * 1e18);
        assertEq(_pool.lenderDebt(),        21_000 * 1e18);
        assertEq(_pool.pledgedCollateral(), _pool.encumberedCollateral(_pool.borrowerDebt(), _pool.lup()));

        assertEq(_pool.encumberedCollateral(_pool.borrowerDebt(), _pool.lup()), 7.061038044472344858 * 1e18);
        assertEq(_pool.encumberedCollateral(_pool.lenderDebt(), _pool.lup()),   7.044598359431304627 * 1e18);

        // check borrower state
        (borrowerDebt, , borrowerCollateral, ) = _pool.borrowerInfo(address(_borrower));
        assertEq(borrowerDebt,       _pool.borrowerDebt());
        assertEq(borrowerCollateral, _pool.pledgedCollateral());
        assertEq(
            _pool.encumberedCollateral(_pool.borrowerDebt(), _pool.lup()),
            _pool.encumberedCollateral(borrowerDebt, _pool.lup())
        );
        assertEq(_collateral.balanceOf(address(_borrower)), 142.938961955527655142 * 1e18);

        assertEq(_pool.borrowerCollateralization(borrowerDebt, borrowerCollateral, _pool.lup()), _pool.poolCollateralization());
    }

    /**
     *  @notice 1 borrower tests reverts in pullCollateral.
     *          Reverts:
     *              Attempts to remove more than available unencumbered collateral.
     */
    function testPullCollateralRequireEnoughCollateral() external {
        uint256 testCollateralAmount = 100 * 1e18;

        // should revert if trying to remove more collateral than is available
        vm.expectRevert("S:PC:NOT_ENOUGH_COLLATERAL");
        _borrower.pullCollateral(_pool, testCollateralAmount, address(0), address(0));

        // borrower deposits 100 collateral
        vm.expectEmit(true, true, true, true);
        emit PledgeCollateral(address(_borrower), testCollateralAmount);
        _borrower.pledgeCollateral(_pool, testCollateralAmount, address(0), address(0));

        // should be able to now remove collateral
        vm.expectEmit(true, true, true, true);
        emit PullCollateral(address(_borrower), testCollateralAmount);
        _borrower.pullCollateral(_pool, testCollateralAmount, address(0), address(0));
    }

    /**
     *  @notice 1 actor tests addCollateral and removeCollateral.
     */
    function testRemoveCollateral() external {
        // test setup
        uint256 testIndex = 2550;
        uint256 priceAtTestIndex = _pool.indexToPrice(testIndex);
        _collateral.mint(address(_bidder), 100 * 1e18);
        _bidder.approveToken(_collateral, address(_pool), 100 * 1e18);

        // actor deposits collateral into a bucket
        uint256 collateralToDeposit = 4 * 1e18;
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(_bidder), address(_pool), collateralToDeposit);
        vm.expectEmit(true, true, false, true);
        emit AddCollateral(address(_bidder), priceAtTestIndex, collateralToDeposit);
        _bidder.addCollateral(_pool, collateralToDeposit, testIndex);

        // check bucket state
        (uint256 lpAccumulator, uint256 availableCollateral) = _pool.buckets(testIndex);
        assertEq(availableCollateral, collateralToDeposit);
        assertEq(_pool.lpBalance(testIndex, address(_bidder)), 12_043.56808879152623138 * 1e27);

        // check bucket state
        (lpAccumulator, availableCollateral) = _pool.buckets(testIndex);
        assertEq(availableCollateral, collateralToDeposit);
        assertGt(availableCollateral, 0);
        assertEq(_pool.lpBalance(testIndex, address(_bidder)), 12_043.568088791526231380000000000 * 1e27);

        // check pool state and balances
        assertEq(_collateral.balanceOf(address(_lender)), 0);
        assertEq(_collateral.balanceOf(address(_pool)), collateralToDeposit);
        assertEq(_quote.balanceOf(address(_pool)),        0);

        // actor withdraws their collateral
        _bidder.removeCollateral(_pool, collateralToDeposit, testIndex);
    }

    /**
     *  @notice 1 lender, 1 bidder tests reverts in removeCollateral.
     *          Reverts:
     *              Attempts to remove collateral when there is none in the bucket.
     *              Attempts to remove collateral when lpBalance is 0.
     */
    function testRemoveCollateralRequireChecks() external {
        // test setup
        uint256 testIndex = 2550;
        uint256 priceAtTestIndex = _pool.indexToPrice(testIndex);
        assertEq(priceAtTestIndex, 3_010.892022197881557845 * 1e18);
        _collateral.mint(address(_bidder), 100 * 1e18);
        _bidder.approveToken(_collateral, address(_pool), 100 * 1e18);

        // lender adds quote to pool
        _lender.addQuoteToken(_pool, 10_000 * 1e18, 2550);

        // should revert if insufficient collateral is available in the bucket
        vm.expectRevert("S:RC:AMT_GT_COLLAT");
        _lender.removeCollateral(_pool, 5 * 1e18, testIndex);

        // bidder adds collateral
        uint256 availableCollateral = 4 * 1e18;
        _bidder.addCollateral(_pool, availableCollateral, 2550);

        // should revert if attempting to remove more than lp balance allows
        vm.expectRevert("S:RC:INSUF_LP_BAL");
        _lender.removeCollateral(_pool, 4 * 1e18, testIndex);

        // should be able to remove collateral if properly specified
        uint256 lpBalance = _pool.lpBalance(testIndex, address(_bidder));
        vm.expectEmit(true, true, true, true);
        emit Transfer(address(_pool), address(_bidder), availableCollateral);
        vm.expectEmit(true, true, true, true);
        emit RemoveCollateral(address(_bidder), priceAtTestIndex, availableCollateral, lpBalance);
        _bidder.removeCollateral(_pool, availableCollateral, testIndex);
    }

    /**
     *  @notice 1 lender, 1 bidder tests purchasing quote token with collateral.
     */
    function testPurchaseCollateral() external {
        // test setup
        uint256 testIndex = 2550;
        uint256 priceAtTestIndex = _pool.indexToPrice(testIndex);
        assertEq(priceAtTestIndex, 3_010.892022197881557845 * 1e18);
        _collateral.mint(address(_bidder), 100 * 1e18);
        _bidder.approveToken(_collateral, address(_pool), 100 * 1e18);

        // lender adds initial quote to pool
        _lender.addQuoteToken(_pool, 10_000 * 1e18, testIndex);

        // bidder deposits collateral into a bucket
        // FIXME: When bidder purchases with Maths.wdiv(10_000 * 1e18, priceAtTestIndex),
        //  their LP balance is slightly over 10k due to rounding error.  Makes line 290 ugly.
        uint256 collateralToPurchaseWith = 4 * 1e18;
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(_bidder), address(_pool), collateralToPurchaseWith);
        vm.expectEmit(true, true, false, true);
        emit AddCollateral(address(_bidder), priceAtTestIndex, collateralToPurchaseWith);
        _bidder.addCollateral(_pool, collateralToPurchaseWith, testIndex);

        // check bucket state
        (uint256 lpAccumulator, uint256 availableCollateral) = _pool.buckets(testIndex);
        assertEq(availableCollateral, collateralToPurchaseWith);
        assertEq(_pool.lpBalance(testIndex, address(_lender)), 10_000 * 1e27);
        assertEq(_pool.lpBalance(testIndex, address(_bidder)), 12_043.56808879152623138 * 1e27);

        // bidder uses their LP to purchase all quote token in the bucket
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(_pool), address(_bidder), 10_000 * 1e18);
        vm.expectEmit(true, true, false, true);
        emit RemoveQuoteToken(address(_bidder), priceAtTestIndex, 10_000 * 1e18, _pool.lup());
        _bidder.removeQuoteToken(_pool, 10_000 * 1e18, testIndex);

        // check bucket state
        (lpAccumulator, availableCollateral) = _pool.buckets(testIndex);
        assertEq(availableCollateral, collateralToPurchaseWith);
        assertGt(availableCollateral, 0);
        assertEq(_pool.lpBalance(testIndex, address(_lender)), 10_000 * 1e27);
        assertEq(_pool.lpBalance(testIndex, address(_bidder)), 2_043.56808879152623138 * 1e27);

        // check pool state and balances
        assertEq(_collateral.balanceOf(address(_lender)), 0);
        assertEq(_collateral.balanceOf(address(_pool)),   collateralToPurchaseWith);
        assertEq(_quote.balanceOf(address(_pool)),        0);

        // lender exchanges their LP for collateral
        uint256 exchangeRate = _pool.exchangeRate(testIndex);
        uint256 lpBalance = _pool.lpBalance(testIndex, address(_lender));
        uint256 lpValueInQuote = lpBalance * exchangeRate / 1e36;
        assertGe(lpValueInQuote, 10_000 * 1e18);
        uint256 lpValueInCollateral = Maths.wad(Maths.rdiv(lpValueInQuote, Maths.ray(priceAtTestIndex)));
        assertGe(lpValueInCollateral, 2 * 1e18);
        vm.expectEmit(true, true, true, true);
        emit Transfer(address(_pool), address(_lender), lpValueInCollateral);
        // FIXME: LPs redeemed for collateral doesn't match the event.
//        vm.expectEmit(true, true, true, true);
//        emit RemoveCollateral(address(_lender), priceAtTestIndex, lpValueInCollateral, lpBalance);
        _lender.removeCollateral(_pool, lpValueInCollateral, testIndex);

        // TODO: bidder still has some collateral in there
//        // check pool state and balances
//        assertEq(_collateral.balanceOf(address(_lender)), availableCollateral);
//        assertEq(_collateral.balanceOf(address(_pool)),   0);
//        assertEq(_quote.balanceOf(address(_pool)),        0);
//
//        // check bucket state
//        (lpAccumulator, availableCollateral) = _pool.buckets(testIndex);
//        assertEq(availableCollateral, 0);
//        assertEq(lpAccumulator,       0);
//        assertEq(lpAccumulator,       _pool.lpBalance(testIndex, address(_lender)));
    }

    // TODO: add collateralization, utilization and encumberance test? -> use hardcoded amounts in pure functions without creaitng whole pool flows

}
