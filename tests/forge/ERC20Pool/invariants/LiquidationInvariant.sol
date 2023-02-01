// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.14;

import '@std/Test.sol';
import "forge-std/console.sol";

import { TestBase } from './TestBase.sol';

import { LENDER_MIN_BUCKET_INDEX, LENDER_MAX_BUCKET_INDEX, BORROWER_MIN_BUCKET_INDEX } from './handlers/BasicPoolHandler.sol';
import { LiquidationPoolHandler } from './handlers/LiquidationPoolHandler.sol';
import { BasicInvariants } from './BasicInvariants.t.sol';
import { IBaseHandler } from './handlers/IBaseHandler.sol';

contract LiquidationInvariant is BasicInvariants {

    /**************************************************************************************************************************************/
    /*** Invariant Tests                                                                                                                ***/
    /***************************************************************************************************************************************
     * Auction
        *  A2: totalBondEscrowed = sum of all kicker's bond = total Bond in Auction
    ****************************************************************************************************************************************/
    
    LiquidationPoolHandler internal _liquidationPoolHandler;

    function setUp() public override virtual{

        super.setUp();

        excludeContract(address(_basicPoolHandler));

        _liquidationPoolHandler = new LiquidationPoolHandler(address(_pool), address(_quote), address(_collateral), address(_poolInfo), NUM_ACTORS);
        _handler = address(_liquidationPoolHandler);
    }

    // checks sum of all kicker bond is equal to total pool bond
    function invariant_bond_A2() public {
        uint256 actorCount = IBaseHandler(_handler).getActorsCount();
        uint256 totalKickerBond;
        for(uint256 i = 0; i < actorCount; i++) {
            address kicker = IBaseHandler(_handler)._actors(i);
            (, uint256 bond) = _pool.kickerInfo(kicker);
            totalKickerBond += bond;
        }

        uint256 totalBondInAuction;

        for(uint256 i = 0; i < actorCount; i++) {
            address borrower = IBaseHandler(_handler)._actors(i);
            (, , uint256 bondSize, , , , , , ) = _pool.auctionInfo(borrower);
            totalBondInAuction += bondSize;
        }

        require(totalBondInAuction == totalKickerBond, "Incorrect bond");

        (uint256 totalPoolBond, , ) = _pool.reservesInfo();

        require(totalPoolBond == totalKickerBond, "Incorrect bond");
    }

    function invariant_call_summary() external view virtual override{
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
        console.log("UBLiquidationHandler.kickAuction           ",  IBaseHandler(_handler).numberOfCalls("UBLiquidationHandler.kickAuction"));
        console.log("BLiquidationHandler.takeAuction           ",  IBaseHandler(_handler).numberOfCalls("BLiquidationHandler.takeAuction"));
        console.log("UBLiquidationHandler.takeAuction           ",  IBaseHandler(_handler).numberOfCalls("UBLiquidationHandler.takeAuction"));
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