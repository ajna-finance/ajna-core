// SPDX-License-Identifier: MIT

pragma solidity 0.8.11;

import { ClonesWithImmutableArgs } from "@clones/ClonesWithImmutableArgs.sol";

import { ERC20Pool } from "./ERC20Pool.sol";

import { IPoolFactory } from "./interfaces/IPoolFactory.sol";

contract ERC20PoolFactory is IPoolFactory {

    using ClonesWithImmutableArgs for address;

    mapping(address => mapping(address => address)) public deployedPools;

    ERC20Pool public implementation;

    constructor() {
        implementation = new ERC20Pool();
    }

    /** @inheritdoc IPoolFactory*/
    function deployPool(address collateral_, address quote_) external returns (address) {
        if (collateral_ == address(0) || quote_ == address(0)) {
            revert WethOnly();
        }

        if (deployedPools[collateral_][quote_] != address(0)) {
            revert PoolAlreadyExists();
        }

        bytes memory data = abi.encodePacked(collateral_, quote_);

        ERC20Pool pool = ERC20Pool(address(implementation).clone(data));
        pool.initialize();

        deployedPools[collateral_][quote_] = address(pool);
        emit PoolCreated(address(pool));
        return address(pool);
    }
}
