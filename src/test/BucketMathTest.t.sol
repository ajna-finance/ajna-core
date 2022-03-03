// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.11;

import {DSTestPlus} from "./utils/DSTestPlus.sol";

import "../libraries/BucketMath.sol";

contract BucketMathTest is DSTestPlus {
    function testPriceToIndex() public {
        int256 priceToTest = 5 * 10**18;

        int256 index = BucketMath.priceToIndex(priceToTest);

        assertEq(index, 322);
    }

    function testPriceToIndexFuzzy(int256 priceToIndex) public {
        if (
            priceToIndex < BucketMath.MIN_PRICE ||
            priceToIndex >= BucketMath.MAX_PRICE
        ) {
            return;
        }

        int256 index = BucketMath.priceToIndex(priceToIndex);
        int256 price = BucketMath.indexToPrice(index);

        assertEq(price, priceToIndex);
    }
}
