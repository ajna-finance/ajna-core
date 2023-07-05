// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.18;

import { PositionManager } from 'src/PositionManager.sol';

import { PositionPoolHandler }  from  './PositionPoolHandler.sol';
import { BaseERC20PoolHandler } from '../../ERC20Pool/handlers/unbounded/BaseERC20PoolHandler.sol';
import { BaseERC721PoolHandler } from '../../ERC721Pool/handlers/unbounded/BaseERC721PoolHandler.sol';

// TODO: find a better directory location for this handler so that it can be used for a multiple pool scenario outside of positions and rewards
// TODO: inherit from erc20 and erc721 pool handlers
abstract contract MultiplePoolHandler {

    struct PoolInfo {
        address pool;
        address quote;
        address collateral;
        bool is721;
        uint256 numActors; // TODO: handle actors on a per pool basis?
    }

    PoolInfo[] internal _pools;

    address[] handlers;

    constructor(
        PoolInfo[] pools_,
        address ajna_,
        address poolInfo_,
        uint256 numOfActors_,
        address testContract_
    ) {

        for (uint256 i = 0; i < pools_.length; i++) {
            _pools.push(pools_[i]);

            if (pools_[i].is721) {
                handlers.push(address(new BaseERC721PoolHandler(
                    pools_[i].pool,
                    ajna_,
                    pools_[i].quote,
                    pools_[i].collateral,
                    poolInfo_,
                    numOfActors_
                )));
            } else {
                handlers.push(address(new BaseERC20PoolHandler(
                    pools_[i].pool,
                    ajna_,
                    pools_[i].quote,
                    pools_[i].collateral,
                    poolInfo_,
                    numOfActors_
                )));
            }
        }

    }
}
