// SPDX-License-Identifier: MIT
pragma solidity 0.8.14;

/**
 * @title ERC721 Pool State
 */
interface IERC721PoolState {

    /**
     *  @notice Check if a token id is allowed as collateral in pool.
     *  @param  tokenId The token id to check.
     *  @return allowed True if token id is allowed in pool
     */
    function tokenIdsAllowed(
        uint256 tokenId
    ) external view returns (bool allowed);
}