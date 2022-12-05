// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.14;

import './utils/DSTestPlus.sol';

import 'src/libraries/Maths.sol';
import 'src/base/Pool.sol';

contract PoolUtilsTest is DSTestPlus {

    /**
     *  @notice Tests fenwick index calculation from varying bucket prices
     */
    function testPriceToIndex() external {
        assertEq(indexOf(1_004_968_987.606512354182109771 * 10**18), 0);
        assertEq(indexOf(99_836_282_890),                            7388);
        assertEq(indexOf(49_910.043670274810022205 * 1e18),          1987);
        assertEq(indexOf(2_000.221618840727700609 * 1e18),           2632);
        assertEq(indexOf(146.575625611106531706 * 1e18),             3156);
        assertEq(indexOf(145.846393642892072537 * 1e18),             3157);
        assertEq(indexOf(5.263790124045347667 * 1e18),               3823);
        assertEq(indexOf(1.646668492116543299 * 1e18),               4056);
        assertEq(indexOf(1.315628874808846999 * 1e18),               4101);
        assertEq(indexOf(1.051140132040790557 * 1e18),               4146);
        assertEq(indexOf(0.000046545370002462 * 1e18),               6156);
        assertEq(indexOf(0.006822416727411372 * 1e18),               5156);
        assertEq(indexOf(0.006856528811048429 * 1e18),               5155);
        assertEq(indexOf(0.951347940696068854 * 1e18),               4166);
    }

    /**
     *  @notice Tests bucket price calculation from varying fenwick index
     */
    function testindexToPrice() external {
        assertEq(priceAt( 0 ),    1_004_968_987.606512354182109771 * 10**18);
        assertEq(priceAt( 7388 ), 99_836_282_890);
        assertEq(priceAt( 1987 ), 49_910.043670274810022205 * 1e18);
        assertEq(priceAt( 2632 ), 2_000.221618840727700609 * 1e18);
        assertEq(priceAt( 3156 ), 146.575625611106531706 * 1e18);
        assertEq(priceAt( 3157 ), 145.846393642892072537 * 1e18);
        assertEq(priceAt( 3823 ), 5.263790124045347667 * 1e18);
        assertEq(priceAt( 4056 ), 1.646668492116543299 * 1e18);
        assertEq(priceAt( 4101 ), 1.315628874808846999 * 1e18);
        assertEq(priceAt( 4146 ), 1.051140132040790557 * 1e18);
        assertEq(priceAt( 6156 ), 0.000046545370002462 * 1e18);
        assertEq(priceAt( 5156 ), 0.006822416727411372 * 1e18);
        assertEq(priceAt( 5155 ), 0.006856528811048429 * 1e18);
        assertEq(priceAt( 4166 ), 0.951347940696068854 * 1e18);
    }

    /**
     *  @notice Tests collateral encumberance for varying values of debt and lup
     */
    function testEncumberance() external {
        uint256 debt  = 11_000.143012091382543917 * 1e18;
        uint256 price = 1_001.6501589292607751220 * 1e18;

        assertEq(encumberance(debt, price),   10.98202093218880245 * 1e18);
        assertEq(encumberance(0, price),      0);
        assertEq(encumberance(debt, 0),       0);
        assertEq(encumberance(0, 0),          0);
    }

    /**
     *  @notice Tests loan/pool collateralization for varying values of debt, collateral and lup
     */
    function testCollateralization() external {
        uint256 debt  = 11_000.143012091382543917 * 1e18;
        uint256 price = 1_001.6501589292607751220 * 1e18;
        uint256 collateral = 10.98202093218880245 * 1e18;

        assertEq(collateralization(debt, collateral, price),   1 * 1e18);
        assertEq(collateralization(0, collateral, price),      Maths.WAD);
        assertEq(collateralization(debt, collateral, 0),       Maths.WAD);
        assertEq(collateralization(0, collateral, 0),          Maths.WAD);
        assertEq(collateralization(debt, 0, price),            0);
    }

    /**
     *  @notice Tests pool target utilization based on varying values of debt and lup estimated moving averages
     */
    function testPoolTargetUtilization() external {
        uint256 debtEma  = 11_000.143012091382543917 * 1e18;
        uint256 lupColEma = 1_001.6501589292607751220 * 1e18;

        assertEq(targetUtilization(debtEma, lupColEma), 10.98202093218880245 * 1e18);
        assertEq(targetUtilization(0, lupColEma),       Maths.WAD);
        assertEq(targetUtilization(debtEma, 0),         Maths.WAD);
        assertEq(targetUtilization(0, 0),               Maths.WAD);
    }

    /**
     *  @notice Tests fee rate for early withdrawals
     */
    function testFeeRate() external {
        uint256 interestRate = 0.12 * 1e18;
        assertEq(feeRate(interestRate),  0.002307692307692308 * 1e18);
        assertEq(feeRate(0.52 * 1e18),     0.01 * 1e18);
        assertEq(feeRate(0.26 * 1e18),     0.005 * 1e18);
    }

    /**
     *  @notice Tests the minimum debt amount calculations for varying parameters
     */
    function testMinDebtAmount() external {
        uint256 debt = 11_000 * 1e18;
        uint256 loansCount = 50;

        assertEq(minDebtAmount(debt, loansCount), 22 * 1e18);
        assertEq(minDebtAmount(debt, 10),         110 * 1e18);
        assertEq(minDebtAmount(debt, 0),          0);
        assertEq(minDebtAmount(0, loansCount),    0);
    }
}
