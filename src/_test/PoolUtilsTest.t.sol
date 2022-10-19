// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.14;

import './utils/DSTestPlus.sol';

import '@prb-math/contracts/PRBMathSD59x18.sol';
import '@prb-math/contracts/PRBMathUD60x18.sol';
import "forge-std/console2.sol";

import '../libraries/Maths.sol';
import '../libraries/PoolUtils.sol';
import '../base/Pool.sol';

contract PoolUtilsTest is DSTestPlus {

    /**
     *  @notice Tests claimable reserves calculation for varying parameters
     */
    function testClaimableReserves() external {
        uint256 debt = 11_000 * 1e18;
        uint256 poolSize = 1_001 * 1e18;
        uint256 liquidationBondEscrowed = 1_001 * 1e18;
        uint256 reserveAuctionUnclaimed = 1_001 * 1e18;
        uint256 quoteTokenBalance = 11_000 * 1e18;

        assertEq(PoolUtils.claimableReserves(debt, poolSize, liquidationBondEscrowed, reserveAuctionUnclaimed, quoteTokenBalance),18_942 * 1e18);
        assertEq(PoolUtils.claimableReserves(debt, poolSize, liquidationBondEscrowed, reserveAuctionUnclaimed, 0), 7_942 * 1e18);
        assertEq(PoolUtils.claimableReserves(0, poolSize, liquidationBondEscrowed, reserveAuctionUnclaimed, quoteTokenBalance), 7_997 * 1e18);
        assertEq(PoolUtils.claimableReserves(debt, poolSize, liquidationBondEscrowed, reserveAuctionUnclaimed, Maths.WAD),  7_943 * 1e18);
        assertEq(PoolUtils.claimableReserves(debt, 11_000 * 1e18, liquidationBondEscrowed, reserveAuctionUnclaimed, 0),  0);
        assertEq(PoolUtils.claimableReserves(debt, poolSize, 11_000 * 1e18, reserveAuctionUnclaimed, 0),  0);
        assertEq(PoolUtils.claimableReserves(debt, poolSize, liquidationBondEscrowed, 11_000 * 1e18, 0),  0);
        assertEq(PoolUtils.claimableReserves(debt, 11_000 * 1e18, 11_000 * 1e18, reserveAuctionUnclaimed, 0),  0);
        assertEq(PoolUtils.claimableReserves(debt, poolSize, 11_000 * 1e18, 10_895 * 1e18, quoteTokenBalance),  0);

    }

    /**
     *  @notice Tests collateral encumberance for varying values of debt and lup
     */
    function testEncumberance() external {
        uint256 debt  = 11_000.143012091382543917 * 1e18;
        uint256 price = 1_001.6501589292607751220 * 1e18;

        assertEq(PoolUtils.encumberance(debt, price),   10.98202093218880245 * 1e18);
        assertEq(PoolUtils.encumberance(0, price),  0);
        assertEq(PoolUtils.encumberance(debt, 0),  0);
        assertEq(PoolUtils.encumberance(0, 0),  0);
    }

    /**
     *  @notice Tests loan/pool collateralization for varying values of debt, collateral and lup
     */
    function testCollateralization() external {
        uint256 debt  = 11_000.143012091382543917 * 1e18;
        uint256 price = 1_001.6501589292607751220 * 1e18;
        uint256 collateral = 10.98202093218880245 * 1e18;

        assertEq(PoolUtils.collateralization(debt, collateral, price),   1 * 1e18);
        assertEq(PoolUtils.collateralization(0, collateral, price),   Maths.WAD);
        assertEq(PoolUtils.collateralization(debt, collateral, 0),   Maths.WAD);
        assertEq(PoolUtils.collateralization(0, collateral, 0),   Maths.WAD);
        assertEq(PoolUtils.collateralization(debt, 0, price),   0);
    }

    /**
     *  @notice Tests pool target utilization based on varying values of debt and lup estimated moving averages
     */
    function testPoolTargetUtilization() external {
        uint256 debtEma  = 11_000.143012091382543917 * 1e18;
        uint256 lupColEma = 1_001.6501589292607751220 * 1e18;

        assertEq(PoolUtils.poolTargetUtilization(debtEma, lupColEma),   10.98202093218880245 * 1e18);
        assertEq(PoolUtils.poolTargetUtilization(0, lupColEma),  Maths.WAD);
        assertEq(PoolUtils.poolTargetUtilization(debtEma, 0),  Maths.WAD);
        assertEq(PoolUtils.poolTargetUtilization(0, 0),  Maths.WAD);
    }

    /**
     *  @notice Tests fee rate for early withdrawals
     */
    function testFeeRate() external {
        uint256 interestRate = 0.05 * 1e18;
        uint256 minFees = 0.005 * 1e18;
        assertEq(PoolUtils.feeRate(interestRate, minFees),  minFees);
        assertEq(PoolUtils.feeRate(52 * 1e18, minFees),  1 * 1e18);
        assertEq(PoolUtils.feeRate(26 * 1e18, minFees),  0.5 * 1e18);
    }

    /**
     *  @notice Tests the minimum debt amount calculations for varying parameters
     */
    function testMinDebtAmount() external {
        uint256 debt = 11_000 * 1e18;
        uint256 loansCount = 50;

        assertEq(PoolUtils.minDebtAmount(debt, loansCount), 22 * 1e18);
        assertEq(PoolUtils.minDebtAmount(debt, 10), 110 * 1e18);
        assertEq(PoolUtils.minDebtAmount(debt, 0),  0);
        assertEq(PoolUtils.minDebtAmount(0, loansCount),  0);
    }

    /**
     *  @notice Tests reserve price multiplier for reverse dutch auction at different times
     */
    function testReserveAuctionPrice() external {
        skip(5 days);
        assertEq(PoolUtils.reserveAuctionPrice(block.timestamp),1e27);
        assertEq(PoolUtils.reserveAuctionPrice(block.timestamp - 1 hours),500000000 * 1e18);
        assertEq(PoolUtils.reserveAuctionPrice(block.timestamp - 2 hours),250000000 * 1e18);
        assertEq(PoolUtils.reserveAuctionPrice(block.timestamp - 4 hours),62500000 * 1e18);
        assertEq(PoolUtils.reserveAuctionPrice(block.timestamp - 16 hours),15258.789062500000000000 * 1e18);
        assertEq(PoolUtils.reserveAuctionPrice(block.timestamp - 24 hours),59.604644775390625000 * 1e18);
        assertEq(PoolUtils.reserveAuctionPrice(block.timestamp - 90 hours),0);


    }

    /**
     *  @notice Tests early withdrawal amount after penalty for varying parameters
     */
    function testApplyEarlyWithdrawalPenalty() external {
        Pool.PoolState memory poolState_;
        poolState_.collateral = 5 * 1e18;
        poolState_.accruedDebt = 8000 * 1e18; 
        poolState_.rate = 0.05 * 1e18;
        uint256 minFee = 0.5 * 1e18;
        skip(4 days);
        uint256 depositTime = block.timestamp - 2 days;
        uint256 fromIndex  = 1524; // price -> 2_000.221618840727700609 * 1e18
        uint256 toIndex  = 1000; // price -> 146.575625611106531706 * 1e18
        uint256 amount  = 100000 * 1e18;

        assertEq(PoolUtils.applyEarlyWithdrawalPenalty(poolState_, minFee, depositTime, fromIndex, toIndex, amount),    amount);

        poolState_.collateral = 2 * 1e18;
        assertEq(PoolUtils.applyEarlyWithdrawalPenalty(poolState_, minFee, depositTime, fromIndex, toIndex, amount),    amount);

        assertEq(PoolUtils.applyEarlyWithdrawalPenalty(poolState_, minFee, block.timestamp - 4 hours, fromIndex, 0, amount),    50_000 * 1e18);

        poolState_.collateral = 0;
        assertEq(PoolUtils.applyEarlyWithdrawalPenalty(poolState_, minFee, block.timestamp - 4 hours, fromIndex, 0, amount),    amount);
    }

    /**
     *  @notice Tests fenwick index calculation from varying bucket prices
     */
    function testPriceToIndex() external {

        assertEq(PoolUtils.priceToIndex(1_004_968_987.606512354182109771 * 10**18), 0);

        assertEq(PoolUtils.priceToIndex(99_836_282_890),    7388);

        assertEq(PoolUtils.priceToIndex(49_910.043670274810022205 * 1e18),  1987);

        assertEq(PoolUtils.priceToIndex(2_000.221618840727700609 * 1e18),   2632);

        assertEq(PoolUtils.priceToIndex(146.575625611106531706 * 1e18), 3156);

        assertEq(PoolUtils.priceToIndex(145.846393642892072537 * 1e18), 3157);

        assertEq(PoolUtils.priceToIndex(5.263790124045347667 * 1e18),   3823);

        assertEq(PoolUtils.priceToIndex(1.646668492116543299 * 1e18),   4056);

        assertEq(PoolUtils.priceToIndex(1.315628874808846999 * 1e18),   4101);

        assertEq(PoolUtils.priceToIndex(1.051140132040790557 * 1e18),   4146);

        assertEq(PoolUtils.priceToIndex(0.000046545370002462 * 1e18),   6156);

        assertEq(PoolUtils.priceToIndex(0.006822416727411372 * 1e18),   5156);

        assertEq(PoolUtils.priceToIndex(0.006856528811048429 * 1e18),   5155);

        assertEq(PoolUtils.priceToIndex(0.951347940696068854 * 1e18),   4166);
        
    }

    /**
     *  @notice Tests bucket price calculation from varying fenwick index
     */
    function testIndexToPrice() external {

        assertEq(PoolUtils.indexToPrice(0), 1_004_968_987.606512354182109771 * 10**18);
        
        assertEq(PoolUtils.indexToPrice(7388),    99_836_282_890);

        assertEq(PoolUtils.indexToPrice( 1987),  49_910.043670274810022205 * 1e18);

        assertEq(PoolUtils.indexToPrice( 2632),   2_000.221618840727700609 * 1e18);

        assertEq(PoolUtils.indexToPrice( 3156), 146.575625611106531706 * 1e18);

        assertEq(PoolUtils.indexToPrice(  3157), 145.846393642892072537 * 1e18);

        assertEq(PoolUtils.indexToPrice( 3823),   5.263790124045347667 * 1e18);

        assertEq(PoolUtils.indexToPrice( 4056),   1.646668492116543299 * 1e18);

        assertEq(PoolUtils.indexToPrice( 4101),   1.315628874808846999 * 1e18);

        assertEq(PoolUtils.indexToPrice( 4146),   1.051140132040790557 * 1e18);

        assertEq(PoolUtils.indexToPrice( 6156),   0.000046545370002462 * 1e18);

        assertEq(PoolUtils.indexToPrice( 5156),   0.006822416727411372 * 1e18);

        assertEq(PoolUtils.indexToPrice( 5155),   0.006856528811048429 * 1e18);

        assertEq(PoolUtils.indexToPrice( 4166),   0.951347940696068854 * 1e18);
        
    }
}
