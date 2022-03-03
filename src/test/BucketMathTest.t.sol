// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.11;

import {DSTestPlus} from "./utils/DSTestPlus.sol";

import "../libraries/BucketMath.sol";

contract BucketMathTest is DSTestPlus {

    function testPriceToIndex () public {
        int256 priceToTest = 5 * 10 ** 18;

        int256 index = BucketMath.priceToIndex(priceToTest);

        assertEq(index, 322);
    }

}
