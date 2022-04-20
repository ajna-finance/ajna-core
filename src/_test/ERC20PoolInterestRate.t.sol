// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.11;

import {PRBMathUD60x18} from "@prb-math/contracts/PRBMathUD60x18.sol";

import {DSTestPlus} from "./utils/DSTestPlus.sol";
import {UserWithCollateral, UserWithQuoteToken} from "./utils/Users.sol";
import {CollateralToken, QuoteToken} from "./utils/Tokens.sol";

import {ERC20Pool} from "../ERC20Pool.sol";
import {ERC20PoolFactory} from "../ERC20PoolFactory.sol";

contract ERC20PoolInterestRateTest is DSTestPlus {
    ERC20Pool internal pool;
    CollateralToken internal collateral;
    QuoteToken internal quote;

    UserWithCollateral internal borrower;
    UserWithQuoteToken internal lender;

    function setUp() public {
        collateral = new CollateralToken();
        quote = new QuoteToken();

        ERC20PoolFactory factory = new ERC20PoolFactory();
        pool = factory.deployPool(address(collateral), address(quote));

        borrower = new UserWithCollateral();
        collateral.mint(address(borrower), 100 * 1e18);
        borrower.approveToken(collateral, address(pool), 100 * 1e18);

        lender = new UserWithQuoteToken();
        quote.mint(address(lender), 200_000 * 1e18);
        lender.approveToken(quote, address(pool), 200_000 * 1e18);
    }

    // @notice: with 1 lender and 1 borrower quote token is deposited
    // @notice: then borrower adds collateral and borrows interest
    // @notice: rate is checked for correctness
    function testUpdateInterestRate() public {
        uint256 priceHigh = 4_000.927678580567537368 * 1e18;
        uint256 priceMed = 3_514.334495390401848927 * 1e18;
        uint256 priceLow = 2_503.519024294695168295 * 1e18;

        assertEq(pool.previousRate(), 0.05 * 1e18);

        uint256 updateTime = pool.previousRateUpdate();

        // should silently not update when actual utilization is 0
        pool.updateInterestRate();
        assertEq(pool.previousRate(), 0.05 * 1e18);
        assertEq(pool.previousRateUpdate(), updateTime);

        // raise pool utilization
        // lender deposits 10_000 DAI in 3 buckets each
        lender.addQuoteToken(pool, address(lender), 10_000 * 1e18, priceHigh);
        lender.addQuoteToken(pool, address(lender), 10_000 * 1e18, priceMed);
        lender.addQuoteToken(pool, address(lender), 10_000 * 1e18, priceLow);

        // borrower deposits 100 MKR collateral and draws debt
        borrower.addCollateral(pool, 100 * 1e18);
        borrower.borrow(pool, 25_000 * 1e18, 2500 * 1e18);

        skip(8200);

        assertEq(pool.getPoolActualUtilization(), 0.833333333333333333333333333 * 1e27);
        assertEq(pool.getPoolTargetUtilization(), 0.099859436886217129237589653 * 1e27);

        vm.expectEmit(true, true, false, true);
        emit UpdateInterestRate(0.05 * 1e18, 0.086673629908233477 * 1e18);
        lender.updateInterestRate(pool);

        assertEq(pool.previousRate(), 0.086673629908233477 * 1e18);
        assertEq(pool.previousRateUpdate(), 8200);
        assertEq(pool.lastInflatorSnapshotUpdate(), 8200);
    }

    // @notice: with 1 lender and 1 borrower quote token is deposited
    // @notice: then borrower adds collateral and borrows interest
    // @notice: rate is checked for correctness, pool is underutilized

    function testUpdateInterestRateUnderutilized() public {
        uint256 priceHigh = 4_000.927678580567537368 * 1e18;

        assertEq(pool.previousRate(), 0.05 * 1e18);
        lender.addQuoteToken(pool, address(lender), 1_000 * 1e18, priceHigh);
        skip(14);

        // borrower draws debt with a low collateralization ratio
        borrower.addCollateral(pool, 0.049988406706455432 * 1e18);
        borrower.borrow(pool, 200 * 1e18, 0);
        skip(14);

        assertLt(pool.getPoolActualUtilization(), pool.getPoolTargetUtilization());

        vm.expectEmit(true, true, false, true);
        emit UpdateInterestRate(0.05 * 1e18, 0.009999996670471735 * 1e18);
        lender.updateInterestRate(pool);
        assertEq(pool.previousRate(), 0.009999996670471735 * 1e18);
    }
}
