// SPDX-License-Identifier: MIT

pragma solidity 0.8.14;

/**
 * @title Positions Manager State
 */
interface IPositionManagerState {

    /**
     *  @notice Returns the pool address associated with a positions `NFT`.
     *  @param  tokenId_ The token id of the positions `NFT`.
     *  @return Pool address associated with the `NFT`.
     */
    function poolKey(
        uint256 tokenId_
    ) external view returns (address);
}

/// @dev Struct holding Position `LP` state.
struct Position {
    uint256 lps;         // [WAD] position LP
    uint256 depositTime; // deposit time for position
}
