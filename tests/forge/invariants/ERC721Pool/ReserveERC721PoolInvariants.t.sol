// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.14;

import "@std/console.sol";

import { BaseInvariants }                 from '../base/BaseInvariants.sol';
import { LiquidationInvariants }          from '../base/LiquidationInvariants.t.sol';
import { ReserveInvariants }              from '../base/ReserveInvariants.t.sol';
import { ReserveERC721PoolHandler }        from './handlers/ReserveERC721PoolHandler.sol';
import { LiquidationERC721PoolInvariants } from './LiquidationERC721PoolInvariants.t.sol';

contract ReserveERC721PoolInvariants is ReserveInvariants, LiquidationERC721PoolInvariants {
    
    ReserveERC721PoolHandler internal _reserveERC721PoolHandler;

    function setUp() public override(BaseInvariants, LiquidationERC721PoolInvariants) virtual {

        super.setUp();

        excludeContract(address(_liquidationERC721PoolHandler));

        _reserveERC721PoolHandler = new ReserveERC721PoolHandler(
            address(_erc721pool),
            address(_ajna),
            address(_quote),
            address(_collateral),
            address(_poolInfo),
            NUM_ACTORS,
            address(this)
        );

        _handler = address(_reserveERC721PoolHandler);
    }

    function invariant_call_summary() public virtual override( LiquidationInvariants, LiquidationERC721PoolInvariants) useCurrentTimestamp {}

}