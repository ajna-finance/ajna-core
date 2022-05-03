// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.11;

import { BucketMath } from "../libraries/BucketMath.sol";

import { DSTestPlus } from "./utils/DSTestPlus.sol";

contract BucketMathTest is DSTestPlus {

    // @notice: Tests price maps to index
    // @notice: BucketMath revert:
    // @notice:     attempt to get index of bad price
    function testPriceToIndex() public {
        uint256 badPrice = 5 * 10**10;

        vm.expectRevert(BucketMath.PriceOutsideBoundry.selector);
        BucketMath.priceToIndex(badPrice);

        uint256 priceToTest = 5 * 10**18;
        int256 index = BucketMath.priceToIndex(priceToTest);

        assertEq(index, 323);
    }

    // @notice: Tests validity of min and max prices
    function testIsValidPrice() public {
        assertTrue( BucketMath.isValidPrice(BucketMath.MAX_PRICE));
        assertTrue( BucketMath.isValidPrice(BucketMath.MIN_PRICE));
        assertTrue( BucketMath.isValidPrice(_p49910));
        assertTrue(!BucketMath.isValidPrice(2_000 * 10 ** 18));
    }

    // @notice: Tests verying prices map to indexes properly
    function testPriceIndexConversion() public {
        assertEq(BucketMath.indexToPrice(4156),                 BucketMath.MAX_PRICE);
        assertEq(BucketMath.priceToIndex(BucketMath.MAX_PRICE), 4156);
        assertEq(BucketMath.indexToPrice(-3232),                BucketMath.MIN_PRICE);
        assertEq(BucketMath.priceToIndex(BucketMath.MIN_PRICE), -3232);

        assertEq(BucketMath.indexToPrice(2169),    _p49910);
        assertEq(BucketMath.priceToIndex(_p49910), 2169);

        assertEq(BucketMath.indexToPrice(1524),   _p2000);
        assertEq(BucketMath.priceToIndex(_p2000), 1524);

        assertEq(BucketMath.indexToPrice(1000),  _p146);
        assertEq(BucketMath.priceToIndex(_p146), 1000);

        assertEq(BucketMath.indexToPrice(999),   _p145);
        assertEq(BucketMath.priceToIndex(_p145), 999);

        assertEq(BucketMath.indexToPrice(333),    _p5_26);
        assertEq(BucketMath.priceToIndex(_p5_26), 333);

        assertEq(BucketMath.indexToPrice(100),    _p1_64);
        assertEq(BucketMath.priceToIndex(_p1_64), 100);

        assertEq(BucketMath.indexToPrice(55),     _p1_31);
        assertEq(BucketMath.priceToIndex(_p1_31), 55);

        assertEq(BucketMath.indexToPrice(10),     _p1_05);
        assertEq(BucketMath.priceToIndex(_p1_05), 10);

        assertEq(BucketMath.indexToPrice(-2000),      _p0_000046);
        assertEq(BucketMath.priceToIndex(_p0_000046), -2000);

        assertEq(BucketMath.indexToPrice(-1000),      _p0_006822);
        assertEq(BucketMath.priceToIndex(_p0_006822), -1000);

        assertEq(BucketMath.indexToPrice(-999),       _p0_006856);
        assertEq(BucketMath.priceToIndex(_p0_006856), -999);

        assertEq(BucketMath.indexToPrice(-333),       _p0_189977);
        assertEq(BucketMath.priceToIndex(_p0_189977), -333);

        assertEq(BucketMath.indexToPrice(-100),       _p0_607286);
        assertEq(BucketMath.priceToIndex(_p0_607286), -100);

        assertEq(BucketMath.indexToPrice(-10),        _p0_951347);
        assertEq(BucketMath.priceToIndex(_p0_951347), -10);

    }

    // @notice: Tests that price to index and index to price
    // @notice: return properly
    function testPriceBucketCorrectness() public {
        for (int256 i = BucketMath.MIN_PRICE_INDEX; i < BucketMath.MAX_PRICE_INDEX; i++) {
            uint256 priceToTest = BucketMath.indexToPrice(i);

            assertEq(BucketMath.priceToIndex(priceToTest), i);
            assertEq(priceToTest,                          BucketMath.indexToPrice(i));
        }
    }

    // @notice: Tests retreival of closest bucket to price
    function testClosestPriceBucket() public {
        uint256 priceToTest = 2_000 * 10**18;

        (int256 index, uint256 price) = BucketMath.getClosestBucket(priceToTest);

        assertEq(index, 1524);
        assertEq(price, _p2000);
    }

    // @notice: Tests get closest bucket with fuzzing
    function testPriceToIndexFuzzy(uint256 priceToIndex_) public {
        if (priceToIndex_ < BucketMath.MIN_PRICE || priceToIndex_ >= BucketMath.MAX_PRICE) {
            return;
        }

        (int256 index, uint256 price) = BucketMath.getClosestBucket(priceToIndex_);

        assertEq(BucketMath.indexToPrice(index), price);
        assertEq(BucketMath.priceToIndex(price), index);
    }

}
