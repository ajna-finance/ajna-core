// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.14;

import '@std/Test.sol';
import "@std/console.sol";
import { Strings } from '@openzeppelin/contracts/utils/Strings.sol';

import { TestBase } from './TestBase.sol';

import { LENDER_MIN_BUCKET_INDEX, LENDER_MAX_BUCKET_INDEX, BORROWER_MIN_BUCKET_INDEX } from './handlers/BasicPoolHandler.sol';

import { ReservePoolHandler }   from './handlers/ReservePoolHandler.sol';
import { LiquidationInvariant } from './LiquidationInvariant.t.sol';
import { IBaseHandler }         from './handlers/IBaseHandler.sol';

contract ReserveInvariants is LiquidationInvariant {
    
    ReservePoolHandler internal _reservePoolHandler;

    function setUp() public override virtual {

        super.setUp();

        excludeContract(address(_liquidationPoolHandler));

        _reservePoolHandler = new ReservePoolHandler(address(_pool), address(_quote), address(_collateral), address(_poolInfo), NUM_ACTORS);
        _handler = address(_reservePoolHandler);
    }

    function invariant_reserves_RE1_RE2_RE3_RE4_RE5_RE6_RE7_RE8_RE9_RE10() public {

        uint256 previousReserves = IBaseHandler(_handler).previousReserves();
        uint256 currentReserves  = IBaseHandler(_handler).currentReserves();
        console.log("Current Reserves -->", currentReserves);
        console.log("Previous Reserves -->", previousReserves);

        // reserves should not change with a action
        if(!IBaseHandler(_handler).shouldReserveChange() && currentReserves != 0) {
            requireWithinDiff(currentReserves, previousReserves, 1e12, string(abi.encodePacked(Strings.toString(previousReserves),"| -> |", Strings.toString(currentReserves))));
        }

        // reserves should change
        else {
            uint256 loanKickIncreaseInReserve = IBaseHandler(_handler).loanKickIncreaseInReserve();

            console.log("loanKickIncreaseInReserve -->", loanKickIncreaseInReserve);
            
            // reserves should increase by 0.25% of borrower debt on loan kick
            if(loanKickIncreaseInReserve != 0) {
                requireWithinDiff(currentReserves, previousReserves + loanKickIncreaseInReserve, 1e12, "Incorrect Reserves change with kick");
            }

            uint256 drawDebtIncreaseInReserve = IBaseHandler(_handler).drawDebtIncreaseInReserve();

            console.log("Draw debt increase in reserve --->", drawDebtIncreaseInReserve);
            // reserves should increase by origination fees on draw debt
            if(drawDebtIncreaseInReserve != 0) {
                requireWithinDiff(currentReserves, previousReserves + drawDebtIncreaseInReserve, 1e12, "Incorrect reserve change on draw debt");
            }

            uint256 firstTakeIncreaseInReserve = IBaseHandler(_handler).firstTakeIncreaseInReserve();
            bool isKickerRewarded = IBaseHandler(_handler).isKickerRewarded();
            uint256 kickerBondChange = IBaseHandler(_handler).kickerBondChange();

            console.log("Kicker Rewarded -->", isKickerRewarded);
            console.log("Kicker Bond change -->", kickerBondChange);

            console.log("firstTakeIncreaseInReserve -->", firstTakeIncreaseInReserve);

            uint256 previousReservesAndBondChange = isKickerRewarded ? previousReserves + kickerBondChange : previousReserves - kickerBondChange;
            
            // reserves should increase by 7% of borrower debt on first take
            if(IBaseHandler(_handler).firstTake()) {
                requireWithinDiff(currentReserves, previousReservesAndBondChange + firstTakeIncreaseInReserve, 1e12, "Incorrect Reserves change with first take");
            } else if(currentReserves != 0 && loanKickIncreaseInReserve == 0 && drawDebtIncreaseInReserve == 0) {
                requireWithinDiff(currentReserves, previousReservesAndBondChange, 1e21, "Incorrect Reserves change with not first take");
            }
        }
    }
}