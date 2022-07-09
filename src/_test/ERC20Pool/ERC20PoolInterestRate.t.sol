// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.14;

import { ERC20Pool }        from "../../erc20/ERC20Pool.sol";
import { ERC20PoolFactory } from "../../erc20/ERC20PoolFactory.sol";

import { DSTestPlus }                             from "../utils/DSTestPlus.sol";
import { CollateralToken, QuoteToken }            from "../utils/Tokens.sol";
import { UserWithCollateral, UserWithQuoteToken } from "../utils/Users.sol";

contract ERC20PoolInterestRateTest is DSTestPlus {

    address            internal _poolAddress;
    CollateralToken    internal _collateral;
    ERC20Pool          internal _pool;
    QuoteToken         internal _quote;
    UserWithCollateral internal _borrower;
    UserWithQuoteToken internal _lender;

    function setUp() external {
        _collateral  = new CollateralToken();
        _quote       = new QuoteToken();
        _poolAddress = new ERC20PoolFactory().deployPool(address(_collateral), address(_quote), 0.05 * 10**18);
        _pool        = ERC20Pool(_poolAddress);

        _borrower = new UserWithCollateral();
        _lender   = new UserWithQuoteToken();

        _collateral.mint(address(_borrower), 500_000 * 1e18);
        _quote.mint(address(_lender), 200_000 * 1e18);
        _borrower.approveToken(_collateral, address(_pool), 500_000 * 1e18);
        _borrower.approveToken(_quote, address(_pool), 50_000 * 1e18);
        _lender.approveToken(_quote, address(_pool), 200_000 * 1e18);
    }

    /**
     *  @notice With 1 lender and 1 borrower quote token is deposited then borrower adds collateral and borrows interest.
     *          Rate is checked to be greater than current one.
     */
    function testUpdateInterestRateIncrease() external {
        uint256 priceHigh  = _p4000;
        uint256 priceMed   = _p3514;
        uint256 priceLow   = _p2503;

        assertEq(_pool.interestRate(),       0.05 * 1e18);
        assertEq(_pool.interestRateUpdate(), 0);

        // raise pool utilization
        // lender deposits 60_000 DAI in 3 buckets
        _lender.addQuoteToken(_pool, 10_000 * 1e18, priceHigh);
        _lender.addQuoteToken(_pool, 20_000 * 1e18, priceMed);
        _lender.addQuoteToken(_pool, 30_000 * 1e18, priceLow);

        // borrower deposits 4000 MKR collateral and draws debt
        _borrower.addCollateral(_pool, 4_000 * 1e18);
        _borrower.borrow(_pool, 53_000 * 1e18, 2_500 * 1e18);

        skip(46800);

        // force interest rate increase
        vm.expectEmit(true, true, false, true);
        emit UpdateInterestRate(0.05 * 1e18, 0.055 * 1e18);
        _lender.addQuoteToken(_pool, 100 * 1e18, priceHigh);

        assertEq(_pool.getPoolActualUtilization(), 0.881871292670569213 * 1e18);
        assertEq(_pool.getPoolTargetUtilization(), 0.005292942977620046 * 1e18);

        assertEq(_pool.interestRate(),               0.055 * 1e18);
        assertEq(_pool.interestRateUpdate(),         46800);
        assertEq(_pool.lastInflatorSnapshotUpdate(), 46800);
    }

    /**
     *  @notice With 1 lender and 1 borrower quote token is deposited then borrower adds collateral and borrows interest.
     *          Rate is checked to be lower than current one.
     */
    function testUpdateInterestRateDecrease() external {
        _lender.addQuoteToken(_pool, 10_000 * 1e18, _p3514);
        _lender.addQuoteToken(_pool, 20_000 * 1e18, _p3010);
        _lender.addQuoteToken(_pool, 20_000 * 1e18, _p2503);
        _lender.addQuoteToken(_pool, 50_000 * 1e18, _p502);
        _lender.addQuoteToken(_pool, 10_000 * 1e18, _p100);
        skip(864000);

        _borrower.addCollateral(_pool, 100 * 1e18);
        _borrower.borrow(_pool, 46_000 * 1e18, 2_000 * 1e18);

        assertEq(_pool.interestRate(),       0.055 * 1e18);
        assertEq(_pool.interestRateUpdate(), 864000);

        // force interest rate increase
        skip(864000);
        vm.expectEmit(true, true, false, true);
        emit UpdateInterestRate(0.055 * 1e18, 0.0605 * 1e18);
        _lender.addQuoteToken(_pool, 1_000 * 1e18, _p502);
        assertEq(_pool.interestRate(),       0.0605 * 1e18);
        assertEq(_pool.interestRateUpdate(), 1728000);

        _borrower.repay(_pool, 45_000 * 1e18);

        // force interest rate decrease
        skip(864000);
        vm.expectEmit(true, true, false, true);
        emit UpdateInterestRate(0.0605 * 1e18, 0.05445 * 1e18);
        _lender.removeQuoteToken(_pool, 50_000 * 1e18, _p2503);
        assertEq(_pool.interestRate(),       0.05445 * 1e18);
        assertEq(_pool.interestRateUpdate(), 2592000);
    }

    /**
     *  @notice Ensure an underutilized and undercollateralized pool does not produce an underflow.
     */
    function testUndercollateralized() external {
        uint256 price = _p3514;

        _lender.addQuoteToken(_pool, 10_000 * 1e18, price);
        skip(14);

        // borrower utilizes the entire pool
        _borrower.addCollateral(_pool, 0.000284548895761533 * 1e18);
        _borrower.borrow(_pool, 1 * 1e18 - 0.000961538461538462 * 1e18, 0); // borrow 1 minus fee
        uint256 lastRate = _pool.interestRate();
        skip(3600 * 24);

        // debt accumulates, and the borrower becomes undercollateralized
        _borrower.repay(_pool, 1); // repay 1 WAD to trigger accumulation
        (, , , , uint256 collateralization, , ) = _pool.getBorrowerInfo(address(_borrower));
        assertLt(collateralization, 1 * 1e18);

        // rate should not change while pool is undercollateralized
        assertEq(_pool.interestRate(), lastRate);
    }

}

