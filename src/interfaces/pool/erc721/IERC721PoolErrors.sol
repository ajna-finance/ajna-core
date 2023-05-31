// SPDX-License-Identifier: MIT

pragma solidity 0.8.18;

/**
 * @title ERC721 Pool Errors
 */
interface IERC721PoolErrors {

    /**
     *  @notice User attempted to add an `NFT` to the pool with a `tokenId` outside of the allowed subset.
     */
    error OnlySubset();
    
    /**
     *  @notice User tried to deploy a pool with an array of `tokenIds` that weren't sorted, or contained duplicates.
     */
    error TokenIdSubsetInvalid();
}