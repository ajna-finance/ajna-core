// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.18;

import '../utils/DSTestPlus.sol';

import 'src/libraries/external/PoolCommons.sol';
import { _dwatp, MIN_PRICE, MAX_PRICE } from 'src/libraries/helpers/PoolHelper.sol';

contract PoolCommonsTest is DSTestPlus {
    DepositsState internal deposits;

    /**
     *  @notice Tests pending inflator calculation for varying parameters
     */
    function testPendingInflator() external {
        uint256 inflator = 0.01 * 1e18; 
        skip(730 days);
        uint256 lastInflatorUpdate = block.timestamp - 365 days; 
        uint256 interestRate = 0.1 * 1e18;
        assertEq(PoolCommons.pendingInflator(inflator, lastInflatorUpdate, interestRate),   Maths.wmul(inflator, PRBMathUD60x18.exp(interestRate)));
        assertEq(PoolCommons.pendingInflator(inflator, block.timestamp - 1 hours, interestRate),    0.010000114155902715 * 1e18);
        assertEq(PoolCommons.pendingInflator(inflator, block.timestamp - 10 hours, interestRate),   0.010001141617671002 * 1e18);
        assertEq(PoolCommons.pendingInflator(inflator, block.timestamp - 1 days, interestRate),     0.010002740101366609 * 1e18);
        assertEq(PoolCommons.pendingInflator(inflator, block.timestamp - 5 hours, 0.042 * 1e18 ),   0.010000239728900849 * 1e18);
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

    function testMeaningfulDeposit() external {
        // set deposit tree sum
        deposits.values[8192] = 1_000 * 1e18;

        // if no debt in pool then dwatp is 0 and meaningful deposit is deposit tree sum
        uint256 t0DebtInAuction = 0;
        uint256 nonAuctionedT0Debt = 0;
        uint256 inflator = 1e18;
        uint256 t0Debt2ToCollateral = 100 * 1e18;
        uint256 dwatp = _dwatp(nonAuctionedT0Debt, inflator, t0Debt2ToCollateral);
        assertEq(dwatp, 0);
        uint256 meaningfulDeposit = PoolCommons._meaningfulDeposit(
            deposits,
            t0DebtInAuction,
            nonAuctionedT0Debt,
            inflator,
            t0Debt2ToCollateral
        );
        assertEq(meaningfulDeposit, 1_000 * 1e18);

        // if MIN_PRICE < dwatp < MAX_PRICE then meaningful deposit is the prefix sum of dwatp index
        t0DebtInAuction = 0;
        nonAuctionedT0Debt = 500 * 1e18;
        dwatp = _dwatp(nonAuctionedT0Debt, inflator, t0Debt2ToCollateral);
        assertLt(dwatp, MAX_PRICE);
        assertGt(dwatp, MIN_PRICE);
        // set amount or prefix sum of dwatp index
        deposits.values[_indexOf(dwatp) + 1] = 555 * 1e18;
        meaningfulDeposit = PoolCommons._meaningfulDeposit(
            deposits,
            t0DebtInAuction,
            nonAuctionedT0Debt,
            inflator,
            t0Debt2ToCollateral
        );
        assertEq(meaningfulDeposit, 555 * 1e18);

        // if current debt in auction (t0 debt * inflator) is less than calculated meaningful deposit, than subtract current debt in auction
        t0DebtInAuction = 300 * 1e18;
        meaningfulDeposit = PoolCommons._meaningfulDeposit(
            deposits,
            t0DebtInAuction,
            nonAuctionedT0Debt,
            inflator,
            t0Debt2ToCollateral
        );
        // meaningfulDeposit = 555 - min(555, 300 * 1) = 255
        assertEq(meaningfulDeposit, 255 * 1e18);

        // if current debt in auction (t0 debt * inflator) is greater than meaningful deposit, than meaningful deposit is 0
        t0DebtInAuction = 300 * 1e18;
        inflator = 2 * 1e18;
        meaningfulDeposit = PoolCommons._meaningfulDeposit(
            deposits,
            t0DebtInAuction,
            nonAuctionedT0Debt,
            inflator,
            t0Debt2ToCollateral
        );
        // PROTOTECH-2: ensure t0 debt is multiplied by inflator
        // test would fail otherwise as calculated meaningful deposit (555) > t0 debt in auction (300) so meaningful deposit would be calculated as 555 - 300 = 255
        // meaningfulDeposit = 555 - min(555, 300 * 2) = 0
        assertEq(meaningfulDeposit, 0);

        // if dwatp < MIN_PRICE meaningful deposit is deposit tree sum (1000) - current t0 debt (300)
        nonAuctionedT0Debt = 1_000 * 1e18;
        t0Debt2ToCollateral = 0.000001 * 1e18;
        inflator = 1 * 1e18;
        dwatp = _dwatp(nonAuctionedT0Debt, inflator, t0Debt2ToCollateral);
        assertLt(dwatp, MAX_PRICE);
        assertLt(dwatp, MIN_PRICE);
        meaningfulDeposit = PoolCommons._meaningfulDeposit(
            deposits,
            t0DebtInAuction,
            nonAuctionedT0Debt,
            inflator,
            t0Debt2ToCollateral
        );
        assertEq(meaningfulDeposit, 700 * 1e18);

        // if dwatp > MAX_PRICE meaningful deposit is 0
        nonAuctionedT0Debt = 1 * 1e18;
        t0Debt2ToCollateral = 1_000 * 1e36;
        inflator = 1 * 1e18;
        dwatp = _dwatp(nonAuctionedT0Debt, inflator, t0Debt2ToCollateral);
        assertGt(dwatp, MAX_PRICE);
        assertGt(dwatp, MIN_PRICE);
        meaningfulDeposit = PoolCommons._meaningfulDeposit(
            deposits,
            t0DebtInAuction,
            nonAuctionedT0Debt,
            inflator,
            t0Debt2ToCollateral
        );
        assertEq(meaningfulDeposit, 0);
    }

}
