// SPDX-License-Identifier: MIT

pragma solidity 0.8.14;

import { IPoolFactory } from '../IPoolFactory.sol';

/**
 *  @title ERC20 Pool Factory
 *  @dev   Used to deploy ERC20 pools.
 */
interface IERC20PoolFactory is IPoolFactory {

    /**************************/
    /*** External Functions ***/
    /**************************/

    /**
     *  @notice Deploys a cloned pool for the given collateral and quote token.
     *  @dev    Pool must not already exist, and must use WETH instead of ETH.
     *  @param  collateral   Address of ERC20 collateral token.
     *  @param  quote        Address of ERC20 quote token.
     *  @param  interestRate Initial interest rate of the pool.
     *  @return pool         Address of the newly created pool.
     */
    function deployPool(
        address collateral,
        address quote,
        uint256 interestRate
    ) external returns (address pool);
}
