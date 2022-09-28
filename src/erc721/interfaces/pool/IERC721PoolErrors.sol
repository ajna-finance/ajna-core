// SPDX-License-Identifier: MIT

pragma solidity 0.8.14;

/**
 * @title ERC721 Pool Errors
 */
interface IERC721PoolErrors {

    /**
     *  @notice Failed to add tokenId to an EnumerableSet.
     */
    error AddTokenFailed();

    /**
     *  @notice User attempted to add an NFT to the pool with a tokenId outsde of the allowed subset.
     */
    error OnlySubset();

    /**
     *  @notice Failed to remove a tokenId from an EnumerableSet.
     */
    error RemoveTokenFailed();

    /**
     *  @notice User attempted to interact with a tokenId that hasn't been deposited into the pool or bucket.
     */
    error TokenNotDeposited();
}