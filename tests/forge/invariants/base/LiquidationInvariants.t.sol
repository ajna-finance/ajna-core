// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.14;

import "@std/console.sol";

import { IBaseHandler }           from '../interfaces/IBaseHandler.sol';
import { BasicInvariants }        from './BasicInvariants.t.sol';

abstract contract LiquidationInvariants is BasicInvariants {

    // checks sum of all borrower's t0debt is equals to total pool t0debtInAuction
    function invariant_debtInAuction_A1() public useCurrentTimestamp {
        uint256 actorCount = IBaseHandler(_handler).getActorsCount();
        uint256 totalT0debtInAuction;

        for (uint256 i = 0; i < actorCount; i++) {
            address borrower = IBaseHandler(_handler).actors(i);
            (, , , uint256 kickTime, , , , , , ) = _pool.auctionInfo(borrower);

            if (kickTime != 0) {
                (uint256 t0debt, , ) = _pool.borrowerInfo(borrower);
                totalT0debtInAuction += t0debt;
            }
        }

        require(_pool.totalT0DebtInAuction() == totalT0debtInAuction, "Auction Invariant A1");
    }

    // checks sum of all kicker bond is equal to total pool bond
    function invariant_bond_A2() public useCurrentTimestamp {
        uint256 actorCount = IBaseHandler(_handler).getActorsCount();
        uint256 totalKickerBond;

        for (uint256 i = 0; i < actorCount; i++) {
            address kicker = IBaseHandler(_handler).actors(i);
            (uint256 claimable, uint256 bond) = _pool.kickerInfo(kicker);

            totalKickerBond += bond + claimable;
        }

        (uint256 totalPoolBond, , , ) = _pool.reservesInfo();

        require(totalPoolBond == totalKickerBond, "Auction Invariant A2");
    }

    // checks total borrowers with debt is equals to sum of borrowers unkicked and borrowers kicked
    // checks total auctions is equals to total borrowers kicked 
    function invariant_auctions_A3_A4() public useCurrentTimestamp {
        uint256 actorCount = IBaseHandler(_handler).getActorsCount();
        uint256 totalBorrowersWithDebt;

        for (uint256 i = 0; i < actorCount; i++) {
            address borrower = IBaseHandler(_handler).actors(i);
            (uint256 t0Debt, , ) = _pool.borrowerInfo(borrower);

            if (t0Debt > 0) totalBorrowersWithDebt += 1;
        }

        ( , , uint256 loansCount) = _pool.loansInfo();
        uint256 totalAuction = _pool.totalAuctionsInPool();

        require(
            totalBorrowersWithDebt == loansCount + totalAuction,
            "Auction Invariant A3"
        );

        uint256 borrowersKicked;

        for (uint256 i = 0; i < actorCount; i++) {
            address borrower = IBaseHandler(_handler).actors(i);

            (, , , uint256 kickTime, , , , , , ) = _pool.auctionInfo(borrower);

            if (kickTime != 0) borrowersKicked += 1;
        }

        require(totalAuction == borrowersKicked, "Auction Invariant A4");
    }

    // for each auction, kicker locked bond is more than equal to auction bond 
    function invariant_borrowers_A5() public useCurrentTimestamp {
        uint256 actorCount = IBaseHandler(_handler).getActorsCount();

        for (uint256 i = 0; i < actorCount; i++) {
            address borrower = IBaseHandler(_handler).actors(i);
            (address kicker, , uint256 bondSize, , , , , , , ) = _pool.auctionInfo(borrower);
            (, uint256 lockedAmount) = _pool.kickerInfo(kicker);

            require(lockedAmount >= bondSize, "Auction Invariant A5");
        }
    }

    // if a Liquidation is not taken then the take flag (Liquidation.alreadyTaken) should be False, if already taken then the take flag should be True
    function invariant_auction_taken_A6() public useCurrentTimestamp {
        uint256 actorCount = IBaseHandler(_handler).getActorsCount();

        for (uint256 i = 0; i < actorCount; i++) {
            address borrower = IBaseHandler(_handler).actors(i);
            (, , , , , , , , , bool alreadyTaken) = _pool.auctionInfo(borrower);

            require(
                alreadyTaken == IBaseHandler(_handler).alreadyTaken(borrower),
                "Auction Invariant A6"
            );
        }
    }
    
    function invariant_call_summary() public virtual override useCurrentTimestamp {
        console.log("\nCall Summary\n");
        console.log("--Lender----------");
        console.log("BLiquidationHandler.addQuoteToken         ",  IBaseHandler(_handler).numberOfCalls("BBasicHandler.addQuoteToken"));
        console.log("UBLiquidationHandler.addQuoteToken        ",  IBaseHandler(_handler).numberOfCalls("UBBasicHandler.addQuoteToken"));
        console.log("BLiquidationHandler.removeQuoteToken      ",  IBaseHandler(_handler).numberOfCalls("BBasicHandler.removeQuoteToken"));
        console.log("UBLiquidationHandler.removeQuoteToken     ",  IBaseHandler(_handler).numberOfCalls("UBBasicHandler.removeQuoteToken"));
        console.log("BLiquidationHandler.addCollateral         ",  IBaseHandler(_handler).numberOfCalls("BBasicHandler.addCollateral"));
        console.log("UBLiquidationHandler.addCollateral        ",  IBaseHandler(_handler).numberOfCalls("UBBasicHandler.addCollateral"));
        console.log("BLiquidationHandler.removeCollateral      ",  IBaseHandler(_handler).numberOfCalls("BBasicHandler.removeCollateral"));
        console.log("UBLiquidationHandler.removeCollateral     ",  IBaseHandler(_handler).numberOfCalls("UBBasicHandler.removeCollateral"));
        console.log("--Borrower--------");
        console.log("BLiquidationHandler.drawDebt              ",  IBaseHandler(_handler).numberOfCalls("BBasicHandler.drawDebt"));
        console.log("UBLiquidationHandler.drawDebt             ",  IBaseHandler(_handler).numberOfCalls("UBBasicHandler.drawDebt"));
        console.log("BLiquidationHandler.repayDebt             ",  IBaseHandler(_handler).numberOfCalls("BBasicHandler.repayDebt"));
        console.log("UBLiquidationHandler.repayDebt            ",  IBaseHandler(_handler).numberOfCalls("UBBasicHandler.repayDebt"));
        console.log("BLiquidationHandler.kickAuction           ",  IBaseHandler(_handler).numberOfCalls("BLiquidationHandler.kickAuction"));
        console.log("UBLiquidationHandler.kickAuction          ",  IBaseHandler(_handler).numberOfCalls("UBLiquidationHandler.kickAuction"));
        console.log("BLiquidationHandler.takeAuction           ",  IBaseHandler(_handler).numberOfCalls("BLiquidationHandler.takeAuction"));
        console.log("UBLiquidationHandler.takeAuction          ",  IBaseHandler(_handler).numberOfCalls("UBLiquidationHandler.takeAuction"));
        console.log("------------------");
        console.log(
            "Sum",
            IBaseHandler(_handler).numberOfCalls("BBasicHandler.addQuoteToken") +
            IBaseHandler(_handler).numberOfCalls("BBasicHandler.removeQuoteToken") +
            IBaseHandler(_handler).numberOfCalls("BBasicHandler.addCollateral") +
            IBaseHandler(_handler).numberOfCalls("BBasicHandler.removeCollateral") +
            IBaseHandler(_handler).numberOfCalls("BBasicHandler.drawDebt") + 
            IBaseHandler(_handler).numberOfCalls("BBasicHandler.repayDebt") +
            IBaseHandler(_handler).numberOfCalls("BLiquidationHandler.kickAuction") +
            IBaseHandler(_handler).numberOfCalls("BLiquidationHandler.takeAuction")
        );
    }

}