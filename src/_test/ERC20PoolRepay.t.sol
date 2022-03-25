// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.11;

import {DSTestPlus} from "./utils/DSTestPlus.sol";
import {UserWithCollateral, UserWithQuoteToken} from "./utils/Users.sol";
import {CollateralToken, QuoteToken} from "./utils/Tokens.sol";

import {ERC20Pool} from "../ERC20Pool.sol";
import {ERC20PoolFactory} from "../ERC20PoolFactory.sol";

contract ERC20PoolRepayTest is DSTestPlus {
    ERC20Pool internal pool;
    CollateralToken internal collateral;
    QuoteToken internal quote;

    UserWithCollateral internal borrower;
    UserWithQuoteToken internal lender;

    function setUp() public {
        collateral = new CollateralToken();
        quote = new QuoteToken();

        ERC20PoolFactory factory = new ERC20PoolFactory();
        pool = factory.deployPool(collateral, quote);

        borrower = new UserWithCollateral();
        collateral.mint(address(borrower), 100 * 1e18);
        borrower.approveToken(collateral, address(pool), 100 * 1e18);

        lender = new UserWithQuoteToken();
        quote.mint(address(lender), 200_000 * 1e18);
        lender.approveToken(quote, address(pool), 200_000 * 1e18);
    }

    function testRepay() public {
        // lender deposits 10000 DAI in 3 buckets each
        lender.addQuoteToken(pool, 10_000 * 1e18, 5_000 * 1e18);
        lender.addQuoteToken(pool, 10_000 * 1e18, 4_000 * 1e18);
        lender.addQuoteToken(pool, 10_000 * 1e18, 3_000 * 1e18);

        // borrower starts with 10_000 DAI and deposit 100 collateral
        quote.mint(address(borrower), 10_000 * 1e18);
        borrower.approveToken(quote, address(pool), 100_000 * 1e18);
        borrower.addCollateral(pool, 100 * 1e18);

        // check balances
        assertEq(collateral.balanceOf(address(borrower)), 0);
        assertEq(collateral.balanceOf(address(pool)), 100 * 1e18);
        assertEq(pool.totalCollateral(), 100 * 1e18);

        // repay should revert if no debt
        vm.expectRevert("ajna/no-debt-to-repay");
        borrower.repay(pool, 10_000 * 1e18);

        // take loan of 25_000 DAI from 3 buckets
        borrower.borrow(pool, 25_000 * 1e18, 2_500 * 1e18);

        // check balances
        assertEq(pool.totalQuoteToken(), 30_000 * 1e18);
        assertEq(pool.totalDebt(), 25_000 * 1e18);
        assertEq(pool.lup(), 3_000 * 1e18);
        assertEq(pool.getEncumberedCollateral(), 8.333333333333333333 * 1e18);
        assertEq(quote.balanceOf(address(borrower)), 35_000 * 1e18);
        assertEq(quote.balanceOf(address(pool)), 5_000 * 1e18);

        // check borrower
        (uint256 borrowerDebt, uint256 depositedCollateral, ) = pool.borrowers(
            address(borrower)
        );
        assertEq(borrowerDebt, 25_000 * 1e18);
        assertEq(depositedCollateral, 100 * 1e18);

        // repay should revert if amount not available
        vm.expectRevert("ajna/no-funds-to-repay");
        borrower.repay(pool, 50_000 * 1e18);

        // repay debt partially 10_000 DAI
        skip(8200);
        vm.expectEmit(true, false, false, true);
        emit Transfer(address(borrower), address(pool), 10_000 * 1e18);
        emit Repay(address(borrower), 4_000 * 1e18, 10_000 * 1e18);
        borrower.repay(pool, 10_000 * 1e18);

        // check balances
        assertEq(pool.totalQuoteToken(), 30_000 * 1e18);
        assertEq(pool.totalDebt(), 15_000.325027478522625000 * 1e18);
        assertEq(pool.lup(), 4_000 * 1e18);
        assertEq(pool.getEncumberedCollateral(), 3.750081256869630656 * 1e18);
        assertEq(quote.balanceOf(address(borrower)), 25_000 * 1e18);
        assertEq(quote.balanceOf(address(pool)), 15_000 * 1e18);

        // check borrower debt
        (borrowerDebt, depositedCollateral, ) = pool.borrowers(
            address(borrower)
        );
        assertEq(borrowerDebt, 15_000.325027478522625000 * 1e18);
        assertEq(depositedCollateral, 100 * 1e18);

        // repay remaining 15_000 DAI plus accumulated debt
        vm.expectEmit(true, false, false, true);
        emit Transfer(
            address(borrower),
            address(pool),
            15_000.325027478522625000 * 1e18
        );
        emit Repay(
            address(borrower),
            5_000 * 1e18,
            15_000.325027478522625000 * 1e18
        );
        borrower.repay(pool, 16_000 * 1e18);

        // check balances
        assertEq(pool.totalQuoteToken(), 30_000 * 1e18);
        assertEq(pool.totalDebt(), 0);
        assertEq(pool.lup(), 5_000 * 1e18);
        assertEq(pool.getEncumberedCollateral(), 0);
        assertEq(
            quote.balanceOf(address(borrower)),
            9_999.674972521477375000 * 1e18
        );
        assertEq(
            quote.balanceOf(address(pool)),
            30_000.325027478522625000 * 1e18
        );

        // remove deposited collateral
        borrower.removeCollateral(pool, 100 * 1e18);
        assertEq(collateral.balanceOf(address(borrower)), 100 * 1e18);
    }
}
