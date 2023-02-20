// SPDX-License-Identifier: MIT

pragma solidity 0.8.14;

/**
 * @title Positions Manager Events
 */
interface IPositionManagerEvents {

    /**
     *  @notice Emitted when an existing NFT was burned.
     *  @param  lender  Lender address.
     *  @param  tokenId The token id of the NFT that was burned.
     */
    event Burn(
        address indexed lender,
        uint256 indexed tokenId
    );

    /**
     *  @notice Emitted when existing positions were tracked for a given NFT.
     *  @param  tokenId The tokenId of the NFT.
     */
    event TrackPositions(
        address indexed lender,
        uint256 tokenId,
        uint256[] indexes
    );

    /**
     *  @notice Emitted when representative NFT minted.
     *  @param  lender  Lender address.
     *  @param  pool    Pool address.
     *  @param  tokenId The tokenId of the newly minted NFT.
     */
    event Mint(
        address indexed lender,
        address indexed pool,
        uint256 tokenId
    );

    /**
     *  @notice Emitted when a position's liquidity is moved between buckets.
     *  @param  lender  Lender address.
     *  @param  tokenId The tokenId of the newly minted NFT.
     */
    event MoveLiquidity(
        address indexed lender,
        uint256 tokenId
    );

    /**
     *  @notice Emitted when existing positions were untracked for a given NFT.
     *  @param  tokenId The tokenId of the NFT.
     */
    event UntrackPositions(
        address indexed lender,
        uint256 tokenId,
        uint256[] indexes
    );
}