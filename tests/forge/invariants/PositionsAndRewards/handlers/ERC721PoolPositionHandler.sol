// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.18;

import { PositionManager } from 'src/PositionManager.sol';
import { Pool }            from 'src/base/Pool.sol';
import { ERC721Pool }      from 'src/ERC721Pool.sol';

import { TokenWithNDecimals, NFTCollateralToken } from '../../../utils/Tokens.sol';

import { PositionPoolHandler }   from  './PositionPoolHandler.sol';
import { BaseERC721PoolHandler } from '../../ERC721Pool/handlers/unbounded/BaseERC721PoolHandler.sol';

contract ERC721PoolPositionHandler is PositionPoolHandler, BaseERC721PoolHandler {

    constructor(
        address positions_,
        address[] memory pools_,
        address ajna_,
        address poolInfoUtils_,
        uint256 numOfActors_,
        address testContract_
    ) BaseERC721PoolHandler(pools_[0], ajna_, poolInfoUtils_, numOfActors_, testContract_) {

        for (uint256 i = 0; i < pools_.length; i++) {
            _pools.push(pools_[i]);
        }

        // Position manager
        _positionManager = PositionManager(positions_);

        // pool hash for mint() call
        _poolHash = bytes32(keccak256("ERC721_NON_SUBSET_HASH"));
    }

    modifier useRandomPool(uint256 poolIndex) override {
        poolIndex   = bound(poolIndex, 0, _pools.length - 1);
        updateTokenAndPoolAddress(_pools[poolIndex]);

        _;
    }

    function updateTokenAndPoolAddress(address pool_) internal override {
        _pool = Pool(pool_);
        _erc721Pool = ERC721Pool(pool_);

        _quote = TokenWithNDecimals(_pool.quoteTokenAddress());
        _collateral = NFTCollateralToken(_pool.collateralAddress());
    }
}
