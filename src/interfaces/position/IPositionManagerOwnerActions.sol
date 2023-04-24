// SPDX-License-Identifier: MIT

pragma solidity 0.8.14;

/**
 * @title Positions Manager Owner Actions
 */
interface IPositionManagerOwnerActions {

    /**
     *  @notice Called by owners to burn an existing `NFT`.
     *  @dev    Requires that all `LP` have been removed from the `NFT `prior to calling.
     *  @param  params_ Calldata struct supplying inputs required to update the underlying assets owed to an `NFT`.
     */
    function burn(
        BurnParams calldata params_
    ) external;

    /**
     *  @notice Called to memorialize existing positions with a given NFT.
     *  @dev    The array of buckets is expected to be constructed off chain by scanning events for that lender.
     *  @dev    The NFT must have already been created, and the number of buckets to be memorialized at a time determined by function caller.
     *  @dev    An additional call is made to the pool to transfer the LP from their previous owner, to the Position Manager.
     *  @dev    `Pool.increaseLPAllowance` must be called prior to calling this method in order to allow Position manager contract to transfer LP to be memorialized.
     *  @param  params_ Calldata struct supplying inputs required to conduct the memorialization.
     */
    function memorializePositions(
        MemorializePositionsParams calldata params_
    ) external;

    /**
     *  @notice Called by owners to mint and receive an `Ajna` Position `NFT`.
     *  @dev    Position `NFT`s can only be minited with an association to pools that have been deployed by the `Ajna` `ERC20PoolFactory` or `ERC721PoolFactory`.
     *  @param  params_  Calldata struct supplying inputs required to mint a positions `NFT`.
     *  @return tokenId_ The `tokenId` of the newly minted `NFT`.
     */
    function mint(
        MintParams calldata params_
    ) external returns (uint256 tokenId_);

    /**
     *  @notice Called by owners to move liquidity between two buckets.
     *  @param  params_  Calldata struct supplying inputs required to move liquidity tokens.
     */
    function moveLiquidity(
        MoveLiquidityParams calldata params_
    ) external;

    /**
     *  @notice Called to reedem existing positions with a given `NFT`.
     *  @dev    The array of buckets is expected to be constructed off chain by scanning events for that lender.
     *  @dev    The `NFT` must have already been created, and the number of buckets to be memorialized at a time determined by function caller.
     *  @dev    An additional call is made to the pool to transfer the `LP` Position Manager to owner.
     *  @dev    `Pool.approveLPTransferors` must be called prior to calling this method in order to allow `Position manager` contract to transfer redeemed `LP`.
     *  @param  params_ Calldata struct supplying inputs required to conduct the redeem.
     */
    function reedemPositions(
        RedeemPositionsParams calldata params_
    ) external;

    /*********************/
    /*** Struct params ***/
    /*********************/

    /**
     *  @notice Struct holding parameters for burning an `NFT`.
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
        uint256 expiry;    // Timestamp after which this TX will revert, preventing inclusion in a block with unfavorable price
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
