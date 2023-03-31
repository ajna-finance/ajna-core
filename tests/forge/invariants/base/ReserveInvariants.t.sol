// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.14;

import "@std/console.sol";

import { IBaseHandler }          from '../interfaces/IBaseHandler.sol';
import { LiquidationInvariants } from './LiquidationInvariants.t.sol';

abstract contract ReserveInvariants is LiquidationInvariants {

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
        * RE11: Reserves decrease by claimableReserves by startClaimableReserveAuction
        * RE12: Reserves decrease by amount of reserve used to settle a auction
    ****************************************************************************************************************************************/

    function invariant_reserves_RE1_RE2_RE3_RE4_RE5_RE6_RE7_RE8_RE9_RE10_RE11_RE12() public useCurrentTimestamp {

        uint256 previousReserves = IBaseHandler(_handler).previousReserves();
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
            1e15,
            "Incorrect Reserves change"
        );
    }
}