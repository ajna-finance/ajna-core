// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.18;

import { PositionManager } from 'src/PositionManager.sol';

import { PositionPoolHandler }  from  './PositionPoolHandler.sol';
import { BaseERC20PoolHandler } from '../../ERC20Pool/handlers/unbounded/BaseERC20PoolHandler.sol';
import { BaseERC721PoolHandler } from '../../ERC721Pool/handlers/unbounded/BaseERC721PoolHandler.sol';

contract ERC20PoolHandler is BaseERC20PoolHandler {
    constructor(
        address pool_,
        address ajna_,
        address quote_,
        address collateral_,
        address poolInfo_,
        uint256 numOfActors_,
        address testContract_
    ) BaseERC20PoolHandler(pool_, ajna_, quote_, collateral_, poolInfo_, numOfActors_, testContract_) {}
}

contract ERC721PoolHandler is BaseERC721PoolHandler {
    constructor(
        address pool_,
        address ajna_,
        address quote_,
        address collateral_,
        address poolInfo_,
        uint256 numOfActors_,
        address testContract_
    ) BaseERC721PoolHandler(pool_, ajna_, quote_, collateral_, poolInfo_, numOfActors_, testContract_) {}
}

// TODO: find a better directory location for this handler so that it can be used for a multiple pool scenario outside of positions and rewards
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

    mapping (address pool => PoolInfo poolInfo) public poolInfos;

    constructor(
        PoolInfo[] memory pools_,
        address ajna_,
        address poolInfo_,
        uint256 numOfActors_,
        address testContract_
    ) {

        for (uint256 i = 0; i < pools_.length; i++) {
            _pools.push(pools_[i]);

            if (pools_[i].is721) {
                handlers.push(address(new ERC20PoolHandler(
                    pools_[i].pool,
                    ajna_,
                    pools_[i].quote,
                    pools_[i].collateral,
                    poolInfo_,
                    numOfActors_,
                    testContract_
                )));
            } else {
                handlers.push(address(new ERC721PoolHandler(
                    pools_[i].pool,
                    ajna_,
                    pools_[i].quote,
                    pools_[i].collateral,
                    poolInfo_,
                    numOfActors_,
                    testContract_
                )));
            }
        }

    }

}
