// SPDX-License-Identifier: MIT
pragma solidity 0.8.14;

import { IPoolFactory } from "../../base/interfaces/IPoolFactory.sol";

/**
 *  @title Ajna Pool Factory
 *  @dev   Used to deploy non fungible pools.
 */
interface IERC721PoolFactory is IPoolFactory {

    /**************************/
    /*** External Functions ***/
    /**************************/

    /**
     *  @notice Deploys a cloned pool for the given collateral and quote token.
     *  @dev    Pool must not already exist, and must use WETH instead of ETH.
     *  @param  collateral_   Address of NFT collateral token.
     *  @param  quote_        Address of NFT quote token.
     *  @param  tokenIds_     Ids of subset NFT tokens.
     *  @param  interestRate_ Initial interest rate of the pool.
     *  @return pool_         Address of the newly created pool.
     */
    function deploySubsetPool(address collateral_, address quote_, uint256[] memory tokenIds_, uint256 interestRate_) external returns (address pool_);
}
