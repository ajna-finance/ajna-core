// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.14;

import "@std/console.sol";

import { BaseInvariants }                 from '../base/BaseInvariants.sol';
import { LiquidationInvariants }          from '../base/LiquidationInvariants.t.sol';
import { ReserveInvariants }              from '../base/ReserveInvariants.t.sol';
import { ReserveERC20PoolHandler }        from './handlers/ReserveERC20PoolHandler.sol';
import { LiquidationERC20PoolInvariants } from './LiquidationERC20PoolInvariants.t.sol';

contract ReserveERC20PoolInvariants is ReserveInvariants, LiquidationERC20PoolInvariants {

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
        * RE11: Reserves decrease by claimableReserves by kickReserveAuction
        * RE12: Reserves decrease by amount of reserve used to settle a auction
    ****************************************************************************************************************************************/
    
    ReserveERC20PoolHandler internal _reserveERC20PoolHandler;

    function setUp() public override(BaseInvariants, LiquidationERC20PoolInvariants) virtual {

        super.setUp();

        excludeContract(address(_liquidationERC20PoolHandler));

        _reserveERC20PoolHandler = new ReserveERC20PoolHandler(
            address(_erc20pool),
            address(_ajna),
            address(_quote),
            address(_collateral),
            address(_poolInfo),
            NUM_ACTORS,
            address(this)
        );

        _handler = address(_reserveERC20PoolHandler);
    }

    function invariant_call_summary() public virtual override( LiquidationInvariants, LiquidationERC20PoolInvariants) useCurrentTimestamp {}

}