// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.14;

import { LiquidationInvariants }       from '../base/LiquidationInvariants.t.sol';
import { BaseInvariants }              from '../base/BaseInvariants.sol';
import { BasicInvariants }             from '../base/BasicInvariants.t.sol';
import { LiquidationERC20PoolHandler } from './handlers/LiquidationERC20PoolHandler.sol';
import { BasicERC20PoolInvariants }    from './BasicERC20PoolInvariants.t.sol';

contract LiquidationERC20PoolInvariants is BasicERC20PoolInvariants, LiquidationInvariants {
    
    LiquidationERC20PoolHandler internal _liquidationERC20PoolHandler;

    function setUp() public override(BaseInvariants, BasicERC20PoolInvariants) virtual{

        super.setUp();

        excludeContract(address(_basicERC20PoolHandler));

        _liquidationERC20PoolHandler = new LiquidationERC20PoolHandler(
            address(_erc20pool),
            address(_ajna),
            address(_quote),
            address(_collateral),
            address(_poolInfo),
            NUM_ACTORS,
            address(this)
        );

        _handler = address(_liquidationERC20PoolHandler);
    }

    function invariant_call_summary() public virtual override(BasicInvariants, LiquidationInvariants) useCurrentTimestamp {
        super.invariant_call_summary();
    }

}