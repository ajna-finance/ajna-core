// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.18;

import { PositionManager } from 'src/PositionManager.sol';

import { PositionPoolHandler }  from  './PositionPoolHandler.sol';
import { BaseERC20PoolHandler } from '../../ERC20Pool/handlers/unbounded/BaseERC20PoolHandler.sol';

import { MultiplePoolHandler } from './MultiplePoolHandler.sol';

contract MultiplePoolPositionHandler is PositionPoolHandler, MultiplePoolHandler {

    constructor(
        address positions_,
        PoolInfo[] pools_,
        address ajna_,
        address poolInfo_,
        uint256 numOfActors_,
        address testContract_
    ) MultiplePoolHandler(pools_, ajna_, poolInfo_, numOfActors_, testContract_) {

        // Position manager
        _positionManager = PositionManager(positions_);

        // TODO: replace usage of _poolHash variable with calls to tokenId to find out pool type and then the appropriate hash automatically.
        // pool hash for mint() call
        _poolHash = bytes32(keccak256("ERC20_NON_SUBSET_HASH"));
    }
}
