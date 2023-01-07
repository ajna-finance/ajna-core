// SPDX-License-Identifier: MIT

pragma solidity 0.8.14;

/**
 * @title Positions Manager Owner Actions
 */
interface IPositionManagerOwnerActions {

    /**
     *  @notice Called by owners to burn an existing NFT.
     *  @dev    Requires that all lp tokens have been removed from the NFT prior to calling.
     *  @param  params Calldata struct supplying inputs required to update the underlying assets owed to an NFT.
     */
    function burn(
        BurnParams calldata params
    ) external;

    /**
     *  @notice Called to memorialize existing positions with a given NFT.
     *  @dev    The array of buckets is expected to be constructed off chain by scanning events for that lender.
     *  @dev    The NFT must have already been created, and the number of buckets to be memorialized at a time determined by function caller.
     *  @dev    An additional call is made to the pool to transfer the LP tokens from their previous owner, to the Position Manager.
     *  @dev    Pool.setPositionOwner() must be called prior to calling this method.
     *  @param  params Calldata struct supplying inputs required to conduct the memorialization.
     */
    function memorializePositions(
        MemorializePositionsParams calldata params
    ) external;

    /**
     *  @notice Called by owners to add quote tokens and receive a representative NFT.
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
     *  @notice Called to reedem existing positions with a given NFT.
     *  @dev    The array of buckets is expected to be constructed off chain by scanning events for that lender.
     *  @dev    The NFT must have already been created, and the number of buckets to be memorialized at a time determined by function caller.
     *  @dev    An additional call is made to the pool to transfer the LP tokens Position Manager to owner.
     *  @dev    Pool.setPositionOwner() must be called prior to calling this method.
     *  @param  params Calldata struct supplying inputs required to conduct the redeem.
     */
    function reedemPositions(
        RedeemPositionsParams calldata params
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
    struct MemorializePositionsParams {
        uint256   tokenId; // The tokenId of the positions NFT
        uint256[] indexes; // The array of bucket indexes to memorialize positions
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
    }

    /**
     *  @notice Struct holding parameters for tracking positions.
     */
    struct RedeemPositionsParams {
        uint256   tokenId; // The tokenId of the positions NFT
        address   pool;    // The pool address associated with positions NFT
        uint256[] indexes; // The array of bucket indexes to reedem positions for
    }
}