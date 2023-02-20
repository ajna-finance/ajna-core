// SPDX-License-Identifier: MIT

pragma solidity 0.8.14;

/**
 * @title Positions Manager Owner Actions
 */
interface IPositionManagerOwnerActions {

    /**
     *  @notice Called by owners to burn an existing NFT.
     *  @dev    Requires that all lps have been removed from the NFT prior to calling.
     *  @param  params Calldata struct supplying inputs required to update the underlying assets owed to an NFT.
     */
    function burn(
        BurnParams calldata params
    ) external;

    /**
     *  @notice Called to track existing positions with a given NFT.
     *  @dev    The array of buckets is expected to be constructed off chain by scanning events for that lender.
     *  @dev    When tracking position the owner gives full control of the entire LP deposit and won't be able to use LPs outside of position manager (only move actions).
     *  @dev    The NFT must have already been created, and the number of buckets to be tracked at a time determined by function caller.
     *  @param  params Calldata struct supplying inputs required to conduct the tracking positions.
     */
    function trackPositions(
        TrackPositionsParams calldata params
    ) external;

    /**
     *  @notice Called by owners to mint and receive an Ajna Position NFT.
     *  @dev    PositionNFTs can only be minited with an association to pools that have been deployed by the Ajna ERC20PoolFactory or ERC721PoolFactory.
     *  @param  params  Calldata struct supplying inputs required to mint a positions NFT.
     *  @return tokenId The tokenId of the newly minted NFT.
     */
    function mint(
        MintParams calldata params
    ) external returns (uint256 tokenId);

    /**
     *  @notice Called by owners to move liquidity between two buckets.
     *  @param  params  Calldata struct supplying inputs required to move liquidity tokens.
     */
    function moveLiquidity(
        MoveLiquidityParams calldata params
    ) external;

    /**
     *  @notice Called to untrack existing positions for a given NFT.
     *  @dev    The array of buckets is expected to be constructed off chain by scanning events for that lender.
     *  @dev    The NFT must have already been created, and the number of buckets to be tracked at a time determined by function caller.
     *  @param  params Calldata struct supplying inputs required to conduct positions untrack.
     */
    function untrackPositions(
        UntrackPositionsParams calldata params
    ) external;

    /*********************/
    /*** Struct params ***/
    /*********************/

    /**
     *  @notice Struct holding parameters for burning an NFT.
     */
    struct BurnParams {
        uint256 tokenId; // The tokenId of the positions NFT to burn
        address pool;    // The pool address associated with burned positions NFT
    }

    /**
     *  @notice Struct holding parameters for tracking positions.
     */
    struct TrackPositionsParams {
        uint256   tokenId; // The tokenId of the positions NFT
        address   pool;    // The pool address associated with positions NFT
        uint256[] indexes; // The array of bucket indexes to track positions
    }

    /**
     *  @notice Struct holding mint parameters.
     */
    struct MintParams {
        address recipient;      // Lender address
        address pool;           // The pool address associated with minted positions NFT
        bytes32 poolSubsetHash; // Hash of pool information used to track pool in the factory after deployment
    }

    /**
     *  @notice Struct holding parameters for moving the liquidity of a position.
     */
    struct MoveLiquidityParams {
        uint256 tokenId;   // The tokenId of the positions NFT
        address pool;      // The pool address associated with positions NFT
        uint256 fromIndex; // The bucket index from which liquidity should be moved
        uint256 toIndex;   // The bucket index to which liquidity should be moved
        uint256 expiry;    // Timestamp after which this TX will revert, preventing inclusion in a block with unfavorable price
    }

    /**
     *  @notice Struct holding parameters for tracking positions.
     */
    struct UntrackPositionsParams {
        uint256   tokenId; // The tokenId of the positions NFT
        address   pool;    // The pool address associated with positions NFT
        uint256[] indexes; // The array of bucket indexes to untrack positions for
    }
}
