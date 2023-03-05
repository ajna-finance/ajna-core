// SPDX-License-Identifier: MIT

pragma solidity 0.8.14;

/**
 * @title Positions Manager Derived State
 */
interface IPositionManagerDerivedState {

    /**
     *  @notice Returns the LPs accrued to a given tokenId, bucket pairing.
     *  @dev    Nested mappings aren't returned normally as part of the default getter for a mapping.
     *  @param  tokenId Unique ID of token.
     *  @param  index   Index of bucket to check LP balance of.
     *  @return lps     Balance of lps in the bucket for this position.
    */
    function getLPs(
        uint256 tokenId,
        uint256 index
    ) external view returns (uint256 lps);

    /**
     *  @notice Returns an array of bucket indexes in which an NFT has liquidity.
     *  @dev    Potentially includes buckets that have been bankrupted.
     *  @param  tokenId  Unique ID of token.
     *  @return Array of bucket indexes.
    */
    function getPositionIndexes(
        uint256 tokenId
    ) external view returns (uint256[] memory);

    /**
     *  @notice Returns an array of bucket indexes in which an NFT has liquidity, with bankrupt buckets removed.
     *  @param  tokenId  Unique ID of token.
     *  @return Array of bucket indexes filtered for active liquidity.
    */
    function getPositionIndexesFiltered(
        uint256 tokenId
    ) external view returns (uint256[] memory);

    /**
     *  @notice Returns information about a given NFT.
     *  @param  tokenId_ Unique ID of token.
     *  @param  index_   Bucket index to check for position information.
     *  @return lps in that bucket.
     *  @return position's deposit time.
    */
    function getPositionInfo(
        uint256 tokenId_,
        uint256 index_
    ) external view returns (uint256, uint256);


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

    /**
     *  @notice Checks if a tokenId has a position in a bucket that was bankrupted.
     *  @param  tokenId_           Unique ID of token.
     *  @param  index_             Index of bucket to check for bankruptcy.
     *  @return isBankrupt_        True if the position in the bucket was bankrupted.
    */
    function isPositionBucketBankrupt(
        uint256 tokenId_,
        uint256 index_
    ) external view returns (bool isBankrupt_);
}
