// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.18;

import { PositionManager }              from 'src/PositionManager.sol';

import { BasePositionHandler } from  './BasePositionHandler.sol';
import { BaseERC20PoolHandler }     from '../../ERC20Pool/handlers/unbounded/BaseERC20PoolHandler.sol';

contract PositionHandler is BasePositionHandler {

    constructor(
        address positions_,
        address pool_,
        address ajna_,
        address quote_,
        address collateral_,
        address poolInfo_,
        uint256 numOfActors_,
        address testContract_
    ) BaseERC20PoolHandler(pool_, ajna_, quote_, collateral_, poolInfo_, numOfActors_, testContract_) {

        // Position manager
        _positionManager = PositionManager(positions_);
    }
}
