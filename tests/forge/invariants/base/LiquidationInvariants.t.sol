// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.14;

import "@std/console.sol";

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
        _invariant_A6();
    }

    /// @dev checks sum of all borrower's t0debt is equals to total pool t0debtInAuction
    function _invariant_A1() internal view {
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

    /// @dev checks sum of all kicker bond is equal to total pool bond
    function _invariant_A2() internal view {
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

            (, , , uint256 kickTime, , , , , , ) = _pool.auctionInfo(borrower);

            if (kickTime != 0) borrowersKicked += 1;
        }

        require(totalAuction == borrowersKicked, "Auction Invariant A4");
    }

    /// @dev for each auction, kicker locked bond is more than equal to auction bond
    function _invariant_A5() internal view {
        uint256 actorCount = IBaseHandler(_handler).getActorsCount();

        for (uint256 i = 0; i < actorCount; i++) {
            address borrower = IBaseHandler(_handler).actors(i);
            (address kicker, , uint256 bondSize, , , , , , , ) = _pool.auctionInfo(borrower);
            (, uint256 lockedAmount) = _pool.kickerInfo(kicker);

            require(lockedAmount >= bondSize, "Auction Invariant A5");
        }
    }

    /// @dev if a Liquidation is not taken then the take flag (Liquidation.alreadyTaken) should be False, if already taken then the take flag should be True
    function _invariant_A6() internal view {
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
        console.log("--Liquidation--------");
        console.log("BLiqHandler.kickAuction             ",  IBaseHandler(_handler).numberOfCalls("BLiqHandler.kickAuction"));
        console.log("UBLiqHandler.kickAuction            ",  IBaseHandler(_handler).numberOfCalls("UBLiqHandler.kickAuction"));
        console.log("BLiqHandler.kickWithDeposit         ",  IBaseHandler(_handler).numberOfCalls("BLiqHandler.kickWithDeposit"));
        console.log("UBLiqHandler.kickWithDeposit        ",  IBaseHandler(_handler).numberOfCalls("UBLiqHandler.kickWithDeposit"));
        console.log("BLiqHandler.takeAuction             ",  IBaseHandler(_handler).numberOfCalls("BLiqHandler.takeAuction"));
        console.log("UBLiqHandler.takeAuction            ",  IBaseHandler(_handler).numberOfCalls("UBLiqHandler.takeAuction"));
        console.log("BLiqHandler.bucketTake              ",  IBaseHandler(_handler).numberOfCalls("BLiqHandler.bucketTake"));
        console.log("UBLiqHandler.bucketTake             ",  IBaseHandler(_handler).numberOfCalls("UBLiqHandler.bucketTake"));
        console.log("BLiqHandler.withdrawBonds           ",  IBaseHandler(_handler).numberOfCalls("BLiqHandler.withdrawBonds"));
        console.log("UBLiqHandler.withdrawBonds          ",  IBaseHandler(_handler).numberOfCalls("UBLiqHandler.withdrawBonds"));
        console.log("BLiqHandler.settleAuction           ",  IBaseHandler(_handler).numberOfCalls("BLiqHandler.settleAuction"));
        console.log("UBLiqHandler.settleAuction          ",  IBaseHandler(_handler).numberOfCalls("UBLiqHandler.settleAuction"));
        console.log(
            "Sum",
            IBaseHandler(_handler).numberOfCalls("BLiqHandler.kickAuction") +
            IBaseHandler(_handler).numberOfCalls("BLiqHandler.kickWithDeposit") +
            IBaseHandler(_handler).numberOfCalls("BLiqHandler.takeAuction") +
            IBaseHandler(_handler).numberOfCalls("BLiqHandler.bucketTake") +
            IBaseHandler(_handler).numberOfCalls("BLiqHandler.withdrawBonds") +
            IBaseHandler(_handler).numberOfCalls("BLiqHandler.settleAuction")
        );
    }
}