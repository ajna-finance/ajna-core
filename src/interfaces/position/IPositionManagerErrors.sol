// SPDX-License-Identifier: MIT

pragma solidity 0.8.14;

/**
 * @title Positions Manager Errors
 */
interface IPositionManagerErrors {

    /**
     * @notice User attempting to track a pool position that is already tracked by a position NFT.
     */
    error PositionAlreadyTracked();

    /**
     * @notice User attempting to burn a LPB NFT before untracking position.
     */
    error PositionNotUntracked();

    /**
     * @notice User not authorized to interact with the specified NFT.
     */
    error NoAuth();

    /**
     * @notice User attempted to mint an NFT pointing to a pool that wasn't deployed by an Ajna factory.
     */
    error NotAjnaPool();

    /**
     * @notice User attempted to track a position index that doesn't allow contract as manager.
     */
    error NotLPsManager();

    /**
     * @notice User failed to untrack liquidity in an index from their NFT.
     */
    error UntrackPositionFailed();

    /**
     * @notice User attempting to interact with a pool that doesn't match the pool associated with the tokenId.
     */
    error WrongPool();
}