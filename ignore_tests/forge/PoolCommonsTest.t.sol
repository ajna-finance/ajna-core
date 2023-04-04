// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.14;

import './utils/DSTestPlus.sol';

import 'src/libraries/external/PoolCommons.sol';

contract PoolCommonsTest is DSTestPlus {

    /**
     *  @notice Tests pending inflator calculation for varying parameters
     */
    function testPendingInflator() external {
        uint256 inflatorSnapshot = 0.01 * 1e18; 
        skip(730 days);
        uint256 lastInflatorSnapshotUpdate = block.timestamp - 365 days; 
        uint256 interestRate = 0.1 * 1e18;
        assertEq(PoolCommons.pendingInflator(inflatorSnapshot, lastInflatorSnapshotUpdate, interestRate),   Maths.wmul(inflatorSnapshot,PRBMathUD60x18.exp(interestRate)));
        assertEq(PoolCommons.pendingInflator(inflatorSnapshot, block.timestamp - 1 hours, interestRate),    0.010000114155902715 * 1e18);
        assertEq(PoolCommons.pendingInflator(inflatorSnapshot, block.timestamp - 10 hours, interestRate),   0.010001141617671002 * 1e18);
        assertEq(PoolCommons.pendingInflator(inflatorSnapshot, block.timestamp - 1 days, interestRate),     0.010002740101366609 * 1e18);
        assertEq(PoolCommons.pendingInflator(inflatorSnapshot, block.timestamp - 5 hours, 0.042 * 1e18 ),   0.010000239728900849 * 1e18);
    }

    /**
     *  @notice Tests pending interest factor calculation for varying parameters
     */
    function testPendingInterestFactor() external {
        uint256 interestRate = 0.1 * 1e18;
        uint256 elapsed = 1 days;
        assertEq(PoolCommons.pendingInterestFactor(interestRate, elapsed),    1.000274010136660929 * 1e18);
        assertEq(PoolCommons.pendingInterestFactor(interestRate, 1 hours),    1.000011415590271509 * 1e18);
        assertEq(PoolCommons.pendingInterestFactor(interestRate, 10 hours),   1.000114161767100174 * 1e18);
        assertEq(PoolCommons.pendingInterestFactor(interestRate, 1 minutes),  1.000000190258770001 * 1e18);
        assertEq(PoolCommons.pendingInterestFactor(interestRate, 30 days),    1.008253048257773742 * 1e18);
        assertEq(PoolCommons.pendingInterestFactor(interestRate, 365 days),   1.105170918075647624 * 1e18);
    }

    /**
     *  @notice Tests lender interest margin for varying meaningful actual utilization values
     */
    function testLenderInterestMargin() external {
        assertEq(PoolCommons.lenderInterestMargin(0 * 1e18),          0.849999999999999999 * 1e18 );
        assertEq(PoolCommons.lenderInterestMargin(0.1 * 1e18),        0.855176592309155536 * 1e18 );
        assertEq(PoolCommons.lenderInterestMargin(0.2 * 1e18),        0.860752334991616632 * 1e18 );
        assertEq(PoolCommons.lenderInterestMargin(0.25 * 1e18),       0.863715955537589525 * 1e18 );
        assertEq(PoolCommons.lenderInterestMargin(0.5 * 1e18),        0.880944921102385039 * 1e18 );
        assertEq(PoolCommons.lenderInterestMargin(0.75 * 1e18),       0.905505921257884512 * 1e18 );
        assertEq(PoolCommons.lenderInterestMargin(0.99 * 1e18),       0.967683479649521744 * 1e18);
        assertEq(PoolCommons.lenderInterestMargin(0.9998 * 1e18),     0.991227946785361402 * 1e18);
        assertEq(PoolCommons.lenderInterestMargin(0.99999998 * 1e18), 1 * 1e18);
        assertEq(PoolCommons.lenderInterestMargin(1 * 1e18),          1 * 1e18);
        assertEq(PoolCommons.lenderInterestMargin(1.1 * 1e18),        1 * 1e18);
    }

}
