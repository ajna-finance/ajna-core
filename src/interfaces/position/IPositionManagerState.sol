// SPDX-License-Identifier: MIT

pragma solidity 0.8.14;

/**
 * @title Positions Manager State
 */
interface IPositionManagerState {

    /**
     *  @notice Returns the pool address associated with a positions NFT.
     *  @param  tokenId The token id of the positions NFT.
     *  @return Pool address associated with the NFT.
     */
    function poolKey(
        uint256 tokenId
    ) external view returns (address);
}

struct Position {
    uint256 lps;         // [WAD] position LPs
    uint256 depositTime; // deposit time for position
}
