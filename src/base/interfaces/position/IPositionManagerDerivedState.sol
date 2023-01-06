// SPDX-License-Identifier: MIT

pragma solidity 0.8.14;

/**
 * @title Positions Manager Derived State
 */
interface IPositionManagerDerivedState {

    /**
     *  @notice Returns the lpTokens accrued to a given tokenId, bucket pairing.
     *  @dev    Nested mappings aren't returned normally as part of the default getter for a mapping.
     *  @param  tokenId  Unique ID of token.
     *  @param  index    Index of bucket to check LP balance of.
     *  @return lpTokens Balance of lpTokens in the bucket for this position.
    */
    function getLPTokens(
        uint256 tokenId,
        uint256 index
    ) external view returns (uint256 lpTokens);

    /**
     *  @notice Returns an array of bucket indexes in which an NFT has liquidity.
     *  @param  tokenId  Unique ID of token.
     *  @return Array of bucket indexes.
    */
    function getPositionIndexes(
        uint256 tokenId
    ) external view returns (uint256[] memory);

    /**
     *  @notice Checks if a given tokenId has a given position bucket
     *  @param  tokenId           Unique ID of token.
     *  @param  index             Index of bucket to check if in position buckets.
     *  @return bucketInPosition  True if tokenId has the position bucket.
    */
    function isIndexInPosition(
        uint256 tokenId,
        uint256 index
    ) external view returns (bool bucketInPosition);
}
