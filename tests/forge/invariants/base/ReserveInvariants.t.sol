// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.18;

import "@std/console.sol";

import { Maths } from "src/libraries/internal/Maths.sol";

import { IBaseHandler }          from '../interfaces/IBaseHandler.sol';
import { LiquidationInvariants } from './LiquidationInvariants.t.sol';

abstract contract ReserveInvariants is LiquidationInvariants {

    function invariant_reserves() public useCurrentTimestamp {

        uint256 previousReserves   = IBaseHandler(_handler).previousReserves();
        uint256 increaseInReserves = IBaseHandler(_handler).increaseInReserves();
        uint256 decreaseInReserves = IBaseHandler(_handler).decreaseInReserves();
        (uint256 currentReserves, , , , ) = _poolInfo.poolReservesInfo(address(_pool));

        console.log("Previous Reserves     -->", previousReserves);
        console.log("Increase in Reserves  -->", increaseInReserves);
        console.log("Decrease in Reserves  -->", decreaseInReserves);
        console.log("Current Reserves      -->", currentReserves);
        console.log("Required Reserves     -->", previousReserves + increaseInReserves - decreaseInReserves);

        requireWithinDiff(
            currentReserves,
            previousReserves + increaseInReserves - decreaseInReserves,
            Maths.max(_pool.quoteTokenScale(), 1e13),
            "Incorrect Reserves change"
        );
    }

    function invariant_call_summary() public virtual override useCurrentTimestamp {
        console.log("\nCall Summary\n");
        console.log("--Lender----------");
        console.log("BReserveHandler.addQuoteToken         ",  IBaseHandler(_handler).numberOfCalls("BBasicHandler.addQuoteToken"));
        console.log("UBReserveHandler.addQuoteToken        ",  IBaseHandler(_handler).numberOfCalls("UBBasicHandler.addQuoteToken"));
        console.log("BReserveHandler.removeQuoteToken      ",  IBaseHandler(_handler).numberOfCalls("BBasicHandler.removeQuoteToken"));
        console.log("UBReserveHandler.removeQuoteToken     ",  IBaseHandler(_handler).numberOfCalls("UBBasicHandler.removeQuoteToken"));
        console.log("BReserveHandler.addCollateral         ",  IBaseHandler(_handler).numberOfCalls("BBasicHandler.addCollateral"));
        console.log("UBReserveHandler.addCollateral        ",  IBaseHandler(_handler).numberOfCalls("UBBasicHandler.addCollateral"));
        console.log("BReserveHandler.removeCollateral      ",  IBaseHandler(_handler).numberOfCalls("BBasicHandler.removeCollateral"));
        console.log("UBReserveHandler.removeCollateral     ",  IBaseHandler(_handler).numberOfCalls("UBBasicHandler.removeCollateral"));
        console.log("BReserveHandler.moveQuoteToken        ",  IBaseHandler(_handler).numberOfCalls("BBasicHandler.moveQuoteToken"));
        console.log("UBReserveHandler.moveQuoteToken       ",  IBaseHandler(_handler).numberOfCalls("UBBasicHandler.moveQuoteToken"));
        console.log("BReserveHandler.transferLps           ",  IBaseHandler(_handler).numberOfCalls("BBasicHandler.transferLps"));
        console.log("UBReserveHandler.transferLps          ",  IBaseHandler(_handler).numberOfCalls("UBBasicHandler.transferLps"));
        console.log("--Borrower--------");
        console.log("BReserveHandler.drawDebt              ",  IBaseHandler(_handler).numberOfCalls("BBasicHandler.drawDebt"));
        console.log("UBReserveHandler.drawDebt             ",  IBaseHandler(_handler).numberOfCalls("UBBasicHandler.drawDebt"));
        console.log("BReserveHandler.repayDebt             ",  IBaseHandler(_handler).numberOfCalls("BBasicHandler.repayDebt"));
        console.log("UBReserveHandler.repayDebt            ",  IBaseHandler(_handler).numberOfCalls("UBBasicHandler.repayDebt"));
        console.log("BReserveHandler.pledgeCollateral      ",  IBaseHandler(_handler).numberOfCalls("BBasicHandler.pledgeCollateral"));
        console.log("UBReserveHandler.pledgeCollateral     ",  IBaseHandler(_handler).numberOfCalls("UBBasicHandler.pledgeCollateral"));
        console.log("BReserveHandler.pullCollateral        ",  IBaseHandler(_handler).numberOfCalls("BBasicHandler.pullCollateral"));
        console.log("UBReserveHandler.pullCollateral       ",  IBaseHandler(_handler).numberOfCalls("UBBasicHandler.pullCollateral"));
        console.log("--Kicker/Taker----");
        console.log("BReserveHandler.kickAuction           ",  IBaseHandler(_handler).numberOfCalls("BLiquidationHandler.kickAuction"));
        console.log("UBReserveHandler.kickAuction          ",  IBaseHandler(_handler).numberOfCalls("UBLiquidationHandler.kickAuction"));
        console.log("BReserveHandler.takeAuction           ",  IBaseHandler(_handler).numberOfCalls("BLiquidationHandler.takeAuction"));
        console.log("UBReserveHandler.takeAuction          ",  IBaseHandler(_handler).numberOfCalls("UBLiquidationHandler.takeAuction"));
        console.log("BReserveHandler.bucketTake            ",  IBaseHandler(_handler).numberOfCalls("BLiquidationHandler.bucketTake"));
        console.log("UBReserveHandler.bucketTake           ",  IBaseHandler(_handler).numberOfCalls("UBLiquidationHandler.bucketTake"));
        console.log("BReserveHandler.settleAuction         ",  IBaseHandler(_handler).numberOfCalls("BLiquidationHandler.settleAuction"));
        console.log("UBReserveHandler.settleAuction        ",  IBaseHandler(_handler).numberOfCalls("UBLiquidationHandler.settleAuction"));
        console.log("BReserveHandler.withdrawBonds         ",  IBaseHandler(_handler).numberOfCalls("BLiquidationHandler.withdrawBonds"));
        console.log("UBReserveHandler.withdrawBonds        ",  IBaseHandler(_handler).numberOfCalls("UBLiquidationHandler.withdrawBonds"));
        console.log("BReserveHandler.kickWithDeposit       ",  IBaseHandler(_handler).numberOfCalls("BLiquidationHandler.kickWithDeposit"));
        console.log("UBReserveHandler.kickWithDeposit      ",  IBaseHandler(_handler).numberOfCalls("UBLiquidationHandler.kickWithDeposit"));
        console.log("BReserveHandler.kickReserveAuction    ",  IBaseHandler(_handler).numberOfCalls("BReserveHandler.kickReserveAuction"));
        console.log("UBReserveHandler.kickReserveAuction   ",  IBaseHandler(_handler).numberOfCalls("UBReserveHandler.kickReserveAuction"));
        console.log("BReserveHandler.takeReserves          ",  IBaseHandler(_handler).numberOfCalls("BReserveHandler.takeReserves"));
        console.log("UBReserveHandler.takeReserves         ",  IBaseHandler(_handler).numberOfCalls("UBReserveHandler.takeReserves"));
        console.log("------------------");
        console.log(
            "Sum",
            IBaseHandler(_handler).numberOfCalls("BBasicHandler.addQuoteToken") +
            IBaseHandler(_handler).numberOfCalls("BBasicHandler.removeQuoteToken") +
            IBaseHandler(_handler).numberOfCalls("BBasicHandler.moveQuoteToken") + 
            IBaseHandler(_handler).numberOfCalls("BBasicHandler.addCollateral") +
            IBaseHandler(_handler).numberOfCalls("BBasicHandler.removeCollateral") +
            IBaseHandler(_handler).numberOfCalls("BBasicHandler.pledgeCollateral") + 
            IBaseHandler(_handler).numberOfCalls("BBasicHandler.pullCollateral") + 
            IBaseHandler(_handler).numberOfCalls("BBasicHandler.drawDebt") + 
            IBaseHandler(_handler).numberOfCalls("BBasicHandler.repayDebt") + 
            IBaseHandler(_handler).numberOfCalls("BBasicHandler.transferLps") +
            IBaseHandler(_handler).numberOfCalls("BLiquidationHandler.kickAuction") +
            IBaseHandler(_handler).numberOfCalls("BLiquidationHandler.takeAuction") +
            IBaseHandler(_handler).numberOfCalls("BLiquidationHandler.bucketTake") +
            IBaseHandler(_handler).numberOfCalls("BLiquidationHandler.settleAuction") +
            IBaseHandler(_handler).numberOfCalls("BLiquidationHandler.withdrawBonds") +
            IBaseHandler(_handler).numberOfCalls("BLiquidationHandler.kickWithDeposit") +
            IBaseHandler(_handler).numberOfCalls("BReserveHandler.kickReserveAuction") +
            IBaseHandler(_handler).numberOfCalls("BReserveHandler.takeReserves")
        );
        console.log("------------------");
        console.log("--Successful liquidation actions----");
        console.log("kick:              ",  IBaseHandler(_handler).numberOfActions("kick"));
        console.log("kick with deposit: ",  IBaseHandler(_handler).numberOfActions("kickWithDeposit"));
        console.log("take:              ",  IBaseHandler(_handler).numberOfActions("take"));
        console.log("bucket take:       ",  IBaseHandler(_handler).numberOfActions("bucketTake"));
        console.log("settle             ",  IBaseHandler(_handler).numberOfActions("settle"));
        uint256 currentEpoch = _pool.currentBurnEpoch();
        console.log("Current epoch", currentEpoch);
        for (uint256 epoch = 0; epoch <= currentEpoch; epoch++) {
            (, , uint256 burned) = _pool.burnInfo(epoch);
            if (burned != 0) {
                console.log("Epoch: %s; Burned: %s", epoch, burned);
            }
        }
    }
}