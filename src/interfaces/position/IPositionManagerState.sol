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

    /**
     *  @notice Returns the bucket LPs memorialized in a positions NFT.
     *  @param  tokenId     The token id of the positions NFT.
     *  @param  bucketIndex The bucket index memorialized in a positions NFT.
     *  @return Amount of bucket LPs memorialized in positions NFT.
     */
    function positionLPs(
        uint256 tokenId,
        uint256 bucketIndex
    ) external view returns (uint256);

}
