// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.18;

import "@std/console.sol";

import { LiquidationInvariants }    from '../base/LiquidationInvariants.t.sol';
import { BaseInvariants }           from '../base/BaseInvariants.sol';
import { BasicInvariants }          from '../base/BasicInvariants.t.sol';
import { TradingERC20PoolHandler }  from './handlers/TradingERC20PoolHandler.sol';
import { BasicERC20PoolInvariants } from './BasicERC20PoolInvariants.t.sol';

contract TradingERC20PoolInvariants is BasicERC20PoolInvariants, LiquidationInvariants {
    
    TradingERC20PoolHandler internal _tradingERC20PoolHandler;

    address[] internal _lenders;
    address[] internal _borrowers;

    uint16 internal constant LENDERS     = 2_000;
    uint16 internal constant LOANS_COUNT = 8_000;

    function setUp() public override(BaseInvariants, BasicERC20PoolInvariants) virtual {

        super.setUp();

        excludeContract(address(_basicERC20PoolHandler));

        _tradingERC20PoolHandler = new TradingERC20PoolHandler(
            address(_erc20pool),
            address(_ajna),
            address(_poolInfo),
            address(this)
        );

        _handler = address(_tradingERC20PoolHandler);
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

        _invariant_F1();
        _invariant_F2();
        _invariant_F3();
        _invariant_F4();
        _invariant_F5();

        invariant_collateral_CT1_CT7();

        invariant_call_summary();
    }

    function invariant_call_summary() public virtual override(BasicInvariants, LiquidationInvariants) useCurrentTimestamp {
        super.invariant_call_summary();
    }

}