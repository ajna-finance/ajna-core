// SPDX-License-Identifier: MIT
pragma solidity 0.8.14;

/**
 *  @title Ajna Pool Factory
 *  @dev   Used to deploy both funigible and non fungible pools.
 */
interface IPoolFactory {

    /**************************/
    /*** External Functions ***/
    /**************************/

    /**
     *  @notice Deploys a cloned pool for the given collateral and quote token.
     *  @dev    Pool must not already exist, and must use WETH instead of ETH.
     *  @param  collateral_ Address of ERC20 collateral token.
     *  @param  quote_      Address of ERC20 quote token.
     *  @return pool_       Address of the newly created pool.
     */
    function deployPool(address collateral_, address quote_) external returns (address pool_);
}
