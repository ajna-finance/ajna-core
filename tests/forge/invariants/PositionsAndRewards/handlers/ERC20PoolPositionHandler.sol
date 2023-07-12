// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.18;

import { PositionManager } from 'src/PositionManager.sol';
import { Pool }            from 'src/base/Pool.sol';
import { ERC20Pool }       from 'src/ERC20Pool.sol';

import { TokenWithNDecimals }          from '../../../utils/Tokens.sol';

import { PositionPoolHandler }  from  './PositionPoolHandler.sol';
import { BaseERC20PoolHandler } from '../../ERC20Pool/handlers/unbounded/BaseERC20PoolHandler.sol';

contract ERC20PoolPositionHandler is PositionPoolHandler, BaseERC20PoolHandler {

    constructor(
        address positions_,
        PoolInfo[10] memory pools_,
        address ajna_,
        address poolInfoUtils_,
        uint256 numOfActors_,
        address testContract_
    ) BaseERC20PoolHandler(pools_[0].pool, ajna_, pools_[0].quote, pools_[0].collateral, poolInfoUtils_, numOfActors_, testContract_) {

        for (uint256 i = 0; i < pools_.length; i++) {
            _pools.push(pools_[i]);
        }

        // Position manager
        _positionManager = PositionManager(positions_);

        // pool hash for mint() call
        _poolHash = bytes32(keccak256("ERC20_NON_SUBSET_HASH"));
    }

    modifier useRandomPool(uint256 poolIndex) override {
        poolIndex   = bound(poolIndex, 0, _pools.length - 1);
        _pool       = Pool(_pools[poolIndex].pool);
        _collateral = TokenWithNDecimals(_pools[poolIndex].collateral);
        _quote      = TokenWithNDecimals(_pools[poolIndex].quote);
        _erc20Pool = ERC20Pool(_pools[poolIndex].pool);

        _;
    }
}
