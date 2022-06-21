// SPDX-License-Identifier: MIT

pragma solidity 0.8.14;

import { ClonesWithImmutableArgs } from "@clones/ClonesWithImmutableArgs.sol";

import { ERC721Pool } from "./ERC721Pool.sol";

import { PoolDeployer } from "../base/PoolDeployer.sol";

import { IERC721PoolFactory } from "./interfaces/IERC721PoolFactory.sol";

// TODO: add IERC721PoolFactory
contract ERC721PoolFactory is IERC721PoolFactory, PoolDeployer {

    using ClonesWithImmutableArgs for address;

    ERC721Pool public implementation;

    /// @dev Default bytes32 hash used by ERC721 Non-NFTSubset pool types
    bytes32 public constant ERC721_NON_SUBSET_HASH = keccak256("ERC721_NON_SUBSET_HASH");

    constructor() {
        implementation = new ERC721Pool();
    }

    function deployPool(
        address collateral_, address quote_, uint256 interestRate_
    ) external canDeploy(ERC721_NON_SUBSET_HASH, collateral_, quote_, interestRate_) returns (address pool_) {
        bytes memory data = abi.encodePacked(collateral_, quote_);

        ERC721Pool pool = ERC721Pool(address(implementation).clone(data));
        pool.initialize(interestRate_);
        pool_ = address(pool);

        deployedPools[ERC721_NON_SUBSET_HASH][collateral_][quote_] = pool_;
        emit PoolCreated(pool_);
    }

    function deploySubsetPool(
        address collateral_, address quote_, uint256[] memory tokenIds_, uint256 interestRate_
    ) external canDeploy(getNFTSubsetHash(tokenIds_), collateral_, quote_, interestRate_) returns (address pool_) {
        bytes memory data = abi.encodePacked(collateral_, quote_, tokenIds_);

        ERC721Pool pool = ERC721Pool(address(implementation).clone(data));
        pool.initializeSubset(tokenIds_, interestRate_);
        pool_ = address(pool);

        deployedPools[getNFTSubsetHash(tokenIds_)][collateral_][quote_] = pool_;
        emit PoolCreated(pool_);
    }
}
