// SPDX-License-Identifier: MIT

pragma solidity 0.8.18;

/**
 * @title ERC721 Pool State
 */
interface IERC721PoolState {

    /**
     *  @notice Check if a token id is allowed as collateral in pool.
     *  @param  tokenId The token id to check.
     *  @return allowed `True` if token id is allowed in pool.
     */
    function tokenIdsAllowed(
        uint256 tokenId
    ) external view returns (bool allowed);

    /**
     *  @notice Returns the token id of an `NFT` pledged by a borrower with a given index.
     *  @param  borrower The address of borrower that pledged the `NFT`.
     *  @param  nftIndex `NFT` index in borrower's pledged token ids array.
     *  @return tokenId  Token id of the `NFT`.
     */
    function borrowerTokenIds(
        address borrower,
        uint256 nftIndex
    ) external view returns (uint256 tokenId);

    /**
     *  @notice Returns the token id of an `NFT` added in pool bucket (claimable from pool).
     *  @param  nftIndex `NFT` index in bucket's token ids array.
     *  @return tokenId  Token id of the `NFT`.
     */
    function bucketTokenIds(
        uint256 nftIndex
    ) external view returns (uint256 tokenId);

    /**
     *  @notice Returns the list of `NFT` tokenIds pledged by a borrower in a pool.
     *  @param  borrower_ The address of borrower that pledged the `NFT`s.
     *  @return List of `NFT`s pledged by borrower.
     */
    function getBorrowerTokenIds(address borrower_) external view returns(uint256[] memory);

    /**
     *  @notice Returns the list of `NFT` tokenIds added to pool buckets.
     *  @return List of `NFT`s that are claimable from the pool.
     */
    function getBucketTokenIds() external view returns(uint256[] memory);

}
