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
        address[] memory pools_,
        address ajna_,
        address poolInfoUtils_,
        uint256 numOfActors_,
        address testContract_
    ) BaseERC20PoolHandler(pools_[0], ajna_, poolInfoUtils_, numOfActors_, testContract_) {

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
        updateTokenAndPoolAddress(_pools[poolIndex]);

        _;
    }

    function updateTokenAndPoolAddress(address pool_) internal override {
        _pool = Pool(pool_);
        _erc20Pool = ERC20Pool(pool_);

        _quote = TokenWithNDecimals(_pool.quoteTokenAddress());
        _collateral = TokenWithNDecimals(_pool.collateralAddress());
    }
}
