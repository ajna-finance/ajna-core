// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.10;

import {DSTestPlus} from "./utils/DSTestPlus.sol";
import {UserWithCollateral, UserWithQuoteToken} from "./utils/Users.sol";
import {CollateralToken, QuoteToken} from "./utils/Tokens.sol";

import {ERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20PerpPool} from "../ERC20PerpPool.sol";

contract ERC20PerpPoolPerformanceTest is DSTestPlus {
    ERC20PerpPool internal pool;
    CollateralToken internal collateral;
    QuoteToken internal quote;

    UserWithCollateral[] internal borrowers;
    UserWithQuoteToken[] internal lenders;

    uint256 internal constant MAX_USERS = 100;

    function setUp() public {
        collateral = new CollateralToken();
        quote = new QuoteToken();

        pool = new ERC20PerpPool(collateral, quote);

        for (uint256 i; i < MAX_USERS; ++i) {
            UserWithCollateral user = new UserWithCollateral();
            collateral.mint(address(user), 100_000 * 1e18);
            user.approveToken(collateral, address(pool), type(uint256).max);

            borrowers.push(user);
        }

        for (uint256 i; i < MAX_USERS; ++i) {
            UserWithQuoteToken user = new UserWithQuoteToken();
            quote.mint(address(user), 100_000 * 1e18);
            user.approveToken(quote, address(pool), type(uint256).max);

            lenders.push(user);
        }
    }

    function test_5_borrowers() public {
        uint256 bucketPrice = pool.indexToPrice(7);

        _depositQuoteToken(lenders[0], 10_000 * 1e18, bucketPrice);
        _depositQuoteToken(lenders[1], 5_000 * 1e18, bucketPrice);
        _depositQuoteToken(lenders[2], 7_000 * 1e18, bucketPrice);
        _depositQuoteToken(lenders[3], 4_000 * 1e18, bucketPrice);

        (uint256 onDepositLender, , , , ) = pool.bucketInfoForAddress(
            7,
            address(lenders[0])
        );

        assertEq(onDepositLender, 26_000 * 1e18);

        _depositCollateral(borrowers[0], 10 * 1e18);
        _depositCollateral(borrowers[1], 3 * 1e18);
        _depositCollateral(borrowers[2], 5 * 1e18);
        _depositCollateral(borrowers[3], 2 * 1e18);
        _depositCollateral(borrowers[4], 4 * 1e18);

        _borrow(borrowers[0], 10_000 * 1e18);
        _borrow(borrowers[1], 1_000 * 1e18);
        _borrow(borrowers[2], 2_000 * 1e18);
        _borrow(borrowers[3], 1_000 * 1e18);
        _borrow(borrowers[4], 7_000 * 1e18);

        (
            uint256 onDepositBorrower,
            uint256 totalDebitors,
            uint256 borrowerDebt,
            uint256 debtAccumulator,
            uint256 price
        ) = pool.bucketInfoForAddress(7, address(borrowers[0]));

        assertEq(onDepositBorrower, 5_000 * 1e18);
        assertEq(totalDebitors, 5);
        assertEq(debtAccumulator, 21_000 * 1e18);

        assertEq(borrowerDebt, 10_000 * 1e18);

        _checkBorrowerDebt(borrowers[1], 7, 1_000 * 1e18);
        _checkBorrowerDebt(borrowers[2], 7, 2_000 * 1e18);
        _checkBorrowerDebt(borrowers[3], 7, 1_000 * 1e18);
        _checkBorrowerDebt(borrowers[4], 7, 7_000 * 1e18);

        bucketPrice = pool.indexToPrice(9);

        assertGt(quote.balanceOf(address(lenders[1])), 26_000 * 1e18);
        lenders[1].depositQuoteToken(pool, 26_000 * 1e18, bucketPrice);

        uint256 bucket7OnDepositBorrower;
        uint256 bucket9OnDepositBorrower;

        (
            bucket7OnDepositBorrower,
            totalDebitors,
            borrowerDebt,
            debtAccumulator,
            price
        ) = pool.bucketInfoForAddress(7, address(borrowers[0]));

        assertEq(bucket7OnDepositBorrower, (21_000 + 5_000) * 1e18);
        assertEq(totalDebitors, 0);
        assertEq(debtAccumulator, 0);
        _checkBorrowerDebt(borrowers[0], 7, 0);

        (
            bucket9OnDepositBorrower,
            totalDebitors,
            borrowerDebt,
            debtAccumulator,
            price
        ) = pool.bucketInfoForAddress(9, address(borrowers[0]));

        assertEq(bucket9OnDepositBorrower, (26_000 - 21_000) * 1e18);
        assertEq(totalDebitors, 5);
        assertEq(debtAccumulator, 21_000 * 1e18);
        assertEq(borrowerDebt, 10_000 * 1e18);

        _checkBorrowerDebt(borrowers[0], 7, 0);

        _checkBorrowerDebt(borrowers[1], 7, 0);
        _checkBorrowerDebt(borrowers[1], 9, 1_000 * 1e18);

        _checkBorrowerDebt(borrowers[2], 7, 0);
        _checkBorrowerDebt(borrowers[2], 9, 2_000 * 1e18);

        _checkBorrowerDebt(borrowers[3], 7, 0);
        _checkBorrowerDebt(borrowers[3], 9, 1_000 * 1e18);

        _checkBorrowerDebt(borrowers[4], 7, 0);
        _checkBorrowerDebt(borrowers[4], 9, 7_000 * 1e18);

        assertEq(
            quote.balanceOf(address(pool)),
            bucket7OnDepositBorrower + bucket9OnDepositBorrower
        );
    }

    function _depositQuoteToken(
        UserWithQuoteToken lender,
        uint256 amount,
        uint256 price
    ) internal {
        uint256 balance = quote.balanceOf(address(lender));
        assertGt(balance, amount);

        lender.depositQuoteToken(pool, amount, price);

        assertEq(balance - quote.balanceOf(address(lender)), amount);
        assertEq(pool.quoteBalances(address(lender)), amount);
    }

    function _depositCollateral(UserWithCollateral borrower, uint256 amount)
        internal
    {
        uint256 balance = collateral.balanceOf(address(borrower));
        assertGt(balance, amount);

        borrower.depositCollteral(pool, amount);

        assertEq(balance - collateral.balanceOf(address(borrower)), amount);
    }

    function _borrow(UserWithCollateral borrower, uint256 amount) internal {
        borrower.borrow(pool, amount);

        assertEq(quote.balanceOf(address(borrower)), amount);
    }

    function _checkBorrowerDebt(
        UserWithCollateral borrower,
        uint256 bucket,
        uint256 expectedDebt
    ) internal {
        (, , uint256 borrowerDebt, , ) = pool.bucketInfoForAddress(
            bucket,
            address(borrower)
        );

        assertEq(expectedDebt, borrowerDebt);
    }
}
