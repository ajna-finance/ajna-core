// SPDX-License-Identifier: MIT

pragma solidity 0.8.11;

import {ClonesWithImmutableArgs} from "@clones/ClonesWithImmutableArgs.sol";

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Pool} from "./ERC20Pool.sol";

contract ERC20PoolFactory {
    using ClonesWithImmutableArgs for address;

    ERC20Pool public implementation;

    event PoolCreated(ERC20Pool pool);

    constructor() {
        implementation = new ERC20Pool();
    }

    function deployPool(ERC20 collateral, ERC20 quote)
        external
        returns (ERC20Pool pool)
    {
        bytes memory data = abi.encodePacked(collateral, quote);

        pool = ERC20Pool(address(implementation).clone(data));
        pool.initialize();

        emit PoolCreated(pool);
    }
}
