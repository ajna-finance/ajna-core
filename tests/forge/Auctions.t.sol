// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.14;

import './utils/DSTestPlus.sol';

import 'src/libraries/external/Auctions.sol';

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

        uint256 momp         = 8_678.5 * 1e18;
        uint256 neutralPrice = 8_600.0 * 1e18;
        uint256 kickTime     = block.timestamp;

        assertEq(Auctions._auctionPrice(momp, neutralPrice, kickTime), 277_712 * 1e18);
        skip(1444); // price should not change in the first hour
        assertEq(Auctions._auctionPrice(momp, neutralPrice, kickTime), 277_712 * 1e18);

        skip(5756);     // 2 hours
        assertEq(Auctions._auctionPrice(momp, neutralPrice, kickTime), 138_856 * 1e18);
        skip(2394);     // 2 hours, 39 minutes, 54 seconds
        assertEq(Auctions._auctionPrice(momp, neutralPrice, kickTime), 87_574.910740335995562528 * 1e18);
        skip(2586);     // 3 hours, 23 minutes
        assertEq(Auctions._auctionPrice(momp, neutralPrice, kickTime), 53_227.960156860514117568 * 1e18);
        skip(3);        // 3 seconds later
        assertEq(Auctions._auctionPrice(momp, neutralPrice, kickTime), 53_197.223359425583052544 * 1e18);
        skip(20153);    // 8 hours, 35 minutes, 53 seconds
        assertEq(Auctions._auctionPrice(momp, neutralPrice, kickTime), 1_098.26293050754894624 * 1e18);
        skip(97264);    // 36 hours
        assertEq(Auctions._auctionPrice(momp, neutralPrice, kickTime), 0.00000808248283696 * 1e18);
        skip(129600);   // 72 hours
        assertEq(Auctions._auctionPrice(momp, neutralPrice, kickTime), 0);
    }

    /**
     *  @notice Tests reserve price multiplier for reverse dutch auction at different times
     */
    function testReserveAuctionPrice() external {
        skip(5 days);
        assertEq(_reserveAuctionPrice(block.timestamp),            1e27);
        assertEq(_reserveAuctionPrice(block.timestamp - 1 hours),  500000000 * 1e18);
        assertEq(_reserveAuctionPrice(block.timestamp - 2 hours),  250000000 * 1e18);
        assertEq(_reserveAuctionPrice(block.timestamp - 4 hours),  62500000 * 1e18);
        assertEq(_reserveAuctionPrice(block.timestamp - 16 hours), 15258.789062500000000000 * 1e18);
        assertEq(_reserveAuctionPrice(block.timestamp - 24 hours), 59.604644775390625000 * 1e18);
        assertEq(_reserveAuctionPrice(block.timestamp - 90 hours), 0);
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

        assertEq(_claimableReserves(debt, poolSize, liquidationBondEscrowed, reserveAuctionUnclaimed, quoteTokenBalance),  18_942 * 1e18);
        assertEq(_claimableReserves(debt, poolSize, liquidationBondEscrowed, reserveAuctionUnclaimed, 0),                  7_942 * 1e18);
        assertEq(_claimableReserves(0, poolSize, liquidationBondEscrowed, reserveAuctionUnclaimed, quoteTokenBalance),     7_997 * 1e18);
        assertEq(_claimableReserves(debt, poolSize, liquidationBondEscrowed, reserveAuctionUnclaimed, Maths.WAD),          7_943 * 1e18);
        assertEq(_claimableReserves(debt, 11_000 * 1e18, liquidationBondEscrowed, reserveAuctionUnclaimed, 0),             0);
        assertEq(_claimableReserves(debt, poolSize, 11_000 * 1e18, reserveAuctionUnclaimed, 0),                            0);
        assertEq(_claimableReserves(debt, poolSize, liquidationBondEscrowed, 11_000 * 1e18, 0),                            0);
        assertEq(_claimableReserves(debt, 11_000 * 1e18, 11_000 * 1e18, reserveAuctionUnclaimed, 0),                       0);
        assertEq(_claimableReserves(debt, poolSize, 11_000 * 1e18, 10_895 * 1e18, quoteTokenBalance),                      0);

    }

}
