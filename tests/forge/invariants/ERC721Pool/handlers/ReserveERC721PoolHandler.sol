// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.18;

import { UnboundedReservePoolHandler } from '../../base/handlers/unbounded/UnboundedReservePoolHandler.sol';
import { ReservePoolHandler }          from '../../base/handlers/ReservePoolHandler.sol';
import { LiquidationERC721PoolHandler } from './LiquidationERC721PoolHandler.sol';

contract ReserveERC721PoolHandler is ReservePoolHandler, LiquidationERC721PoolHandler {

    constructor(
        address pool_,
        address ajna_,
        address poolInfo_,
        uint256 numOfActors_,
        address testContract_
    ) LiquidationERC721PoolHandler(pool_, ajna_, poolInfo_, numOfActors_, testContract_) {}

}