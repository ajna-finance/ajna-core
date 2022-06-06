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

    function deployNFTCollectionPool(address collateral_, address quote_) external canDeploy(NON_SUBSET_HASH, collateral_, quote_) returns (address) {
        bytes memory data = abi.encodePacked(collateral_, quote_);

        ERC721Pool pool = ERC721Pool(address(implementation).clone(data));
        pool.initialize();

        deployedPools[NON_SUBSET_HASH][collateral_][quote_] = address(pool);
        emit PoolCreated(address(pool));
        return address(pool);
    }

    function deployNFTSubsetPool(address collateral_, address quote_, uint256[] memory tokenIds_) external canDeploy(getNFTSubsetHash(tokenIds_), collateral_, quote_) returns (address) {
        bytes memory data = abi.encodePacked(collateral_, quote_, tokenIds_);

        ERC721Pool pool = ERC721Pool(address(implementation).clone(data));
        pool.initializeSubset(tokenIds_);

        deployedPools[getNFTSubsetHash(tokenIds_)][collateral_][quote_] = address(pool);
        emit PoolCreated(address(pool));
        return address(pool);
    }
}
