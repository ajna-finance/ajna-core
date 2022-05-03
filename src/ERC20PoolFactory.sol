// SPDX-License-Identifier: MIT

pragma solidity 0.8.11;

import { ClonesWithImmutableArgs } from "@clones/ClonesWithImmutableArgs.sol";

import { ERC20Pool } from "./ERC20Pool.sol";

contract ERC20PoolFactory {

    using ClonesWithImmutableArgs for address;

    mapping(address => mapping(address => address)) public deployedPools;

    ERC20Pool public implementation;

    event PoolCreated(ERC20Pool pool);

    error WethOnly();
    error PoolAlreadyExists();

    constructor() {
        implementation = new ERC20Pool();
    }

    function deployPool(address collateral_, address quote_) external returns (ERC20Pool pool_) {
        if (collateral_ == address(0) || quote_ == address(0)) {
            revert WethOnly();
        }

        if (deployedPools[collateral_][quote_] != address(0)) {
            revert PoolAlreadyExists();
        }

        bytes memory data = abi.encodePacked(collateral_, quote_);

        pool_ = ERC20Pool(address(implementation).clone(data));
        pool_.initialize();

        deployedPools[collateral_][quote_] = address(pool_);
        emit PoolCreated(pool_);
    }

    // TODO: https://ethereum.stackexchange.com/questions/100025/calculate-deterministic-address-with-create2-when-cloning-contract-with-factory
    // function predictCloneAddress()
}
