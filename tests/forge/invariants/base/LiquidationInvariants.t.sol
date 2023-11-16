// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.18;

import "@std/console.sol";
import '../../utils/DSTestPlus.sol';

import { IBaseHandler }           from '../interfaces/IBaseHandler.sol';
import { BasicInvariants }        from './BasicInvariants.t.sol';

abstract contract LiquidationInvariants is BasicInvariants {

    /*************************************/
    /*** Common Liquidation Invariants ***/
    /*************************************/

    function invariant_auction() public useCurrentTimestamp {
        _invariant_A1();
        _invariant_A2();
        _invariant_A3_A4();
        _invariant_A5();
        _invariant_A7();
        _invariant_A8();
    }

    /// @dev checks sum of all borrower's t0debt is equals to total pool t0debtInAuction
    function _invariant_A1() internal view {
        uint256 actorCount = IBaseHandler(_handler).getActorsCount();
        uint256 totalT0debtInAuction;

        for (uint256 i = 0; i < actorCount; i++) {
            address borrower = IBaseHandler(_handler).actors(i);
            (, , , uint256 kickTime, , , , ,) = _pool.auctionInfo(borrower);

            if (kickTime != 0) {
                (uint256 t0debt, , ) = _pool.borrowerInfo(borrower);
                totalT0debtInAuction += t0debt;
            }
        }

        require(_pool.totalT0DebtInAuction() == totalT0debtInAuction, "Auction Invariant A1");
    }

    /// @dev checks sum of all kicker bond is equal to total pool bond
    function _invariant_A2() internal view {
        uint256 actorCount = IBaseHandler(_handler).getActorsCount();
        uint256 kickerClaimableBond;
        uint256 kickerLockedBond;

        for (uint256 i = 0; i < actorCount; i++) {
            address kicker = IBaseHandler(_handler).actors(i);
            (uint256 claimable, uint256 locked) = _pool.kickerInfo(kicker);

            kickerLockedBond    += locked;
            kickerClaimableBond += claimable;
        }

        (uint256 totalBondEscrowed, , , ) = _pool.reservesInfo();

        require(totalBondEscrowed == kickerClaimableBond + kickerLockedBond, "A2: total bond escrowed != kicker bonds");

        uint256 lockedBonds;
        for (uint256 i = 0; i < actorCount; i++) {
            address borrower = IBaseHandler(_handler).actors(i);
            (, , uint256 bond, , , , , , ) = _pool.auctionInfo(borrower);
            lockedBonds += bond;
        }
        require(lockedBonds == kickerLockedBond, "A2: bonds in auctions != than kicker locked bonds");
    }

    /// @dev checks total borrowers with debt is equals to sum of borrowers unkicked and borrowers kicked
    /// @dev checks total auctions is equals to total borrowers kicked
    function _invariant_A3_A4() internal view {
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

            (, , , uint256 kickTime, , , , , ) = _pool.auctionInfo(borrower);

            if (kickTime != 0) borrowersKicked += 1;
        }

        require(totalAuction == borrowersKicked, "Auction Invariant A4");
    }

    /// @dev for each auction, kicker locked bond is more than equal to auction bond
    function _invariant_A5() internal view {
        uint256 actorCount = IBaseHandler(_handler).getActorsCount();

        for (uint256 i = 0; i < actorCount; i++) {
            address borrower = IBaseHandler(_handler).actors(i);
            (address kicker, , uint256 bondSize, , , , , , ) = _pool.auctionInfo(borrower);
            (, uint256 lockedAmount) = _pool.kickerInfo(kicker);

            require(lockedAmount >= bondSize, "Auction Invariant A5");
        }
    }

    /// @dev total bond escrowed should increase when auctioned kicked with the difference needed to cover the bond and should decrease only when kicker bonds withdrawned
    function _invariant_A7() internal view {
        uint256 previousTotalBondEscrowed        = IBaseHandler(_handler).previousTotalBonds();
        uint256 increaseInBonds                  = IBaseHandler(_handler).increaseInBonds();
        uint256 decreaseInBonds                  = IBaseHandler(_handler).decreaseInBonds();
        (uint256 currentTotalBondEscrowed, , , ) = _pool.reservesInfo();

        requireWithinDiff(
            currentTotalBondEscrowed,
            previousTotalBondEscrowed + increaseInBonds - decreaseInBonds,
            _pool.quoteTokenScale(),
            "Auction Invariant A7"
        );
    }

    /// @dev kicker reward should be less than or equals to kicker penalty on take.
    function _invariant_A8() internal view {
        uint256 borrowerPenalty = IBaseHandler(_handler).borrowerPenalty();
        uint256 kickerReward    = IBaseHandler(_handler).kickerReward();

        console.log("Borrower Penalty -->", borrowerPenalty);
        console.log("Kicker Reward    -->", kickerReward);

        require(kickerReward <= borrowerPenalty, "Auction Invariant A8");
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
        console.log("BLiquidationHandler.moveQuoteToken        ",  IBaseHandler(_handler).numberOfCalls("BBasicHandler.moveQuoteToken"));
        console.log("UBLiquidationHandler.moveQuoteToken       ",  IBaseHandler(_handler).numberOfCalls("UBBasicHandler.moveQuoteToken"));
        console.log("BLiquidationHandler.transferLps           ",  IBaseHandler(_handler).numberOfCalls("BBasicHandler.transferLps"));
        console.log("UBLiquidationHandler.transferLps          ",  IBaseHandler(_handler).numberOfCalls("UBBasicHandler.transferLps"));
        console.log("--Borrower--------");
        console.log("BLiquidationHandler.drawDebt              ",  IBaseHandler(_handler).numberOfCalls("BBasicHandler.drawDebt"));
        console.log("UBLiquidationHandler.drawDebt             ",  IBaseHandler(_handler).numberOfCalls("UBBasicHandler.drawDebt"));
        console.log("BLiquidationHandler.repayDebt             ",  IBaseHandler(_handler).numberOfCalls("BBasicHandler.repayDebt"));
        console.log("UBLiquidationHandler.repayDebt            ",  IBaseHandler(_handler).numberOfCalls("UBBasicHandler.repayDebt"));
        console.log("BLiquidationHandler.pledgeCollateral      ",  IBaseHandler(_handler).numberOfCalls("BBasicHandler.pledgeCollateral"));
        console.log("UBLiquidationHandler.pledgeCollateral     ",  IBaseHandler(_handler).numberOfCalls("UBBasicHandler.pledgeCollateral"));
        console.log("BLiquidationHandler.pullCollateral        ",  IBaseHandler(_handler).numberOfCalls("BBasicHandler.pullCollateral"));
        console.log("UBLiquidationHandler.pullCollateral       ",  IBaseHandler(_handler).numberOfCalls("UBBasicHandler.pullCollateral"));
        console.log("BLiquidationHandler.stampLoan             ",  IBaseHandler(_handler).numberOfCalls("BBasicHandler.stampLoan"));
        console.log("UBLiquidationHandler.stampLoan            ",  IBaseHandler(_handler).numberOfCalls("UBBasicHandler.stampLoan"));
        console.log("--Kicker/Taker----");
        console.log("BLiquidationHandler.kickAuction           ",  IBaseHandler(_handler).numberOfCalls("BLiquidationHandler.kickAuction"));
        console.log("UBLiquidationHandler.kickAuction          ",  IBaseHandler(_handler).numberOfCalls("UBLiquidationHandler.kickAuction"));
        console.log("BLiquidationHandler.takeAuction           ",  IBaseHandler(_handler).numberOfCalls("BLiquidationHandler.takeAuction"));
        console.log("UBLiquidationHandler.takeAuction          ",  IBaseHandler(_handler).numberOfCalls("UBLiquidationHandler.takeAuction"));
        console.log("BLiquidationHandler.bucketTake            ",  IBaseHandler(_handler).numberOfCalls("BLiquidationHandler.bucketTake"));
        console.log("UBLiquidationHandler.bucketTake           ",  IBaseHandler(_handler).numberOfCalls("UBLiquidationHandler.bucketTake"));
        console.log("BLiquidationHandler.settleAuction         ",  IBaseHandler(_handler).numberOfCalls("BLiquidationHandler.settleAuction"));
        console.log("UBLiquidationHandler.settleAuction        ",  IBaseHandler(_handler).numberOfCalls("UBLiquidationHandler.settleAuction"));
        console.log("BLiquidationHandler.withdrawBonds         ",  IBaseHandler(_handler).numberOfCalls("BLiquidationHandler.withdrawBonds"));
        console.log("UBLiquidationHandler.withdrawBonds        ",  IBaseHandler(_handler).numberOfCalls("UBLiquidationHandler.withdrawBonds"));
        console.log("BLiquidationHandler.lenderKickAuction     ",  IBaseHandler(_handler).numberOfCalls("BLiquidationHandler.lenderKickAuction"));
        console.log("UBLiquidationHandler.lenderKickAuction    ",  IBaseHandler(_handler).numberOfCalls("UBLiquidationHandler.lenderKickAuction"));
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
            IBaseHandler(_handler).numberOfCalls("BBasicHandler.stampLoan") +
            IBaseHandler(_handler).numberOfCalls("BBasicHandler.transferLps") +
            IBaseHandler(_handler).numberOfCalls("BLiquidationHandler.kickAuction") +
            IBaseHandler(_handler).numberOfCalls("BLiquidationHandler.takeAuction") +
            IBaseHandler(_handler).numberOfCalls("BLiquidationHandler.bucketTake") +
            IBaseHandler(_handler).numberOfCalls("BLiquidationHandler.settleAuction") +
            IBaseHandler(_handler).numberOfCalls("BLiquidationHandler.withdrawBonds") +
            IBaseHandler(_handler).numberOfCalls("BLiquidationHandler.lenderKickAuction")
        );
        console.log("------------------");
        console.log("--Successful liquidation actions----");
        console.log("kick:              ",  IBaseHandler(_handler).numberOfActions("kick"));
        console.log("kick with deposit: ",  IBaseHandler(_handler).numberOfActions("lenderKickAuction"));
        console.log("take:              ",  IBaseHandler(_handler).numberOfActions("take"));
        console.log("bucket take:       ",  IBaseHandler(_handler).numberOfActions("bucketTake"));
        console.log("settle             ",  IBaseHandler(_handler).numberOfActions("settle"));
    }
}