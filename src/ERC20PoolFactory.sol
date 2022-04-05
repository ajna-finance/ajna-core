// SPDX-License-Identifier: MIT

pragma solidity 0.8.11;

import {ClonesWithImmutableArgs} from "@clones/ClonesWithImmutableArgs.sol";

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Pool} from "./ERC20Pool.sol";

contract ERC20PoolFactory {
    using ClonesWithImmutableArgs for address;

    ERC20Pool public implementation;
    mapping(address => mapping(address => address)) public deployedPools;

    event PoolCreated(ERC20Pool pool);

    error PoolAlreadyExists();

    constructor() {
        implementation = new ERC20Pool();
    }

    function deployPool(ERC20 collateral, ERC20 quote)
        external
        returns (ERC20Pool pool)
    {
        if (deployedPools[address(collateral)][address(quote)] != address(0)) {
            revert PoolAlreadyExists();
        }

        bytes memory data = abi.encodePacked(collateral, quote);

        pool = ERC20Pool(address(implementation).clone(data));
        pool.initialize();

        deployedPools[address(collateral)][address(quote)] = address(pool);
        emit PoolCreated(pool);
    }

    function isPoolDeployed(ERC20 collateral, ERC20 quote)
        external
        view
        returns (bool)
    {
        return deployedPools[address(collateral)][address(quote)] != address(0);
    }

    // https://ethereum.stackexchange.com/questions/100025/calculate-deterministic-address-with-create2-when-cloning-contract-with-factory
    // function predictCloneAddress()
}
