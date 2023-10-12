// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.18;

import '../utils/DSTestPlus.sol';

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

        assertEq(_bpf(debt, collateral, neutralPrice, bondFactor, price),             0.1 * 1e18);
        assertEq(_bpf(9000 * 1e18, collateral, neutralPrice, bondFactor, price),      0.083333333333333333 * 1e18);
        assertEq(_bpf(debt, collateral, neutralPrice, bondFactor, 9.5 * 1e18),        0.1 * 1e18);
        assertEq(_bpf(9000 * 1e18, collateral, neutralPrice, bondFactor, 9.5 * 1e18), 0.091666666666666667 * 1e18);
        assertEq(_bpf(9000 * 1e18, collateral, 10 * 1e18, bondFactor, 10.5 * 1e18),   -0.05 * 1e18);
        assertEq(_bpf(debt, collateral, 5 * 1e18, bondFactor, 10.5 * 1e18),           -0.1 * 1e18);
    }

    /**
     *  @notice Tests auction price multiplier for reverse dutch auction at different times
     */
    function testAuctionPrice() external {
        skip(6238);

        uint256 referencePrice = 8_678.5 * 1e18;
        uint256 kickTime       = block.timestamp;

        assertEq(_auctionPrice(referencePrice, kickTime), 2_221_696 * 1e18);
        skip(44 minutes);      // 44 minutes
        assertEq(_auctionPrice(referencePrice, kickTime), 483_524.676068186452113664 * 1e18);
        skip(16 minutes);      // 1 hour
        assertEq(_auctionPrice(referencePrice, kickTime), 277_712 * 1e18);
        skip(99 minutes);      // 2 hours, 39 minutes
        assertEq(_auctionPrice(referencePrice, kickTime), 27_712.130183984744559172 * 1e18);
        skip(3);               // 3 seconds later
        assertEq(_auctionPrice(referencePrice, kickTime), 27_704.127762591858494776 * 1e18);
        skip(57 + 80 minutes); // 4 hours 
        assertEq(_auctionPrice(referencePrice, kickTime), 17_357 * 1e18);
        skip(1 hours);         // 5 hours
        assertEq(_auctionPrice(referencePrice, kickTime), 12_273.252401054905374068 * 1e18);
        skip(1 hours);         // 6 hours
        assertEq(_auctionPrice(referencePrice, kickTime), 8_678.5 * 1e18);
        skip(2 hours);         // 8 hours
        assertEq(_auctionPrice(referencePrice, kickTime), 4_339.25 * 1e18);
        skip(2 hours);         // 10 hours
        assertEq(_auctionPrice(referencePrice, kickTime), 2_169.625 * 1e18);
        skip(1 hours);         // 11 hours
        assertEq(_auctionPrice(referencePrice, kickTime), 1_534.15655013186316308 * 1e18);
        skip(1 hours);         // 12 hours
        assertEq(_auctionPrice(referencePrice, kickTime), 1084.8125 * 1e18);
        skip(1 hours);         // 13 hours
        assertEq(_auctionPrice(referencePrice, kickTime), 767.07827506593158154 * 1e18);
        skip(2 hours);         // 15 hours
        assertEq(_auctionPrice(referencePrice, kickTime), 271.203125 * 1e18);
        skip(3 hours);         // 18 hours
        assertEq(_auctionPrice(referencePrice, kickTime), 33.900390625 * 1e18);
        skip(6 hours);        // 24 hours
        assertEq(_auctionPrice(referencePrice, kickTime), 0.529693603515625 * 1e18);
        skip(12 hours);        // 36 hours
        assertEq(_auctionPrice(referencePrice, kickTime), 0.000129319727420501 * 1e18);
        skip(36 hours);        // 72 hours
        assertEq(_auctionPrice(referencePrice, kickTime), 0.000000000000001627 * 1e18);
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

        assertEq(_claimableReserves(debt, poolSize, liquidationBondEscrowed, reserveAuctionUnclaimed, quoteTokenBalance),  8_998.000000000000000000 * 1e18);
        assertEq(_claimableReserves(debt, poolSize, liquidationBondEscrowed, reserveAuctionUnclaimed, 0),                  0);
        assertEq(_claimableReserves(0, poolSize, liquidationBondEscrowed, reserveAuctionUnclaimed, quoteTokenBalance),     7_996.999998999000000000 * 1e18);
        assertEq(_claimableReserves(debt, poolSize, liquidationBondEscrowed, reserveAuctionUnclaimed, Maths.WAD),          0);
        assertEq(_claimableReserves(debt, 11_000 * 1e18, liquidationBondEscrowed, reserveAuctionUnclaimed, 0),             0);
        assertEq(_claimableReserves(debt, poolSize, 11_000 * 1e18, reserveAuctionUnclaimed, 0),                            0);
        assertEq(_claimableReserves(debt, poolSize, liquidationBondEscrowed, 11_000 * 1e18, 0),                            0);
        assertEq(_claimableReserves(debt, 11_000 * 1e18, 11_000 * 1e18, reserveAuctionUnclaimed, 0),                       0);
        assertEq(_claimableReserves(debt, poolSize, 11_000 * 1e18, 10_895 * 1e18, quoteTokenBalance),                      0);
    }

}
