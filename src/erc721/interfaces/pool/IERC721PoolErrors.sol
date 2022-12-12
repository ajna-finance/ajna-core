// SPDX-License-Identifier: MIT

pragma solidity 0.8.14;

/**
 * @title ERC721 Pool Errors
 */
interface IERC721PoolErrors {

    /**
     *  @notice User attempted to add an NFT to the pool with a tokenId outsde of the allowed subset.
     */
    error OnlySubset();
}