// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.11;

import {DSTestPlus} from "./utils/DSTestPlus.sol";

import "../libraries/BucketMath.sol";

contract BucketMathTest is DSTestPlus {
    function testPriceToIndex() public {
        uint256 priceToTest = 5 * 10**18;

        int256 index = BucketMath.priceToIndex(priceToTest);

        assertEq(index, 323);
    }

    function testIsValidPrice() public {
        assertTrue(BucketMath.isValidPrice(BucketMath.MAX_PRICE));
        assertTrue(BucketMath.isValidPrice(BucketMath.MIN_PRICE));
        assertTrue(BucketMath.isValidPrice(49_910.043670274810022205 * 10**18));
        assertTrue(!BucketMath.isValidPrice(2_000 * 10**18));
    }

    function testPriceIndexConversion() public {
        uint256 priceToTest = BucketMath.MAX_PRICE;
        assertEq(BucketMath.indexToPrice(4156), priceToTest);
        assertEq(BucketMath.priceToIndex(priceToTest), 4156);

        priceToTest = 49_910.043670274810022205 * 10**18;
        assertEq(BucketMath.indexToPrice(2169), priceToTest);
        assertEq(BucketMath.priceToIndex(priceToTest), 2169);

        priceToTest = 2_000.221618840727700609 * 10**18;
        assertEq(BucketMath.indexToPrice(1524), priceToTest);
        assertEq(BucketMath.priceToIndex(priceToTest), 1524);

        priceToTest = 146.575625611106531706 * 10**18;
        assertEq(BucketMath.indexToPrice(1000), priceToTest);
        assertEq(BucketMath.priceToIndex(priceToTest), 1000);

        priceToTest = 145.846393642892072537 * 10**18;
        assertEq(BucketMath.indexToPrice(999), priceToTest);
        assertEq(BucketMath.priceToIndex(priceToTest), 999);

        priceToTest = 5.263790124045347667 * 10**18;
        assertEq(BucketMath.indexToPrice(333), priceToTest);
        assertEq(BucketMath.priceToIndex(priceToTest), 333);

        priceToTest = 1.646668492116543299 * 10**18;
        assertEq(BucketMath.indexToPrice(100), priceToTest);
        assertEq(BucketMath.priceToIndex(priceToTest), 100);

        priceToTest = 1.315628874808846999 * 10**18;
        assertEq(BucketMath.indexToPrice(55), priceToTest);
        assertEq(BucketMath.priceToIndex(priceToTest), 55);

        priceToTest = 1.051140132040790557 * 10**18;
        assertEq(BucketMath.indexToPrice(10), priceToTest);
        assertEq(BucketMath.priceToIndex(priceToTest), 10);

        priceToTest = 0.000046545370002462 * 10**18;
        assertEq(BucketMath.indexToPrice(-2000), priceToTest);
        assertEq(BucketMath.priceToIndex(priceToTest), -2000);

        priceToTest = 0.006822416727411372 * 10**18;
        assertEq(BucketMath.indexToPrice(-1000), priceToTest);
        assertEq(BucketMath.priceToIndex(priceToTest), -1000);

        priceToTest = 0.006856528811048429 * 10**18;
        assertEq(BucketMath.indexToPrice(-999), priceToTest);
        assertEq(BucketMath.priceToIndex(priceToTest), -999);

        priceToTest = 0.189977179263271283 * 10**18;
        assertEq(BucketMath.indexToPrice(-333), priceToTest);
        assertEq(BucketMath.priceToIndex(priceToTest), -333);

        priceToTest = 0.607286776171110946 * 10**18;
        assertEq(BucketMath.indexToPrice(-100), priceToTest);
        assertEq(BucketMath.priceToIndex(priceToTest), -100);

        priceToTest = 0.951347940696068854 * 10**18;
        assertEq(BucketMath.indexToPrice(-10), priceToTest);
        assertEq(BucketMath.priceToIndex(priceToTest), -10);

        priceToTest = BucketMath.MIN_PRICE;
        assertEq(BucketMath.indexToPrice(-3232), priceToTest);
        assertEq(BucketMath.priceToIndex(priceToTest), -3232);
    }

    function testPriceBucketCorrectness() public {
        for (
            int256 i = BucketMath.MIN_PRICE_INDEX;
            i < BucketMath.MAX_PRICE_INDEX;
            i++
        ) {
            uint256 priceToTest = BucketMath.indexToPrice(i);
            assertEq(BucketMath.priceToIndex(priceToTest), i);
            assertEq(priceToTest, BucketMath.indexToPrice(i));
        }
    }

    function testClosestPriceBucket() public {
        uint256 priceToTest = 2_000 * 10**18;

        (int256 index, uint256 price) = BucketMath.getClosestBucket(
            priceToTest
        );

        assertEq(index, 1524);
        assertEq(price, 2000.221618840727700609 * 1e18);
    }

    function testPriceToIndexFuzzy(uint256 priceToIndex) public {
        if (
            priceToIndex < BucketMath.MIN_PRICE ||
            priceToIndex >= BucketMath.MAX_PRICE
        ) {
            return;
        }

        (int256 index, uint256 price) = BucketMath.getClosestBucket(
            priceToIndex
        );

        assertEq(BucketMath.indexToPrice(index), price);
        assertEq(BucketMath.priceToIndex(price), index);
    }
}
