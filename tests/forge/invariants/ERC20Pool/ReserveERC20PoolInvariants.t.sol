// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.18;

import { BaseInvariants }                 from '../base/BaseInvariants.sol';
import { LiquidationInvariants }          from '../base/LiquidationInvariants.t.sol';
import { ReserveInvariants }              from '../base/ReserveInvariants.t.sol';
import { ReserveERC20PoolHandler }        from './handlers/ReserveERC20PoolHandler.sol';
import { LiquidationERC20PoolInvariants } from './LiquidationERC20PoolInvariants.t.sol';

contract ReserveERC20PoolInvariants is ReserveInvariants, LiquidationERC20PoolInvariants {
    
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

    function invariant_call_summary() public virtual override(LiquidationERC20PoolInvariants, ReserveInvariants) useCurrentTimestamp {
        super.invariant_call_summary();
    }

}