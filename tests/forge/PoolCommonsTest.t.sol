// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.14;

import './utils/DSTestPlus.sol';

import 'src/libraries/external/PoolCommons.sol';

contract PoolCommonsTest is DSTestPlus {

    /**
     *  @notice Tests fenwick index calculation from varying bucket prices
     */
    function testPriceToIndex() external {
        assertEq(PoolCommons.priceToIndex(1_004_968_987.606512354182109771 * 10**18), 0);
        assertEq(PoolCommons.priceToIndex(99_836_282_890),                            7388);
        assertEq(PoolCommons.priceToIndex(49_910.043670274810022205 * 1e18),          1987);
        assertEq(PoolCommons.priceToIndex(2_000.221618840727700609 * 1e18),           2632);
        assertEq(PoolCommons.priceToIndex(146.575625611106531706 * 1e18),             3156);
        assertEq(PoolCommons.priceToIndex(145.846393642892072537 * 1e18),             3157);
        assertEq(PoolCommons.priceToIndex(5.263790124045347667 * 1e18),               3823);
        assertEq(PoolCommons.priceToIndex(1.646668492116543299 * 1e18),               4056);
        assertEq(PoolCommons.priceToIndex(1.315628874808846999 * 1e18),               4101);
        assertEq(PoolCommons.priceToIndex(1.051140132040790557 * 1e18),               4146);
        assertEq(PoolCommons.priceToIndex(0.000046545370002462 * 1e18),               6156);
        assertEq(PoolCommons.priceToIndex(0.006822416727411372 * 1e18),               5156);
        assertEq(PoolCommons.priceToIndex(0.006856528811048429 * 1e18),               5155);
        assertEq(PoolCommons.priceToIndex(0.951347940696068854 * 1e18),               4166);
    }

    /**
     *  @notice Tests bucket price calculation from varying fenwick index
     */
    function testindexToPrice() external {
        assertEq(PoolCommons.indexToPrice( 0 ),    1_004_968_987.606512354182109771 * 10**18);
        assertEq(PoolCommons.indexToPrice( 7388 ), 99_836_282_890);
        assertEq(PoolCommons.indexToPrice( 1987 ), 49_910.043670274810022205 * 1e18);
        assertEq(PoolCommons.indexToPrice( 2632 ), 2_000.221618840727700609 * 1e18);
        assertEq(PoolCommons.indexToPrice( 3156 ), 146.575625611106531706 * 1e18);
        assertEq(PoolCommons.indexToPrice( 3157 ), 145.846393642892072537 * 1e18);
        assertEq(PoolCommons.indexToPrice( 3823 ), 5.263790124045347667 * 1e18);
        assertEq(PoolCommons.indexToPrice( 4056 ), 1.646668492116543299 * 1e18);
        assertEq(PoolCommons.indexToPrice( 4101 ), 1.315628874808846999 * 1e18);
        assertEq(PoolCommons.indexToPrice( 4146 ), 1.051140132040790557 * 1e18);
        assertEq(PoolCommons.indexToPrice( 6156 ), 0.000046545370002462 * 1e18);
        assertEq(PoolCommons.indexToPrice( 5156 ), 0.006822416727411372 * 1e18);
        assertEq(PoolCommons.indexToPrice( 5155 ), 0.006856528811048429 * 1e18);
        assertEq(PoolCommons.indexToPrice( 4166 ), 0.951347940696068854 * 1e18);
    }

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
