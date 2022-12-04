// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.14;

import './utils/DSTestPlus.sol';

import 'src/libraries/Maths.sol';
import 'src/base/Pool.sol';

contract PoolUtilsTest is DSTestPlus {

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
