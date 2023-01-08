// SPDX-License-Identifier: MIT

pragma solidity 0.8.14;

import { IPoolFactory } from '../IPoolFactory.sol';

/**
 *  @title ERC721 Pool Factory
 *  @dev   Used to deploy non fungible pools.
 */
interface IERC721PoolFactory is IPoolFactory {

    /**************************/
    /*** External Functions ***/
    /**************************/

    /**
     *  @notice Deploys a cloned pool for the given collateral and quote token.
     *  @dev    Pool must not already exist, and must use WETH instead of ETH.
     *  @param  collateral   Address of NFT collateral token.
     *  @param  quote        Address of NFT quote token.
     *  @param  tokenIds     Ids of subset NFT tokens.
     *  @param  interestRate Initial interest rate of the pool.
     *  @return pool         Address of the newly created pool.
     */
    function deployPool(
        address collateral,
        address quote,
        uint256[] memory tokenIds,
        uint256 interestRate
    ) external returns (address pool);

    /**
     *  @notice User attempted to make pool with non supported NFT contract as collateral.
     */
    error NFTNotSupported();
}
