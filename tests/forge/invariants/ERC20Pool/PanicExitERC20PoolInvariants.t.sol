// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.18;

import "@std/console.sol";

import { LiquidationInvariants }     from '../base/LiquidationInvariants.t.sol';
import { BaseInvariants }            from '../base/BaseInvariants.sol';
import { BasicInvariants }           from '../base/BasicInvariants.t.sol';
import { PanicExitERC20PoolHandler } from './handlers/PanicExitERC20PoolHandler.sol';
import { BasicERC20PoolInvariants }  from './BasicERC20PoolInvariants.t.sol';

contract PanicExitERC20PoolInvariants is BasicERC20PoolInvariants, LiquidationInvariants {
    
    PanicExitERC20PoolHandler internal _panicExitERC20PoolHandler;

    address[] internal _lenders;
    address[] internal _borrowers;

    uint16 internal constant LENDERS     = 2_000;
    uint16 internal constant LOANS_COUNT = 8_000;

    function setUp() public override(BaseInvariants, BasicERC20PoolInvariants) virtual {

        super.setUp();

        excludeContract(address(_basicERC20PoolHandler));

        _panicExitERC20PoolHandler = new PanicExitERC20PoolHandler(
            address(_erc20pool),
            address(_ajna),
            address(_poolInfo),
            address(this)
        );

        _handler = address(_panicExitERC20PoolHandler);
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

        invariant_call_summary();
    }

    function invariant_call_summary() public virtual override(BasicInvariants, LiquidationInvariants) useCurrentTimestamp {
        super.invariant_call_summary();
    }

}