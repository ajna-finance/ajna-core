// SPDX-License-Identifier: MIT

pragma solidity 0.8.11;

import { ClonesWithImmutableArgs } from "@clones/ClonesWithImmutableArgs.sol";

import { ERC721Pool } from "./ERC721Pool.sol";

import { PoolDeployer } from "./base/PoolDeployer.sol";

import { IPoolFactory } from "./interfaces/IPoolFactory.sol";

// TODO: add IERC721PoolFactory
contract ERC721PoolFactory is PoolDeployer {

    using ClonesWithImmutableArgs for address;

    ERC721Pool public implementation;

    event PoolCreated(address pool_);

    constructor() {
        implementation = new ERC721Pool();
    }

    function deployNFTCollectionPool(address collateral_, address quote_) external canDeploy(NON_SUBSET_HASH, collateral_, quote_) returns (address pool_) {
        bytes memory data = abi.encodePacked(collateral_, quote_);

        ERC721Pool pool = ERC721Pool(address(implementation).clone(data));
        pool.initialize();
        pool_ = address(pool);

        deployedPools[NON_SUBSET_HASH][collateral_][quote_] = pool_;
        emit PoolCreated(pool_);
    }

    function deployNFTSubsetPool(address collateral_, address quote_, uint256[] memory tokenIds_) external canDeploy(getNFTSubsetHash(tokenIds_), collateral_, quote_) returns (address pool_) {
        bytes memory data = abi.encodePacked(collateral_, quote_, tokenIds_);

        ERC721Pool pool = ERC721Pool(address(implementation).clone(data));
        pool.initializeSubset(tokenIds_);
        pool_ = address(pool);

        deployedPools[getNFTSubsetHash(tokenIds_)][collateral_][quote_] = pool_;
        emit PoolCreated(pool_);
    }
}
