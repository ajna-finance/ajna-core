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

    uint8 internal constant MAX_USERS = type(uint8).max;

    function setUp() public {
        collateral = new CollateralToken();
        quote = new QuoteToken();

        pool = new ERC20PerpPool(collateral, quote);

        for (uint256 i; i < MAX_USERS; ++i) {
            UserWithCollateral user = new UserWithCollateral();
            collateral.mint(address(user), 1_000_000 * 1e18);
            user.approveToken(collateral, address(pool), type(uint256).max);

            borrowers.push(user);
        }

        for (uint256 i; i < MAX_USERS; ++i) {
            UserWithQuoteToken user = new UserWithQuoteToken();
            quote.mint(address(user), 1_000_000 * 1e18);
            user.approveToken(quote, address(pool), type(uint256).max);

            lenders.push(user);
        }
    }

    function skip_test_x_borrowers(
        uint8 numberOfLenders,
        uint8 numberOfBorrowers
    ) public {
        if (numberOfLenders == 0 || numberOfBorrowers == 0) {
            return;
        }
        if (numberOfLenders > 100 || numberOfBorrowers > 100) {
            return;
        }

        uint256 bucketPrice = pool.indexToPrice(7);

        for (uint8 i = 0; i < numberOfLenders; i++) {
            _depositQuoteToken(lenders[i], 1_000 * 1e18, bucketPrice);
        }

        for (uint8 i = 0; i < numberOfBorrowers; i++) {
            _depositCollateral(borrowers[i], 1e18);
        }

        for (uint8 i = 0; i < numberOfBorrowers; i++) {
            _borrow(borrowers[i], 1e18);
        }

        for (uint8 i = 0; i < numberOfBorrowers; i++) {
            _checkBorrowerDebt(borrowers[i], 7, 1e18);
        }
    }

    function test_5_borrowers_move_from_bucket_1_to_7() public {
        scenario_with_5_borrowers(1, 7);
    }

    function test_5_borrowers_move_from_bucket_1_to_100() public {
        scenario_with_5_borrowers(1, 100);
    }

    function test_5_borrowers_move_from_bucket_1_to_1000() public {
        scenario_with_5_borrowers(1, 1000);
    }

    function test_5_borrowers_move_from_bucket_1_to_3000() public {
        scenario_with_5_borrowers(1, 3000);
    }

    function test_5_borrowers_and_2_buckets() public {
        uint256 onDepositBorrower;
        uint256 totalDebitors;
        uint256 debtAccumulator;

        uint256 firstBucketId = 1;
        uint256 secondBucketId = 2;
        uint256 firstBucketPrice = pool.indexToPrice(firstBucketId);
        uint256 secondBucketPrice = pool.indexToPrice(secondBucketId);

        _depositQuoteToken(lenders[0], 10_000 * 1e18, firstBucketPrice);
        _depositQuoteToken(lenders[0], 5_000 * 1e18, secondBucketPrice);

        _depositQuoteToken(lenders[1], 5_000 * 1e18, firstBucketPrice);
        _depositQuoteToken(lenders[1], 3_000 * 1e18, secondBucketPrice);

        _depositQuoteToken(lenders[2], 7_000 * 1e18, firstBucketPrice);
        _depositQuoteToken(lenders[2], 2_000 * 1e18, secondBucketPrice);

        _depositQuoteToken(lenders[3], 4_000 * 1e18, firstBucketPrice);
        _depositQuoteToken(lenders[3], 5_000 * 1e18, secondBucketPrice);

        (onDepositBorrower, , , ) = pool.bucketInfo(firstBucketId);
        assertEq(onDepositBorrower, 26_000 * 1e18);

        (onDepositBorrower, , , ) = pool.bucketInfo(secondBucketId);
        assertEq(onDepositBorrower, 15_000 * 1e18);

        for (uint256 i = 0; i < 5; i++) {
            _depositCollateral(borrowers[i], 50 * 1e18);
        }

        for (uint256 i = 0; i < 5; i++) {
            _borrow(borrowers[i], 8_000 * 1e18);
        }

        (
            onDepositBorrower,
            totalDebitors,
            debtAccumulator,
            firstBucketPrice
        ) = pool.bucketInfo(firstBucketId);

        assertEq(onDepositBorrower, 1_000 * 1e18);
        assertEq(totalDebitors, 4);
        assertEq(debtAccumulator, 25_000 * 1e18);

        (
            onDepositBorrower,
            totalDebitors,
            debtAccumulator,
            secondBucketPrice
        ) = pool.bucketInfo(secondBucketId);

        assertEq(onDepositBorrower, 0);
        assertEq(totalDebitors, 2);
        assertEq(debtAccumulator, 15_000 * 1e18);

        _checkBorrowerDebt(borrowers[0], secondBucketId, 8_000 * 1e18);
        _checkBorrowerDebt(borrowers[1], secondBucketId, 7_000 * 1e18);

        _checkBorrowerDebt(borrowers[1], firstBucketId, 1_000 * 1e18);
        _checkBorrowerDebt(borrowers[2], firstBucketId, 8_000 * 1e18);
        _checkBorrowerDebt(borrowers[3], firstBucketId, 8_000 * 1e18);
        _checkBorrowerDebt(borrowers[4], firstBucketId, 8_000 * 1e18);

        uint256 thirdBucketId = 3;
        uint256 thirdBucketPrice = pool.indexToPrice(thirdBucketId);

        _depositQuoteToken(lenders[4], 50_000 * 1e18, thirdBucketPrice);

        (
            onDepositBorrower,
            totalDebitors,
            debtAccumulator,
            firstBucketPrice
        ) = pool.bucketInfo(firstBucketId);

        assertEq(onDepositBorrower, 26_000 * 1e18);
        assertEq(totalDebitors, 0);
        assertEq(debtAccumulator, 0);

        (
            onDepositBorrower,
            totalDebitors,
            debtAccumulator,
            secondBucketPrice
        ) = pool.bucketInfo(secondBucketId);

        assertEq(onDepositBorrower, 15_000 * 1e18);
        assertEq(totalDebitors, 0);
        assertEq(debtAccumulator, 0);

        (
            onDepositBorrower,
            totalDebitors,
            debtAccumulator,
            thirdBucketPrice
        ) = pool.bucketInfo(thirdBucketId);

        assertEq(onDepositBorrower, 10_000 * 1e18);
        assertEq(totalDebitors, 5);
        assertEq(debtAccumulator, 40_000 * 1e18);

        for (uint256 i = 0; i < 5; i++) {
            _checkBorrowerDebt(borrowers[i], thirdBucketId, 8_000 * 1e18);
        }
    }

    function test_5_borrowers_and_10_buckets() public {
        uint256 onDepositBorrower;
        uint256 totalDebitors;
        uint256 debtAccumulator;

        for (uint256 i = 1; i <= 10; i++) {
            uint256 bucketPrice = pool.indexToPrice(i);
            _depositQuoteToken(lenders[0], 5_000 * 1e18, bucketPrice);
            _depositQuoteToken(lenders[1], 3_000 * 1e18, bucketPrice);
            _depositQuoteToken(lenders[2], 4_000 * 1e18, bucketPrice);
            _depositQuoteToken(lenders[3], 7_000 * 1e18, bucketPrice);
        }

        assertEq(quote.balanceOf(address(pool)), 190_000 * 1e18);

        for (uint256 i = 1; i <= 10; i++) {
            (uint256 onDepositBorrower, , , ) = pool.bucketInfo(i);
            assertEq(onDepositBorrower, 19_000 * 1e18);
        }

        for (uint256 i = 0; i < 5; i++) {
            _depositCollateral(borrowers[i], 50 * 1e18);
        }

        for (uint256 i = 0; i < 5; i++) {
            _borrow(borrowers[i], 38_000 * 1e18);
        }

        for (uint256 i = 1; i <= 10; i++) {
            (onDepositBorrower, totalDebitors, debtAccumulator, ) = pool
                .bucketInfo(i);
            assertEq(onDepositBorrower, 0);
            assertEq(totalDebitors, 1);
            assertEq(debtAccumulator, 19_000 * 1e18);
        }

        _checkBorrowerDebt(borrowers[0], 10, 19_000 * 1e18);
        _checkBorrowerDebt(borrowers[0], 9, 19_000 * 1e18);
        _checkBorrowerDebt(borrowers[4], 2, 19_000 * 1e18);
        _checkBorrowerDebt(borrowers[4], 1, 19_000 * 1e18);

        uint256 bucket11_price = pool.indexToPrice(11);
        _depositQuoteToken(lenders[4], 200_000 * 1e18, bucket11_price);

        for (uint256 i = 1; i <= 10; i++) {
            (onDepositBorrower, totalDebitors, debtAccumulator, ) = pool
                .bucketInfo(i);
            assertEq(onDepositBorrower, 19_000 * 1e18);
            assertEq(totalDebitors, 0);
            assertEq(debtAccumulator, 0);
        }

        (onDepositBorrower, totalDebitors, debtAccumulator, ) = pool.bucketInfo(
            11
        );
        assertEq(onDepositBorrower, 10_000 * 1e18);
        assertEq(totalDebitors, 5);
        assertEq(debtAccumulator, 190_000 * 1e18);

        for (uint256 i = 0; i < 5; i++) {
            _checkBorrowerDebt(borrowers[i], 11, 38_000 * 1e18);
        }
    }

    function scenario_with_5_borrowers(
        uint256 initialBucket,
        uint256 laterBucket
    ) public {
        uint256 bucketPrice = pool.indexToPrice(initialBucket);

        _depositQuoteToken(lenders[0], 10_000 * 1e18, bucketPrice);
        _depositQuoteToken(lenders[1], 5_000 * 1e18, bucketPrice);
        _depositQuoteToken(lenders[2], 7_000 * 1e18, bucketPrice);
        _depositQuoteToken(lenders[3], 4_000 * 1e18, bucketPrice);

        (uint256 onDepositLender, , , ) = pool.bucketInfo(initialBucket);

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
            uint256 debtAccumulator,
            uint256 price
        ) = pool.bucketInfo(initialBucket);

        assertEq(onDepositBorrower, 5_000 * 1e18);
        assertEq(totalDebitors, 5);
        assertEq(debtAccumulator, 21_000 * 1e18);

        _checkBorrowerDebt(borrowers[0], initialBucket, 10_000 * 1e18);
        _checkBorrowerDebt(borrowers[1], initialBucket, 1_000 * 1e18);
        _checkBorrowerDebt(borrowers[2], initialBucket, 2_000 * 1e18);
        _checkBorrowerDebt(borrowers[3], initialBucket, 1_000 * 1e18);
        _checkBorrowerDebt(borrowers[4], initialBucket, 7_000 * 1e18);

        bucketPrice = pool.indexToPrice(laterBucket);

        assertGt(quote.balanceOf(address(lenders[1])), 26_000 * 1e18);
        lenders[1].depositQuoteToken(pool, 26_000 * 1e18, bucketPrice);

        uint256 initialBucketOnDeposit;
        uint256 laterBucketOnDeposit;

        (initialBucketOnDeposit, totalDebitors, debtAccumulator, price) = pool
            .bucketInfo(initialBucket);

        assertEq(initialBucketOnDeposit, (21_000 + 5_000) * 1e18);
        assertEq(totalDebitors, 0);
        assertEq(debtAccumulator, 0);
        _checkBorrowerDebt(borrowers[0], initialBucket, 0);

        (laterBucketOnDeposit, totalDebitors, debtAccumulator, price) = pool
            .bucketInfo(laterBucket);

        assertEq(laterBucketOnDeposit, (26_000 - 21_000) * 1e18);
        assertEq(totalDebitors, 5);
        assertEq(debtAccumulator, 21_000 * 1e18);

        _checkBorrowerDebt(borrowers[0], initialBucket, 0);
        _checkBorrowerDebt(borrowers[0], laterBucket, 10_000 * 1e18);

        _checkBorrowerDebt(borrowers[1], initialBucket, 0);
        _checkBorrowerDebt(borrowers[1], laterBucket, 1_000 * 1e18);

        _checkBorrowerDebt(borrowers[2], initialBucket, 0);
        _checkBorrowerDebt(borrowers[2], laterBucket, 2_000 * 1e18);

        _checkBorrowerDebt(borrowers[3], initialBucket, 0);
        _checkBorrowerDebt(borrowers[3], laterBucket, 1_000 * 1e18);

        _checkBorrowerDebt(borrowers[4], initialBucket, 0);
        _checkBorrowerDebt(borrowers[4], laterBucket, 7_000 * 1e18);

        assertEq(
            quote.balanceOf(address(pool)),
            initialBucketOnDeposit + laterBucketOnDeposit
        );
    }

    function _depositQuoteToken(
        UserWithQuoteToken lender,
        uint256 amount,
        uint256 price
    ) internal {
        uint256 balance = quote.balanceOf(address(lender));
        uint256 poolBalance = pool.quoteBalances(address(lender));

        assertGt(balance, amount);

        lender.depositQuoteToken(pool, amount, price);

        assertEq(balance - quote.balanceOf(address(lender)), amount);
        assertEq(pool.quoteBalances(address(lender)), poolBalance + amount);
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
        uint256 borrowerDebt = pool.userDebt(address(borrower), bucket);

        assertEq(expectedDebt, borrowerDebt);
    }
}
