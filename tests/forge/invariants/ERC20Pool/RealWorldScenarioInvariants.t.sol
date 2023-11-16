// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.18;

import "@std/console.sol";

import { BaseInvariants }                 from '../base/BaseInvariants.sol';
import { ReserveInvariants }              from '../base/ReserveInvariants.t.sol';
import { ReserveERC20PoolHandler }        from './handlers/ReserveERC20PoolHandler.sol';
import { LiquidationERC20PoolInvariants } from './LiquidationERC20PoolInvariants.t.sol';

contract RealWorldScenarioInvariants is ReserveInvariants, LiquidationERC20PoolInvariants {

    ReserveERC20PoolHandler internal _reserveERC20PoolHandler;

    function setUp() public override(BaseInvariants, LiquidationERC20PoolInvariants) virtual {

        super.setUp();

        excludeContract(address(_liquidationERC20PoolHandler));

        _reserveERC20PoolHandler = new ReserveERC20PoolHandler(
            address(_erc20pool),
            address(_ajna),
            address(_poolInfo),
            _numOfActors,
            address(this)
        );

        _handler = address(_reserveERC20PoolHandler);
    }

    function invariant_all_erc20() public useCurrentTimestamp {
        console.log("Quote precision:     ", _quote.decimals());
        console.log("Collateral precision:", _collateral.decimals());
        console.log("Quote balance:       ", _quote.balanceOf(address(_pool)));
        console.log("Collateral balance:  ", _collateral.balanceOf(address(_pool)));

        _invariant_B1();
        _invariant_B2_B3();
        _invariant_B4();
        _invariant_B5_B6_B7();

        _invariant_QT1();
        _invariant_QT2();
        _invariant_QT3();

        _invariant_R1_R2_R3_R4_R5_R6_R7_R8();

        _invariant_L1_L2_L3();

        _invariant_I1();
        _invariant_I2();
        _invariant_I3();
        _invariant_I4();

        _invariant_F1();
        _invariant_F2();
        _invariant_F3();
        _invariant_F4();
        _invariant_F5();

        invariant_collateral_CT1_CT7();

        _invariant_A1();
        _invariant_A2();
        _invariant_A3_A4();
        _invariant_A5();
        _invariant_A7();

        invariant_reserves();

        invariant_call_summary();
    }

    function invariant_call_summary() public virtual override(LiquidationERC20PoolInvariants, ReserveInvariants) useCurrentTimestamp {
        super.invariant_call_summary();
    }

}