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
    UserWithCollateral internal borrower2;
    UserWithQuoteToken internal lender;

    function setUp() public {
        collateral = new CollateralToken();
        quote = new QuoteToken();

        ERC20PoolFactory factory = new ERC20PoolFactory();
        pool = factory.deployPool(collateral, quote);

        borrower = new UserWithCollateral();
        collateral.mint(address(borrower), 100 * 1e18);
        borrower.approveToken(collateral, address(pool), 100 * 1e18);

        borrower2 = new UserWithCollateral();
        collateral.mint(address(borrower2), 100 * 1e18);
        borrower2.approveToken(collateral, address(pool), 100 * 1e18);

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

        // borrower2 starts with 10_000 DAI and deposit 100 collateral
        quote.mint(address(borrower2), 10_000 * 1e18);
        borrower2.approveToken(quote, address(pool), 100_000 * 1e18);
        borrower2.addCollateral(pool, 100 * 1e18);

        // check balances
        assertEq(collateral.balanceOf(address(borrower)), 0);
        assertEq(collateral.balanceOf(address(borrower2)), 0);
        assertEq(collateral.balanceOf(address(pool)), 200 * 1e18);
        assertEq(pool.totalCollateral(), 200 * 1e18);

        // repay should revert if no debt
        vm.expectRevert("ajna/no-debt-to-repay");
        borrower.repay(pool, 10_000 * 1e18);

        // borrower takes loan of 25_000 DAI from 3 buckets
        borrower.borrow(pool, 25_000 * 1e18, 2_500 * 1e18);
        // borrower2 takes loan of 2_000 DAI from 3 buckets
        borrower2.borrow(pool, 2_000 * 1e18, 1 * 1e18);

        // check balances
        assertEq(pool.totalQuoteToken(), 3_000 * 1e18);
        assertEq(pool.totalDebt(), 27_000 * 1e18);
        assertEq(pool.lup(), 3_000 * 1e18);
        assertEq(pool.getEncumberedCollateral(), 9 * 1e18);
        assertEq(quote.balanceOf(address(borrower)), 35_000 * 1e18);
        assertEq(quote.balanceOf(address(borrower2)), 12_000 * 1e18);
        assertEq(quote.balanceOf(address(pool)), 3_000 * 1e18);

        // check borrower
        (uint256 borrowerDebt, uint256 depositedCollateral, ) = pool.borrowers(
            address(borrower)
        );
        assertEq(borrowerDebt, 25_000 * 1e18);
        assertEq(depositedCollateral, 100 * 1e18);

        // check borrower2
        (borrowerDebt, depositedCollateral, ) = pool.borrowers(
            address(borrower2)
        );
        assertEq(borrowerDebt, 2_000 * 1e18);
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
        assertEq(pool.totalQuoteToken(), 13_000 * 1e18);
        assertEq(pool.totalDebt(), 17_000.351029676804435000 * 1e18);
        assertEq(pool.lup(), 4_000 * 1e18);
        assertEq(pool.getEncumberedCollateral(), 4.250087757419201109 * 1e18);
        assertEq(quote.balanceOf(address(borrower)), 25_000 * 1e18);
        assertEq(quote.balanceOf(address(pool)), 13_000 * 1e18);

        // check borrower debt
        (borrowerDebt, depositedCollateral, ) = pool.borrowers(
            address(borrower)
        );
        assertEq(borrowerDebt, 15_000.325027478522625000 * 1e18);
        assertEq(depositedCollateral, 100 * 1e18);

        // borrower attempts to overpay to cover 15_000 DAI plus accumulated debt
        vm.expectEmit(true, false, false, true);
        emit Transfer(
            address(borrower),
            address(pool),
            15_000.325027478522625000 * 1e18
        );
        emit Repay(
            address(borrower),
            5_000 * 1e18,
            17_000.325027478522625000 * 1e18
        );
        borrower.repay(pool, 15_000.325027478522625000 * 1e18);

        (borrowerDebt, depositedCollateral, ) = pool.borrowers(
            address(borrower)
        );

        assertEq(pool.totalQuoteToken(), 28_000.325027478522625000 * 1e18);
        assertEq(pool.totalDebt(), 2_000.026002198281810000 * 1e18);
        assertEq(pool.lup(), 5_000 * 1e18);
        assertEq(pool.getEncumberedCollateral(), 400005200439656362);
        assertEq(
            quote.balanceOf(address(borrower)),
            9_999.674972521477375000 * 1e18
        );
        assertEq(
            quote.balanceOf(address(pool)),
            28_000.325027478522625000 * 1e18
        );

        // borrower2 attempts to repay 2_000 DAI plus accumulated debt
        (borrowerDebt, depositedCollateral, ) = pool.borrowers(
            address(borrower2)
        );

        vm.expectEmit(true, false, false, true);
        emit Transfer(
            address(borrower2),
            address(pool),
            2_000.026002198281810000 * 1e18
        );
        emit Repay(
            address(borrower2),
            5_000 * 1e18,
            2_000.026002198281810000 * 1e18
        );
        borrower2.repay(pool, 2_000.026002198281810000 * 1e18);

        (borrowerDebt, depositedCollateral, ) = pool.borrowers(
            address(borrower2)
        );
        assertEq(borrowerDebt, 0);
        assertEq(pool.totalQuoteToken(), 30_000.351029676804435000 * 1e18);
        assertEq(pool.totalDebt(), 0);
        assertEq(pool.lup(), 5_000 * 1e18);
        assertEq(pool.getEncumberedCollateral(), 0);
        assertEq(
            quote.balanceOf(address(borrower2)),
            9_999.973997801718190000 * 1e18
        );
        assertEq(
            quote.balanceOf(address(pool)),
            30_000.351029676804435000 * 1e18
        );

        // remove deposited collateral
        borrower.removeCollateral(pool, 100 * 1e18);
        assertEq(collateral.balanceOf(address(borrower)), 100 * 1e18);

        borrower2.removeCollateral(pool, 100 * 1e18);
        assertEq(collateral.balanceOf(address(borrower2)), 100 * 1e18);
    }
}
