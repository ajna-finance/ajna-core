// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.14;

import { LiquidationInvariants }       from '../base/LiquidationInvariants.t.sol';
import { BaseInvariants }              from '../base/BaseInvariants.sol';
import { BasicInvariants }             from '../base/BasicInvariants.t.sol';
import { LiquidationERC721PoolHandler } from './handlers/LiquidationERC721PoolHandler.sol';
import { BasicERC721PoolInvariants }    from './BasicERC721PoolInvariants.t.sol';

contract LiquidationERC721PoolInvariants is BasicERC721PoolInvariants, LiquidationInvariants {
    
    LiquidationERC721PoolHandler internal _liquidationERC721PoolHandler;

    function setUp() public override(BaseInvariants, BasicERC721PoolInvariants) virtual{

        super.setUp();

        excludeContract(address(_basicERC721PoolHandler));

        _liquidationERC721PoolHandler = new LiquidationERC721PoolHandler(
            address(_erc721pool),
            address(_ajna),
            address(_quote),
            address(_collateral),
            address(_poolInfo),
            NUM_ACTORS,
            address(this)
        );

        _handler = address(_liquidationERC721PoolHandler);
    }

    function invariant_call_summary() public virtual override(BasicInvariants, LiquidationInvariants) useCurrentTimestamp {
        super.invariant_call_summary();
    }

}