contract ERC20PoolInterestRateTriggerTest is DSTestPlus {

    address            internal _poolAddress;
    CollateralToken    internal _collateral;
    ERC20Pool          internal _pool;
    QuoteToken         internal _quote;
    UserWithCollateral internal _borrower;
    UserWithCollateral internal _borrower1;
    UserWithQuoteToken internal _lender;

    function setUp() external {
        _collateral  = new CollateralToken();
        _quote       = new QuoteToken();
        _poolAddress = new ERC20PoolFactory().deployPool(address(_collateral), address(_quote), 0.05 * 10**18);
        _pool        = ERC20Pool(_poolAddress);

        _borrower  = new UserWithCollateral();
        _borrower1 = new UserWithCollateral();
        _lender    = new UserWithQuoteToken();

        _collateral.mint(address(_borrower),  500_000 * 1e18);
        _collateral.mint(address(_borrower1), 500_000 * 1e18);
        _quote.mint(address(_lender), 200_000 * 1e18);
        _borrower.approveToken(_collateral, address(_pool), 500_000 * 1e18);
        _borrower.approveToken(_quote, address(_pool), 100_000 * 1e18);
        _borrower1.approveToken(_collateral, address(_pool), 500_000 * 1e18);
        _borrower1.approveToken(_quote, address(_pool), 100_000 * 1e18);
        _lender.approveToken(_quote, address(_pool), 200_000 * 1e18);

        _lender.addQuoteToken(_pool, 10_000 * 1e18, _p3514);
        _lender.addQuoteToken(_pool, 20_000 * 1e18, _p3010);
        _lender.addQuoteToken(_pool, 20_000 * 1e18, _p2503);
        _lender.addQuoteToken(_pool, 50_000 * 1e18, _p502);
        _lender.addQuoteToken(_pool, 10_000 * 1e18, _p100);
        skip(864000);

        _borrower.addCollateral(_pool, 100 * 1e18);
        _borrower.borrow(_pool, 46_000 * 1e18, 2_000 * 1e18);
    }

    /**
     *  @notice Test interest rate updates on add collateral action.
     */
    function testUpdateInterestRateOnAddCollateral() external {
        assertEq(_pool.interestRate(),       0.055 * 1e18);
        assertEq(_pool.interestRateUpdate(), 864000);

        // no update if less than 12 hours passed
        skip(36000);
        _borrower.addCollateral(_pool, 100 * 1e18);
        assertEq(_pool.interestRate(),       0.055 * 1e18);
        assertEq(_pool.interestRateUpdate(), 864000);

        // update if more than 12 hours passed
        skip(36000);
        vm.expectEmit(true, true, false, true);
        emit UpdateInterestRate(0.055 * 1e18, 0.0605 * 1e18);
        _borrower.addCollateral(_pool, 100 * 1e18);
        assertEq(_pool.interestRate(),       0.0605 * 1e18);
        assertEq(_pool.interestRateUpdate(), 936000);
    }

    /**
     *  @notice Test interest rate updates on borrow action.
     */
    function testUpdateInterestRateOnBorrow() external {
        assertEq(_pool.interestRate(),       0.055 * 1e18);
        assertEq(_pool.interestRateUpdate(), 864000);

        // no update if less than 12 hours passed
        skip(36000);
        _borrower.borrow(_pool, 100 * 1e18, 2_000 * 1e18);
        assertEq(_pool.interestRate(),       0.055 * 1e18);
        assertEq(_pool.interestRateUpdate(), 864000);

        // update if more than 12 hours passed
        skip(36000);
        vm.expectEmit(true, true, false, true);
        emit UpdateInterestRate(0.055 * 1e18, 0.0605 * 1e18);
        _borrower.borrow(_pool, 100 * 1e18, 2_000 * 1e18);
        assertEq(_pool.interestRate(),       0.0605 * 1e18);
        assertEq(_pool.interestRateUpdate(), 936000);
    }

    /**
     *  @notice Test interest rate updates on remove collateral action.
     */
    function testUpdateInterestRateOnRemoveCollateral() external {
        assertEq(_pool.interestRate(),       0.055 * 1e18);
        assertEq(_pool.interestRateUpdate(), 864000);

        // no update if less than 12 hours passed
        skip(36000);
        _borrower.removeCollateral(_pool, 1 * 1e18);
        assertEq(_pool.interestRate(),       0.055 * 1e18);
        assertEq(_pool.interestRateUpdate(), 864000);

        // update if more than 12 hours passed
        skip(36000);
        vm.expectEmit(true, true, false, true);
        emit UpdateInterestRate(0.055 * 1e18, 0.0605 * 1e18);
        _borrower.removeCollateral(_pool, 1 * 1e18);
        assertEq(_pool.interestRate(),       0.0605 * 1e18);
        assertEq(_pool.interestRateUpdate(), 936000);
    }

    /**
     *  @notice Test interest rate updates on repay action.
     */
    function testUpdateInterestRateOnRepay() external {
        assertEq(_pool.interestRate(),       0.055 * 1e18);
        assertEq(_pool.interestRateUpdate(), 864000);

        // no update if less than 12 hours passed
        skip(36000);
        _borrower.repay(_pool, 1 * 1e18);
        assertEq(_pool.interestRate(),       0.055 * 1e18);
        assertEq(_pool.interestRateUpdate(), 864000);

        // update if more than 12 hours passed
        skip(36000);
        vm.expectEmit(true, true, false, true);
        emit UpdateInterestRate(0.055 * 1e18, 0.0605 * 1e18);
        _borrower.repay(_pool, 1 * 1e18);
        assertEq(_pool.interestRate(),       0.0605 * 1e18);
        assertEq(_pool.interestRateUpdate(), 936000);
    }

    /**
     *  @notice Test interest rate updates on add quote token action.
     */
    function testUpdateInterestRateOnAddQuoteToken() external {
        assertEq(_pool.interestRate(),       0.055 * 1e18);
        assertEq(_pool.interestRateUpdate(), 864000);

        // no update if less than 12 hours passed
        skip(36000);
        _lender.addQuoteToken(_pool, 1_000 * 1e18, _p502);
        assertEq(_pool.interestRate(),       0.055 * 1e18);
        assertEq(_pool.interestRateUpdate(), 864000);

        // update if more than 12 hours passed
        skip(36000);
        vm.expectEmit(true, true, false, true);
        emit UpdateInterestRate(0.055 * 1e18, 0.0605 * 1e18);
        _lender.addQuoteToken(_pool, 1_000 * 1e18, _p502);
        assertEq(_pool.interestRate(),       0.0605 * 1e18);
        assertEq(_pool.interestRateUpdate(), 936000);
    }

    /**
     *  @notice Test interest rate updates on move quote token action.
     */
    function testUpdateInterestRateOnMoveQuoteToken() external {
        assertEq(_pool.interestRate(),       0.055 * 1e18);
        assertEq(_pool.interestRateUpdate(), 864000);

        // no update if less than 12 hours passed
        skip(36000);
        _lender.moveQuoteToken(_pool, 1_000 * 1e18, _p502, _p2503);
        assertEq(_pool.interestRate(),       0.055 * 1e18);
        assertEq(_pool.interestRateUpdate(), 864000);

        // update if more than 12 hours passed
        skip(36000);
        vm.expectEmit(true, true, false, true);
        emit UpdateInterestRate(0.055 * 1e18, 0.0605 * 1e18);
        _lender.moveQuoteToken(_pool, 1_000 * 1e18, _p502, _p2503);
        assertEq(_pool.interestRate(),       0.0605 * 1e18);
        assertEq(_pool.interestRateUpdate(), 936000);
    }

    /**
     *  @notice Test interest rate updates on remove quote token action.
     */
    function testUpdateInterestRateOnRemoveQuoteToken() external {
        assertEq(_pool.interestRate(),       0.055 * 1e18);
        assertEq(_pool.interestRateUpdate(), 864000);

        // no update if less than 12 hours passed
        skip(36000);
        _lender.removeQuoteToken(_pool, 5_000 * 1e18, _p2503);
        assertEq(_pool.interestRate(),       0.055 * 1e18);
        assertEq(_pool.interestRateUpdate(), 864000);
        _borrower.addCollateral(_pool, 1_000 * 1e18);

        // update if more than 12 hours passed
        skip(36000);
        vm.expectEmit(true, true, false, true);
        emit UpdateInterestRate(0.055 * 1e18, 0.0605 * 1e18);
        _lender.removeQuoteToken(_pool, 5_000 * 1e18, _p2503);
        assertEq(_pool.interestRate(),       0.0605 * 1e18);
        assertEq(_pool.interestRateUpdate(), 936000);
    }

    /**
     *  @notice Test interest rate updates on liquidate action.
     */
    function skip_testUpdateInterestRateOnLiquidate() external {
        _borrower1.addCollateral(_pool, 1_000 * 1e18);
        _borrower1.borrow(_pool, 60_000 * 1e18, 1 * 1e18);

        assertEq(_pool.interestRate(),       0.055 * 1e18);
        assertEq(_pool.interestRateUpdate(), 864000);

        skip(48000);
        vm.expectEmit(true, true, false, true);
        emit UpdateInterestRate(0.055 * 1e18, 0.0605 * 1e18);
        _lender.liquidate(_pool, address(_borrower));
        assertEq(_pool.interestRate(),       0.0605 * 1e18);
        assertEq(_pool.interestRateUpdate(), 912000);
    }

    /**
     *  @notice Test interest rate updates on purchase bid action.
     */
    function testUpdateInterestRateOnPurchaseBid() external {
        _borrower1.addCollateral(_pool, 1_000 * 1e18);

        assertEq(_pool.interestRate(),       0.055 * 1e18);
        assertEq(_pool.interestRateUpdate(), 864000);

        // no update if less than 12 hours passed
        skip(36000);
        _borrower1.purchaseBid(_pool, 1_000 * 1e18, _p3514);
        assertEq(_pool.interestRate(),       0.055 * 1e18);
        assertEq(_pool.interestRateUpdate(), 864000);

        // update if more than 12 hours passed
        skip(36000);
        vm.expectEmit(true, true, false, true);
        emit UpdateInterestRate(0.055 * 1e18, 0.0605 * 1e18);
        _borrower1.purchaseBid(_pool, 1_000 * 1e18, _p3514);
        assertEq(_pool.interestRate(),       0.0605 * 1e18);
        assertEq(_pool.interestRateUpdate(), 936000);
    }

    /**
     *  @notice Test interest rate updates on claim collateral bid action.
     */
    function skip_test_UpdateInterestRateOnClaimCollateral() external {
        _borrower1.addCollateral(_pool, 1_000 * 1e18);
        _borrower1.borrow(_pool, 60_000 * 1e18, 1 * 1e18);

        _lender.liquidate(_pool, address(_borrower));
        assertEq(_pool.interestRate(),       0.055 * 1e18);
        assertEq(_pool.interestRateUpdate(), 864000);

        // no update if less than 12 hours passed
        skip(36000);
        _lender.claimCollateral(_pool, 1 * 1e18, _p3514);

        // update if more than 12 hours passed
        skip(36000);
        vm.expectEmit(true, true, false, true);
        emit UpdateInterestRate(0.055 * 1e18, 0.0605 * 1e18);
        _lender.claimCollateral(_pool, 1 * 1e18, _p3514);
        assertEq(_pool.interestRate(),       0.0605 * 1e18);
        assertEq(_pool.interestRateUpdate(), 936000);
    }
}
