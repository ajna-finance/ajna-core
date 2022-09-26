// SPDX-License-Identifier: MIT
pragma solidity 0.8.14;

/**
 * @title Ajna Positions Manager Owner Actions
 */
interface IPositionManagerOwnerActions {

    /**
     *  @notice Struct holding parameters for constructing the NFT token URI.
     *  @param  indexes The array of price buckets index with LP tokens to be tracked by the NFT.
     *  @param  tokenId The tokenId of the NFT.
     *  @param  pool    The pool address.
     */
    struct ConstructTokenURIParams {
        uint256[] indexes;
        uint256 tokenId;
        address pool;
    }


    /**
     *  @notice Struct holding parameters for burning an NFT.
     *  @param  tokenId   The tokenId of the NFT to burn.
     *  @param  recipient The NFT owner address.
     *  @param  pool      The pool address to burn the token from.
     */
    struct BurnParams {
        uint256 tokenId;
        address recipient;
        address pool;
    }

    /**
     *  @notice Called by owners to burn an existing NFT.
     *  @dev    Requires that all lp tokens have been removed from the NFT prior to calling.
     *  @param  params Calldata struct supplying inputs required to update the underlying assets owed to an NFT.
     */
    function burn(
        BurnParams calldata params
    ) external payable;


    /**
     *  @notice Struct holding parameters for tracking positions.
     *  @param  indexes The array of price buckets index with LP tokens to be tracked by a NFT.
     *  @param  tokenId The tokenId of the NFT.
     *  @param  owner   The NFT owner address.
     */
    struct MemorializePositionsParams {
        uint256[] indexes;
        uint256 tokenId;
        address owner;
    }

    /**
     *  @notice Called to memorialize existing positions with a given NFT.
     *  @dev    The array of price is expected to be constructed off chain by scanning events for that lender.
     *  @dev    The NFT must have already been created, and only TODO: (X) prices can be memorialized at a time.
     *  @dev    An additional call is made to the pool to transfer the LP tokens from their previous owner, to the Position Manager.
     *  @dev    Pool.setPositionOwner() must be called prior to calling this method.
     *  @param  params Calldata struct supplying inputs required to conduct the memorialization.
     */
    function memorializePositions(
        MemorializePositionsParams calldata params
    ) external;


    /**
     *  @notice Struct holding mint parameters.
     *  @param  recipient Lender address.
     *  @param  pool      Pool address.
     */
    struct MintParams {
        address recipient;
        address pool;
    }

    /**
     *  @notice Called by owners to add quote tokens and receive a representative NFT.
     *  @param  params  Calldata struct supplying inputs required to mint a position NFT.
     *  @return tokenId The tokenId of the newly minted NFT.
     */
    function mint(
        MintParams calldata params
    ) external payable returns (uint256 tokenId);


    /**
     *  @notice Struct holding parameters for moving the liquidity of a position.
     *  @param  fromIndex The price bucket index from which liquidity should be moved.
     *  @param  toIndex   The price bucket index to which liquidity should be moved.
     *  @param  tokenId   The tokenId of the NFT.
     *  @param  owner     The NFT owner address.
     *  @param  pool      The pool address to move quote tokens.
     */
    struct MoveLiquidityParams {
        uint256 fromIndex;
        uint256 toIndex;
        uint256 tokenId;
        address owner;
        address pool;
    }

    /**
     *  @notice Called by owners to move liquidity between two price buckets.
     *  @param  params  Calldata struct supplying inputs required to move liquidity tokens.
     */
    function moveLiquidity(
        MoveLiquidityParams calldata params
    ) external;


    /**
     *  @notice Struct holding parameters for tracking positions.
     *  @param  indexes The array of price buckets index with LP tokens to be tracked by a NFT.
     *  @param  tokenId The tokenId of the NFT.
     *  @param  owner   The NFT owner address.
     *  @param  pool    The pool address to reedem positions.
     */
    struct RedeemPositionsParams {
        uint256[] indexes;
        uint256 tokenId;
        address owner;
        address pool;
    }

    /**
     *  @notice Called to reedem existing positions with a given NFT.
     *  @dev    The array of price is expected to be constructed off chain by scanning events for that lender.
     *  @dev    The NFT must have already been created, and only TODO: (X) prices can be redeemed at a time.
     *  @dev    An additional call is made to the pool to transfer the LP tokens Position Manager to owner.
     *  @dev    Pool.setPositionOwner() must be called prior to calling this method.
     *  @param  params Calldata struct supplying inputs required to conduct the redeem.
     */
    function reedemPositions(
        RedeemPositionsParams calldata params
    ) external;
}