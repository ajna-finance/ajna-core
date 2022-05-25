// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.11;

import { PRBMathUD60x18 } from "@prb-math/contracts/PRBMathUD60x18.sol";

import { ERC20Pool }        from "../ERC20Pool.sol";
import { ERC20PoolFactory } from "../ERC20PoolFactory.sol";

import { DSTestPlus }                             from "./utils/DSTestPlus.sol";
import { CollateralToken, QuoteToken }            from "./utils/Tokens.sol";
import { UserWithCollateral, UserWithQuoteToken } from "./utils/Users.sol";

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
        _poolAddress = new ERC20PoolFactory().deployPool(address(_collateral), address(_quote));
        _pool        = ERC20Pool(_poolAddress);  

        _borrower   = new UserWithCollateral();
        _lender     = new UserWithQuoteToken();

        _collateral.mint(address(_borrower), 100 * 1e18);
        _quote.mint(address(_lender), 200_000 * 1e18);
        _borrower.approveToken(_collateral, address(_pool), 100 * 1e18);
        _borrower.approveToken(_quote, address(_pool), 1);
        _lender.approveToken(_quote, address(_pool), 200_000 * 1e18);
    }

    /**
     *  @notice With 1 lender and 1 borrower quote token is deposited then borrower adds collateral and borrows interest.
     *          Rate is checked for correctness.
     */
    function testUpdateInterestRate() external {
        uint256 priceHigh  = _p4000;
        uint256 priceMed   = _p3514;
        uint256 priceLow   = _p2503;
        uint256 updateTime = _pool.previousRateUpdate();

        assertEq(_pool.previousRate(), 0.05 * 1e18);

        // should silently not update when actual utilization is 0
        _pool.updateInterestRate();
        assertEq(_pool.previousRate(),       0.05 * 1e18);
        assertEq(_pool.previousRateUpdate(), updateTime);

        // raise pool utilization
        // lender deposits 10_000 DAI in 3 buckets each
        _lender.addQuoteToken(_pool, address(_lender), 10_000 * 1e18, priceHigh);
        _lender.addQuoteToken(_pool, address(_lender), 10_000 * 1e18, priceMed);
        _lender.addQuoteToken(_pool, address(_lender), 10_000 * 1e18, priceLow);

        // borrower deposits 100 MKR collateral and draws debt
        _borrower.addCollateral(_pool, 100 * 1e18);
        _borrower.borrow(_pool, 25_000 * 1e18, 2500 * 1e18);

        skip(8200);

        assertEq(_pool.getPoolActualUtilization(), 0.833333333333333333 * 1e18);
        assertEq(_pool.getPoolTargetUtilization(), 0.099859436886217129 * 1e18);

        vm.expectEmit(true, true, false, true);
        emit UpdateInterestRate(0.05 * 1e18, 0.086673629908233477 * 1e18);
        _lender.updateInterestRate(_pool);

        assertEq(_pool.previousRate(),               0.086673629908233477 * 1e18);
        assertEq(_pool.previousRateUpdate(),         8200);
        assertEq(_pool.lastInflatorSnapshotUpdate(), 8200);
    }

    /**
     *  @notice With 1 lender and 1 borrower quote token is deposited then borrower adds collateral and borrows interest.
     *          Rate is checked for correctness, pool is underutilized.
     */
    function testUpdateInterestRateUnderutilized() external {
        uint256 priceHigh = _p4000;

        assertEq(_pool.previousRate(), 0.05 * 1e18);
        _lender.addQuoteToken(_pool, address(_lender), 1_000 * 1e18, priceHigh);
        skip(14);

        // borrower draws debt with a low collateralization ratio
        _borrower.addCollateral(_pool, 0.049988406706455432 * 1e18);
        _borrower.borrow(_pool, 200 * 1e18, 0);
        skip(14);

        assertLt(_pool.getPoolActualUtilization(), _pool.getPoolTargetUtilization());

        vm.expectEmit(true, true, false, true);
        emit UpdateInterestRate(0.05 * 1e18, 0.009999998890157270 * 1e18);
        _lender.updateInterestRate(_pool);
        assertEq(_pool.previousRate(), 0.009999998890157270 * 1e18);
    }

    /**
     *  @notice Ensure an underutilized and undercollateralized pool does not produce an underflow.
     */
    function testUndercollateralized() external {
        uint256 price = _p3514;

        _lender.addQuoteToken(_pool, address(_lender), 10_000 * 1e18, price);
        skip(14);

        // borrower utilizes the entire pool
        _borrower.addCollateral(_pool, 0.000284548895761533 * 1e18);
        _borrower.borrow(_pool, 1 * 1e18, 0);
        uint256 lastRate = _pool.previousRate();
        skip(3600 * 24);

        // debt accumulates, and the borrower becomes undercollateralized
        _borrower.repay(_pool, 1); // repay 1 WAD to trigger accumulation
        (, , , , uint256 collateralization, , ) = _pool.getBorrowerInfo(address(_borrower));
        assertLt(collateralization, 1 * 1e18);

        // rate should not change while pool is undercollateralized
        _lender.updateInterestRate(_pool);
        assertEq(_pool.previousRate(), lastRate);
    }

}
