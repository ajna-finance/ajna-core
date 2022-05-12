// SPDX-License-Identifier: MIT

pragma solidity 0.8.11;

import { ClonesWithImmutableArgs } from "@clones/ClonesWithImmutableArgs.sol";

import { ERC721Pool } from "./ERC721Pool.sol";

import { FactoryValidation } from "./base/FactoryValidation.sol";

import { IPoolFactory } from "./interfaces/IPoolFactory.sol";

contract ERC721PoolFactory is IPoolFactory, FactoryValidation {

    using ClonesWithImmutableArgs for address;

    mapping(address => mapping(address => address)) public deployedPools;

    ERC721Pool public implementation;

    error ERC721Only();

    constructor() {
        implementation = new ERC721Pool();
    }

    /// @inheritdoc IPoolFactory
    function deployPool(address collateral_, address quote_) external WETHOnly(collateral_, quote_) returns (address) {
        // check that collateral is ERC721
        if (isERC721(collateral_) != true) {
            revert ERC721Only();
        }

        // check that quote is not ERC721
        if (isERC721(quote_)) {
            revert ERC20Only();
        }

        if (deployedPools[collateral_][quote_] != address(0)) {
            revert PoolAlreadyExists();
        }

        bytes memory data = abi.encodePacked(collateral_, quote_);

        ERC721Pool pool = ERC721Pool(address(implementation).clone(data));
        pool.initialize();

        deployedPools[collateral_][quote_] = address(pool);
        emit PoolCreated(address(pool));
        return address(pool);
    }
}
