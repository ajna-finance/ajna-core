// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.14;

import { Strings } from '@openzeppelin/contracts/utils/Strings.sol';

import '@std/Test.sol';
import "@std/console.sol";

import { TestBase } from './TestBase.sol';

import {
    LENDER_MIN_BUCKET_INDEX,
    LENDER_MAX_BUCKET_INDEX,
    BORROWER_MIN_BUCKET_INDEX
} from './handlers/BasicPoolHandler.sol';

import { ReservePoolHandler }   from './handlers/ReservePoolHandler.sol';
import { LiquidationInvariant } from './LiquidationInvariant.t.sol';
import { IBaseHandler }         from './interfaces/IBaseHandler.sol';

contract ReserveInvariants is LiquidationInvariant {

    /**************************************************************************************************************************************/
    /*** Invariant Tests                                                                                                                ***/
    /***************************************************************************************************************************************
     * Reserves
        * RE1 : Reserves are unchanged by pledging collateral
        * RE2 : Reserves are unchanged by removing collateral
        * RE3 : Reserves are unchanged by depositing quote token into a bucket
        * RE4 : Reserves are unchanged by withdrawing deposit (quote token) from a bucket after the penalty period hes expired
        * RE5 : Reserves are unchanged by adding collateral token into a bucket
        * RE6 : Reserves are unchanged by removing collateral token from a bucket
        * RE7 : Reserves increase by 7% of the loan quantity upon the first take (including depositTake or arbTake) and increase/decrease by bond penalty/reward on take.
        * RE8 : Reserves are unchanged under takes/depositTakes/arbTakes after the first take but increase/decrease by bond penalty/reward on take.
        * RE9 : Reserves increase by 3 months of interest when a loan is kicked
        * RE10: Reserves increase by origination fee: max(1 week interest, 0.05% of borrow amount), on draw debt
    ****************************************************************************************************************************************/
    
    ReservePoolHandler internal _reservePoolHandler;

    function setUp() public override virtual {

        super.setUp();

        excludeContract(address(_liquidationPoolHandler));

        _reservePoolHandler = new ReservePoolHandler(
            address(_pool),
            address(_quote),
            address(_collateral),
            address(_poolInfo),
            NUM_ACTORS,
            address(this)
        );

        _handler = address(_reservePoolHandler);
    }

    function invariant_reserves_RE1_RE2_RE3_RE4_RE5_RE6_RE7_RE8_RE9_RE10() public useCurrentTimestamp {

        uint256 previousReserves = IBaseHandler(_handler).previousReserves();
        uint256 currentReserves  = IBaseHandler(_handler).currentReserves();

        console.log("Current Reserves  -->", currentReserves);
        console.log("Previous Reserves -->", previousReserves);

        // reserves should not change with a action
        if (!IBaseHandler(_handler).shouldReserveChange() && currentReserves != 0) {
            requireWithinDiff(
                currentReserves,
                previousReserves,
                1e17,
                string(abi.encodePacked(Strings.toString(previousReserves),"| -> |", Strings.toString(currentReserves)))
            );
        }
        // reserves should change
        else {
            uint256 loanKickIncreaseInReserve = IBaseHandler(_handler).loanKickIncreaseInReserve();

            console.log("loanKickIncreaseInReserve -->", loanKickIncreaseInReserve);
            
            // reserves should increase by 0.25% of borrower debt on loan kick
            if (loanKickIncreaseInReserve != 0) {
                requireWithinDiff(
                    currentReserves,
                    previousReserves + loanKickIncreaseInReserve,
                    1e17,
                    "Incorrect Reserves change with kick"
                );
            }

            uint256 drawDebtIncreaseInReserve = IBaseHandler(_handler).drawDebtIncreaseInReserve();

            console.log("Draw debt increase in reserve --->", drawDebtIncreaseInReserve);

            // reserves should increase by origination fees on draw debt
            if (drawDebtIncreaseInReserve != 0) {
                requireWithinDiff(
                    currentReserves,
                    previousReserves + drawDebtIncreaseInReserve,
                    1e17,
                    "Incorrect reserve change on draw debt"
                );
            }

            uint256 firstTakeIncreaseInReserve = IBaseHandler(_handler).firstTakeIncreaseInReserve();
            bool isKickerRewarded              = IBaseHandler(_handler).isKickerRewarded();
            uint256 kickerBondChange           = IBaseHandler(_handler).kickerBondChange();

            console.log("Kicker Rewarded    -->", isKickerRewarded);
            console.log("Kicker Bond change -->", kickerBondChange);
            console.log("firstTakeIncreaseInReserve -->", firstTakeIncreaseInReserve);

            uint256 previousReservesAndBondChange = !isKickerRewarded ? previousReserves + kickerBondChange : previousReserves;
            
            // reserves should increase by 7% of borrower debt on first take
            if (IBaseHandler(_handler).firstTake()) {
                requireWithinDiff(
                    currentReserves,
                    previousReservesAndBondChange + firstTakeIncreaseInReserve,
                    1e17,
                    "Incorrect Reserves change with first take"
                );
            } else if(currentReserves != 0 && loanKickIncreaseInReserve == 0 && drawDebtIncreaseInReserve == 0) {
                requireWithinDiff(
                    currentReserves,
                    previousReservesAndBondChange,
                    1e17,
                    "Incorrect Reserves change with not first take"
                );
            }
        }
    }
}