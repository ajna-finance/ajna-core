// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.14;

import './utils/DSTestPlus.sol';

import 'src/libraries/Auctions.sol';

contract AuctionsTest is DSTestPlus {

    /**
     *  @notice Tests bond penalty/reward factor calculation for varying parameters
     */
    function testBpf() external {
        uint256 debt  = 11_000 * 1e18;
        uint256 price = 10 * 1e18;
        uint256 collateral = 1000 * 1e18;
        uint256 neutralPrice = 15 * 1e18;
        uint256 bondFactor = 0.1 *  1e18;

        assertEq(Auctions._bpf(debt, collateral, neutralPrice, bondFactor, price),             0.1 * 1e18);
        assertEq(Auctions._bpf(9000 * 1e18, collateral, neutralPrice, bondFactor, price),      0.083333333333333333 * 1e18);
        assertEq(Auctions._bpf(debt, collateral, neutralPrice, bondFactor, 9.5 * 1e18),        0.1 * 1e18);
        assertEq(Auctions._bpf(9000 * 1e18, collateral, neutralPrice, bondFactor, 9.5 * 1e18), 0.091666666666666667 * 1e18);
        assertEq(Auctions._bpf(9000 * 1e18, collateral, 10 * 1e18, bondFactor, 10.5 * 1e18),   -0.05 * 1e18);
        assertEq(Auctions._bpf(debt, collateral, 5 * 1e18, bondFactor, 10.5 * 1e18),           -0.1 * 1e18);
    }

    /**
     *  @notice Tests auction price multiplier for reverse dutch auction at different times
     */
    function testAuctionPrice() external {
        skip(6238);
        uint256 referencePrice = 8_678.5 * 1e18;
        uint256 kickTime = block.timestamp;
        assertEq(Auctions._auctionPrice(referencePrice, kickTime), 277_712 * 1e18);
        skip(1444); // price should not change in the first hour
        assertEq(Auctions._auctionPrice(referencePrice, kickTime), 277_712 * 1e18);

        skip(5756);     // 2 hours
        assertEq(Auctions._auctionPrice(referencePrice, kickTime), 138_856 * 1e18);
        skip(2394);     // 2 hours, 39 minutes, 54 seconds
        assertEq(Auctions._auctionPrice(referencePrice, kickTime), 87_574.910740335995562528 * 1e18);
        skip(2586);     // 3 hours, 23 minutes
        assertEq(Auctions._auctionPrice(referencePrice, kickTime), 53_227.960156860514117568 * 1e18);
        skip(3);        // 3 seconds later
        assertEq(Auctions._auctionPrice(referencePrice, kickTime), 53_197.223359425583052544 * 1e18);
        skip(20153);    // 8 hours, 35 minutes, 53 seconds
        assertEq(Auctions._auctionPrice(referencePrice, kickTime), 1_098.26293050754894624 * 1e18);
        skip(97264);    // 36 hours
        assertEq(Auctions._auctionPrice(referencePrice, kickTime), 0.00000808248283696 * 1e18);
        skip(129600);   // 72 hours
        assertEq(Auctions._auctionPrice(referencePrice, kickTime), 0);
    }

    /**
     *  @notice Tests reserve price multiplier for reverse dutch auction at different times
     */
    function testReserveAuctionPrice() external {
        skip(5 days);
        assertEq(Auctions.reserveAuctionPrice(block.timestamp),            1e27);
        assertEq(Auctions.reserveAuctionPrice(block.timestamp - 1 hours),  500000000 * 1e18);
        assertEq(Auctions.reserveAuctionPrice(block.timestamp - 2 hours),  250000000 * 1e18);
        assertEq(Auctions.reserveAuctionPrice(block.timestamp - 4 hours),  62500000 * 1e18);
        assertEq(Auctions.reserveAuctionPrice(block.timestamp - 16 hours), 15258.789062500000000000 * 1e18);
        assertEq(Auctions.reserveAuctionPrice(block.timestamp - 24 hours), 59.604644775390625000 * 1e18);
        assertEq(Auctions.reserveAuctionPrice(block.timestamp - 90 hours), 0);
    }

    /**
     *  @notice Tests claimable reserves calculation for varying parameters
     */
    function testClaimableReserves() external {
        uint256 debt = 11_000 * 1e18;
        uint256 poolSize = 1_001 * 1e18;
        uint256 liquidationBondEscrowed = 1_001 * 1e18;
        uint256 reserveAuctionUnclaimed = 1_001 * 1e18;
        uint256 quoteTokenBalance = 11_000 * 1e18;

        assertEq(Auctions.claimableReserves(debt, poolSize, liquidationBondEscrowed, reserveAuctionUnclaimed, quoteTokenBalance),  18_942 * 1e18);
        assertEq(Auctions.claimableReserves(debt, poolSize, liquidationBondEscrowed, reserveAuctionUnclaimed, 0),                  7_942 * 1e18);
        assertEq(Auctions.claimableReserves(0, poolSize, liquidationBondEscrowed, reserveAuctionUnclaimed, quoteTokenBalance),     7_997 * 1e18);
        assertEq(Auctions.claimableReserves(debt, poolSize, liquidationBondEscrowed, reserveAuctionUnclaimed, Maths.WAD),          7_943 * 1e18);
        assertEq(Auctions.claimableReserves(debt, 11_000 * 1e18, liquidationBondEscrowed, reserveAuctionUnclaimed, 0),             0);
        assertEq(Auctions.claimableReserves(debt, poolSize, 11_000 * 1e18, reserveAuctionUnclaimed, 0),                            0);
        assertEq(Auctions.claimableReserves(debt, poolSize, liquidationBondEscrowed, 11_000 * 1e18, 0),                            0);
        assertEq(Auctions.claimableReserves(debt, 11_000 * 1e18, 11_000 * 1e18, reserveAuctionUnclaimed, 0),                       0);
        assertEq(Auctions.claimableReserves(debt, poolSize, 11_000 * 1e18, 10_895 * 1e18, quoteTokenBalance),                      0);

    }

    /**
     *  @notice Tests fenwick index calculation from varying bucket prices
     */
    function testPriceToIndex() external {
        assertAuctionPriceToIndex(1_004_968_987.606512354182109771 * 10**18);
        assertAuctionPriceToIndex(99_836_282_890);
        assertAuctionPriceToIndex(49_910.043670274810022205 * 1e18);
        assertAuctionPriceToIndex(2_000.221618840727700609 * 1e18);
        assertAuctionPriceToIndex(146.575625611106531706 * 1e18);
        assertAuctionPriceToIndex(145.846393642892072537 * 1e18);
        assertAuctionPriceToIndex(5.263790124045347667 * 1e18);
        assertAuctionPriceToIndex(1.646668492116543299 * 1e18);
        assertAuctionPriceToIndex(1.315628874808846999 * 1e18);
        assertAuctionPriceToIndex(1.051140132040790557 * 1e18);
        assertAuctionPriceToIndex(0.000046545370002462 * 1e18);
        assertAuctionPriceToIndex(0.006822416727411372 * 1e18);
        assertAuctionPriceToIndex(0.006856528811048429 * 1e18);
        assertAuctionPriceToIndex(0.951347940696068854 * 1e18);        
    }

    /**
     *  @notice Tests bucket price calculation from varying fenwick index
     */
    function testIndexToPrice() external {
        assertAuctionIndexToPrice(0);
        assertAuctionIndexToPrice(7388);
        assertAuctionIndexToPrice(1987);
        assertAuctionIndexToPrice(2632);
        assertAuctionIndexToPrice(3156);
        assertAuctionIndexToPrice(3157);
        assertAuctionIndexToPrice(3823);
        assertAuctionIndexToPrice(4056);
        assertAuctionIndexToPrice(4101);
        assertAuctionIndexToPrice(4146);
        assertAuctionIndexToPrice(6156);
        assertAuctionIndexToPrice(5156);
        assertAuctionIndexToPrice(5155);
        assertAuctionIndexToPrice(4166);
    }

    function assertAuctionIndexToPrice(uint256 index_) internal {
        assertEq(Auctions._indexToPrice(index_), PoolUtils.indexToPrice(index_));
    }

    function assertAuctionPriceToIndex(uint256 price_) internal {
        assertEq(Auctions._priceToIndex(price_), PoolUtils.priceToIndex(price_));
    }

}
