// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.14;

import './utils/DSTestPlus.sol';
import './utils/BucketMath.sol';

contract BucketMathTest is DSTestPlus {

    /**************/
    /*** Prices ***/
    /**************/

    uint256 internal _p50159    = 50_159.593888626183666006 * 1e18;
    uint256 internal _p49910    = 49_910.043670274810022205 * 1e18;
    uint256 internal _p15000    = 15_000.520048194378317056 * 1e18;
    uint256 internal _p10016    = 10_016.501589292607751220 * 1e18;
    uint256 internal _p9020     = 9_020.461710444470171420 * 1e18;
    uint256 internal _p8002     = 8_002.824356287850613262 * 1e18;
    uint256 internal _p5007     = 5_007.644384905151472283 * 1e18;
    uint256 internal _p4000     = 4_000.927678580567537368 * 1e18;
    uint256 internal _p3514     = 3_514.334495390401848927 * 1e18;
    uint256 internal _p3010     = 3_010.892022197881557845 * 1e18;
    uint256 internal _p3002     = 3_002.895231777120270013 * 1e18;
    uint256 internal _p2995     = 2_995.912459898389633881 * 1e18;
    uint256 internal _p2981     = 2_981.007422784467321543 * 1e18;
    uint256 internal _p2966     = 2_966.176540084047110076 * 1e18;
    uint256 internal _p2850     = 2_850.155149230026939621 * 1e18;
    uint256 internal _p2835     = 2_835.975272865698470386 * 1e18;
    uint256 internal _p2821     = 2_821.865943149948749647 * 1e18;
    uint256 internal _p2807     = 2_807.826809104426639178 * 1e18;
    uint256 internal _p2793     = 2_793.857521496941952028 * 1e18;
    uint256 internal _p2779     = 2_779.957732832778084277 * 1e18;
    uint256 internal _p2503     = 2_503.519024294695168295 * 1e18;
    uint256 internal _p2000     = 2_000.221618840727700609 * 1e18;
    uint256 internal _p1004     = 1_004.989662429170775094 * 1e18;
    uint256 internal _p1000     = 1_000.023113960510762449 * 1e18;
    uint256 internal _p502      = 502.433988063349232760 * 1e18;
    uint256 internal _p146      = 146.575625611106531706 * 1e18;
    uint256 internal _p145      = 145.846393642892072537 * 1e18;
    uint256 internal _p100      = 100.332368143282009890 * 1e18;
    uint256 internal _p14_63    = 14.633264579158672146 * 1e18;
    uint256 internal _p13_57    = 13.578453165083418466 * 1e18;
    uint256 internal _p13_31    = 13.310245063610237646 * 1e18;
    uint256 internal _p12_66    = 12.662674231425615571 * 1e18;
    uint256 internal _p5_26     = 5.263790124045347667 * 1e18;
    uint256 internal _p1_64     = 1.646668492116543299 * 1e18;
    uint256 internal _p1_31     = 1.315628874808846999 * 1e18;
    uint256 internal _p1_05     = 1.051140132040790557 * 1e18;
    uint256 internal _p0_951347 = 0.951347940696068854 * 1e18;
    uint256 internal _p0_607286 = 0.607286776171110946 * 1e18;
    uint256 internal _p0_189977 = 0.189977179263271283 * 1e18;
    uint256 internal _p0_006856 = 0.006856528811048429 * 1e18;
    uint256 internal _p0_006822 = 0.006822416727411372 * 1e18;
    uint256 internal _p0_000046 = 0.000046545370002462 * 1e18;
    uint256 internal _p1        = 1 * 1e18;

    /**
     *  @notice Tests price maps to index. BucketMath revert: attempt to get index of bad price.
     */
    function testPriceToIndex() public {
        uint256 badPrice = 5 * 10**10;

        vm.expectRevert("BM:PTI:OOB");
        BucketMath.priceToIndex(badPrice);

        uint256 priceToTest = 5 * 10**18;
        int256 index = BucketMath.priceToIndex(priceToTest);

        assertEq(index, 323);
    }

    /**
     *  @notice Tests validity of min and max prices.
     */
    function testIsValidPrice() public {
        assertTrue( BucketMath.isValidPrice(BucketMath.MAX_PRICE));
        assertTrue( BucketMath.isValidPrice(BucketMath.MIN_PRICE));
        assertTrue( BucketMath.isValidPrice(_p49910));
        assertTrue(!BucketMath.isValidPrice(2_000 * 10 ** 18));
    }

    /**
     *  @notice Tests verying prices map to indexes properly.
     */
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

    /**
     *  @notice Tests that price to index and index to price return correct values.
     */
    function testPriceBucketCorrectness() public {
        for (int256 i = BucketMath.MIN_PRICE_INDEX; i < BucketMath.MAX_PRICE_INDEX; i++) {
            uint256 priceToTest = BucketMath.indexToPrice(i);

            assertEq(BucketMath.priceToIndex(priceToTest), i);
            assertEq(priceToTest,                          BucketMath.indexToPrice(i));
        }
    }

    /**
     *  @notice Tests retrieveal of closest bucket to given price.
     */
    function testClosestPriceBucket() public {
        uint256 priceToTest = 2_000 * 10**18;

        (int256 index, uint256 price) = BucketMath.getClosestBucket(priceToTest);

        assertEq(index, 1524);
        assertEq(price, _p2000);
    }

    /**
     *  @notice Tests get closest bucket with fuzzing.
     */
    function testPriceToIndexFuzzy(uint256 priceToIndex_) public {
        if (priceToIndex_ < BucketMath.MIN_PRICE || priceToIndex_ >= BucketMath.MAX_PRICE) {
            return;
        }

        (int256 index, uint256 price) = BucketMath.getClosestBucket(priceToIndex_);

        assertEq(BucketMath.indexToPrice(index), price);
        assertEq(BucketMath.priceToIndex(price), index);
    }

}
