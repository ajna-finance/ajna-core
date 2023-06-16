// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.18;

import { PositionManager }              from 'src/PositionManager.sol';

import { BaseERC721PoolPositionHandler } from  './BaseERC721PoolPositionHandler.sol';
import { BaseERC721PoolHandler }     from '../../ERC721Pool/handlers/unbounded/BaseERC721PoolHandler.sol';

contract ERC721PoolPositionHandler is BaseERC721PoolPositionHandler {

    constructor(
        address positions_,
        address pool_,
        address ajna_,
        address quote_,
        address collateral_,
        address poolInfo_,
        uint256 numOfActors_,
        address testContract_
    ) BaseERC721PoolHandler(pool_, ajna_, quote_, collateral_, poolInfo_, numOfActors_, testContract_) {

        // Position manager
        _positionManager = PositionManager(positions_);
    }
}
