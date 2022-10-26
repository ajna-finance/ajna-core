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

    /**
     *  @notice Returns the token id of an NFT pledged by a borrower with a given index.
     *  @param  borrower The address of borrower that pledged the NFT.
     *  @param  nftIndex NFT index in borrower's pledged token ids array.
     *  @return tokenId Token id of the NFT.
     */
    function borrowerLockedNFTs(
        address borrower,
        uint256 nftIndex
    ) external view returns (uint256 tokenId);

    /**
     *  @notice Returns the token id of an NFT added in a given bucket.
     *  @param  index    The bucket index.
     *  @param  nftIndex NFT index in bucket's added token ids array.
     *  @return tokenId Token id of the NFT.
     */
    function bucketLockedNFTs(
        uint256 index,
        uint256 nftIndex
    ) external view returns (uint256 tokenId);
}