// SPDX-License-Identifier: MIT

pragma solidity 0.8.14;

import './interfaces/IPoolFactory.sol';

// TODO: determine access control
contract FactoryStorage {

    // TODO: need to figure out how to ensure this is only written to by our factory addresses
    /// @dev SubsetHash => CollateralAddress => QuoteAddress => Pool Address
    // slither-disable-next-line uninitialized-state
    mapping(bytes32 => mapping(address => mapping(address => address))) public deployedPools;

    address[] public deployPoolList;


}
