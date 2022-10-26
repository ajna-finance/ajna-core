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

    /**
     *  @notice User attempted to pull or remove a token that was not pledged or is not the next available token to be processed.
     *  @notice When pulling or taking, tokens will be processed in the reverse order of the time they were pledged by borrower (latest token pledged will be processed first).
     */
    error TokenMismatch();
}