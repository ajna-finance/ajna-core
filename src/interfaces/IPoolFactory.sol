// SPDX-License-Identifier: MIT
pragma solidity 0.8.11;

/// @title Ajna Pool Factory
/// @dev Used to deploy both funigible and non fungible pools
interface IPoolFactory {

    event PoolCreated(address pool);

    error WethOnly();
    error PoolAlreadyExists();

    /// @notice Deploys a cloned pool for the given collateral and quote token
    /// @dev Pool must not already exist, and must use WETH instead of ETH
    function deployPool(address collateral_, address quote_) external returns (address pool_);
}
