// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.14;

import './utils/DSTestPlus.sol';

import 'src/libraries/Maths.sol';
import 'src/libraries/PoolUtils.sol';
import 'src/base/Pool.sol';

contract PoolUtilsTest is DSTestPlus {

    /**
     *  @notice Tests collateral encumberance for varying values of debt and lup
     */
    function testEncumberance() external {
        uint256 debt  = 11_000.143012091382543917 * 1e18;
        uint256 price = 1_001.6501589292607751220 * 1e18;

        assertEq(PoolUtils.encumberance(debt, price),   10.98202093218880245 * 1e18);
        assertEq(PoolUtils.encumberance(0, price),      0);
        assertEq(PoolUtils.encumberance(debt, 0),       0);
        assertEq(PoolUtils.encumberance(0, 0),          0);
    }

    /**
     *  @notice Tests loan/pool collateralization for varying values of debt, collateral and lup
     */
    function testCollateralization() external {
        uint256 debt  = 11_000.143012091382543917 * 1e18;
        uint256 price = 1_001.6501589292607751220 * 1e18;
        uint256 collateral = 10.98202093218880245 * 1e18;

        assertEq(PoolUtils.collateralization(debt, collateral, price),   1 * 1e18);
        assertEq(PoolUtils.collateralization(0, collateral, price),      Maths.WAD);
        assertEq(PoolUtils.collateralization(debt, collateral, 0),       Maths.WAD);
        assertEq(PoolUtils.collateralization(0, collateral, 0),          Maths.WAD);
        assertEq(PoolUtils.collateralization(debt, 0, price),            0);
    }

    /**
     *  @notice Tests pool target utilization based on varying values of debt and lup estimated moving averages
     */
    function testPoolTargetUtilization() external {
        uint256 debtEma  = 11_000.143012091382543917 * 1e18;
        uint256 lupColEma = 1_001.6501589292607751220 * 1e18;

        assertEq(PoolUtils.poolTargetUtilization(debtEma, lupColEma),   10.98202093218880245 * 1e18);
        assertEq(PoolUtils.poolTargetUtilization(0, lupColEma),         Maths.WAD);
        assertEq(PoolUtils.poolTargetUtilization(debtEma, 0),           Maths.WAD);
        assertEq(PoolUtils.poolTargetUtilization(0, 0),                 Maths.WAD);
    }

    /**
     *  @notice Tests fee rate for early withdrawals
     */
    function testFeeRate() external {
        uint256 interestRate = 0.12 * 1e18;
        assertEq(PoolUtils.feeRate(interestRate),  0.002307692307692308 * 1e18);
        assertEq(PoolUtils.feeRate(0.52 * 1e18),     0.01 * 1e18);
        assertEq(PoolUtils.feeRate(0.26 * 1e18),     0.005 * 1e18);
    }

    /**
     *  @notice Tests the minimum debt amount calculations for varying parameters
     */
    function testMinDebtAmount() external {
        uint256 debt = 11_000 * 1e18;
        uint256 loansCount = 50;

        assertEq(PoolUtils.minDebtAmount(debt, loansCount), 22 * 1e18);
        assertEq(PoolUtils.minDebtAmount(debt, 10),         110 * 1e18);
        assertEq(PoolUtils.minDebtAmount(debt, 0),          0);
        assertEq(PoolUtils.minDebtAmount(0, loansCount),    0);
    }

    /**
     *  @notice Tests early withdrawal amount after penalty for varying parameters
     */
    function testApplyEarlyWithdrawalPenalty() external {
        Pool.PoolState memory poolState_;
        poolState_.collateral = 5 * 1e18;
        poolState_.accruedDebt = 8000 * 1e18; 
        poolState_.rate = 0.05 * 1e18;
        skip(4 days);
        uint256 depositTime = block.timestamp - 2 days;
        uint256 fromIndex  = 1524; // price -> 2_000.221618840727700609 * 1e18
        uint256 toIndex  = 1000; // price -> 146.575625611106531706 * 1e18
        uint256 amount  = 100000 * 1e18;

        assertEq(PoolUtils.applyEarlyWithdrawalPenalty(poolState_, depositTime, fromIndex, toIndex, amount), amount);

        poolState_.collateral = 2 * 1e18;
        assertEq(PoolUtils.applyEarlyWithdrawalPenalty(poolState_, depositTime, fromIndex, toIndex, amount), amount);

        assertEq(PoolUtils.applyEarlyWithdrawalPenalty(poolState_, block.timestamp - 4 hours, fromIndex, 0, amount), 99903.8461538461538 * 1e18);

        poolState_.collateral = 0; // should apply penalty also when no collateral in pool
        assertEq(PoolUtils.applyEarlyWithdrawalPenalty(poolState_, block.timestamp - 4 hours, fromIndex, 0, amount), 99903.8461538461538 * 1e18);
    }

    /**
     *  @notice Tests fenwick index calculation from varying bucket prices
     */
    function testPriceToIndex() external {

        assertEq(PoolUtils.priceToIndex(1_004_968_987.606512354182109771 * 10**18), 0);

        assertEq(PoolUtils.priceToIndex(99_836_282_890),                            7388);

        assertEq(PoolUtils.priceToIndex(49_910.043670274810022205 * 1e18),          1987);

        assertEq(PoolUtils.priceToIndex(2_000.221618840727700609 * 1e18),           2632);

        assertEq(PoolUtils.priceToIndex(146.575625611106531706 * 1e18),             3156);

        assertEq(PoolUtils.priceToIndex(145.846393642892072537 * 1e18),             3157);

        assertEq(PoolUtils.priceToIndex(5.263790124045347667 * 1e18),               3823);

        assertEq(PoolUtils.priceToIndex(1.646668492116543299 * 1e18),               4056);

        assertEq(PoolUtils.priceToIndex(1.315628874808846999 * 1e18),               4101);

        assertEq(PoolUtils.priceToIndex(1.051140132040790557 * 1e18),               4146);

        assertEq(PoolUtils.priceToIndex(0.000046545370002462 * 1e18),               6156);

        assertEq(PoolUtils.priceToIndex(0.006822416727411372 * 1e18),               5156);

        assertEq(PoolUtils.priceToIndex(0.006856528811048429 * 1e18),               5155);

        assertEq(PoolUtils.priceToIndex(0.951347940696068854 * 1e18),               4166);
        
    }

    /**
     *  @notice Tests bucket price calculation from varying fenwick index
     */
    function testIndexToPrice() external {

        assertEq(PoolUtils.indexToPrice( 0 ),      1_004_968_987.606512354182109771 * 10**18);
        
        assertEq(PoolUtils.indexToPrice( 7388 ),   99_836_282_890);

        assertEq(PoolUtils.indexToPrice( 1987 ),   49_910.043670274810022205 * 1e18);

        assertEq(PoolUtils.indexToPrice( 2632 ),   2_000.221618840727700609 * 1e18);

        assertEq(PoolUtils.indexToPrice( 3156 ),   146.575625611106531706 * 1e18);

        assertEq(PoolUtils.indexToPrice( 3157 ),   145.846393642892072537 * 1e18);

        assertEq(PoolUtils.indexToPrice( 3823 ),   5.263790124045347667 * 1e18);

        assertEq(PoolUtils.indexToPrice( 4056 ),   1.646668492116543299 * 1e18);

        assertEq(PoolUtils.indexToPrice( 4101 ),   1.315628874808846999 * 1e18);

        assertEq(PoolUtils.indexToPrice( 4146 ),   1.051140132040790557 * 1e18);

        assertEq(PoolUtils.indexToPrice( 6156 ),   0.000046545370002462 * 1e18);

        assertEq(PoolUtils.indexToPrice( 5156 ),   0.006822416727411372 * 1e18);

        assertEq(PoolUtils.indexToPrice( 5155 ),   0.006856528811048429 * 1e18);

        assertEq(PoolUtils.indexToPrice( 4166 ),   0.951347940696068854 * 1e18);
        
    }
}
