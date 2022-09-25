// SPDX-License-Identifier: MIT
pragma solidity 0.8.14;

/**
 *  @title Ajna Position Manager
 *  @dev   TODO
 */
interface IPositionManager {

    /**************/
    /*** Events ***/
    /**************/

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
     *  @notice Emitted when liquidity of the pool was increased.
     *  @param  lender Lender address.
     *  @param  price  The price at quote tokens were added.
     */
    event DecreaseLiquidity(
        address indexed lender,
        uint256 indexed price
    );

    /**
     *  @notice Emitted when liquidity of the pool was increased.
     *  @param  lender Lender address.
     *  @param  price  The price at quote tokens were added.
     */
    event DecreaseLiquidityNFT(
        address indexed lender,
        uint256 indexed price
    );

    /**
     *  @notice Emitted when liquidity of the pool was increased.
     *  @param  lender Lender address.
     *  @param  price  The price at quote tokens were added.
     *  @param  amount The amount of quote tokens added to the pool.
     */
    event IncreaseLiquidity(
        address indexed lender,
        uint256 indexed price,
        uint256 amount
    );

    /**
     *  @notice Emitted when existing positions were memorialized for a given NFT.
     *  @param  tokenId The tokenId of the NFT.
     */
    event MemorializePosition(
        address indexed lender,
        uint256 tokenId
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
     *  @notice Emitted when a position's liquidity is moved between prices.
     *  @param  lender  Lender address.
     *  @param  tokenId The tokenId of the newly minted NFT.
     */
    event MoveLiquidity(
        address indexed lender,
        uint256 tokenId
    );

    /**
     *  @notice Emitted when existing positions were redeemed for a given NFT.
     *  @param  tokenId The tokenId of the NFT.
     */
    event RedeemPosition(
        address indexed lender_,
        uint256 tokenId
    );

    /***************/
    /*** Structs ***/
    /***************/

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
     *  @notice Struct holding parameters for constructing the NFT token URI.
     *  @param  tokenId The tokenId of the NFT.
     *  @param  pool    The pool address.
     *  @param  indexes The array of price buckets index with LP tokens to be tracked by the NFT.
     */
    struct ConstructTokenURIParams {
        uint256 tokenId;
        address pool;
        uint256[] indexes;
    }

    /**
     *  @notice Struct holding parameters for tracking positions.
     *  @param  tokenId The tokenId of the NFT.
     *  @param  owner   The NFT owner address.
     *  @param  indexes The array of price buckets index with LP tokens to be tracked by a NFT.
     */
    struct MemorializePositionsParams {
        uint256 tokenId;
        address owner;
        uint256[] indexes;
    }

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
     *  @notice Struct holding parameters for moving the liquidity of a position.
     *  @param  owner     The NFT owner address.
     *  @param  tokenId   The tokenId of the NFT.
     *  @param  pool      The pool address to move quote tokens.
     *  @param  fromIndex The price bucket index from which liquidity should be moved.
     *  @param  toIndex   The price bucket index to which liquidity should be moved.
     */
    struct MoveLiquidityParams {
        address owner;
        uint256 tokenId;
        address pool;
        uint256 fromIndex;
        uint256 toIndex;
    }

    /**
     *  @notice Struct holding parameters for tracking positions.
     *  @param  tokenId The tokenId of the NFT.
     *  @param  owner   The NFT owner address.
     *  @param  pool    The pool address to reedem positions.
     *  @param  indexes The array of price buckets index with LP tokens to be tracked by a NFT.
     */
    struct RedeemPositionsParams {
        address owner;
        uint256 tokenId;
        address pool;
        uint256[] indexes;
    }

    /************************/
    /*** Owner Functions ***/
    /************************/

    /**
     *  @notice Called by owners to burn an existing NFT.
     *  @dev    Requires that all lp tokens have been removed from the NFT prior to calling.
     *  @param  params Calldata struct supplying inputs required to update the underlying assets owed to an NFT.
     */
    function burn(
        BurnParams calldata params
    ) external payable;

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
     *  @notice Called by owners to add quote tokens and receive a representative NFT.
     *  @param  params  Calldata struct supplying inputs required to mint a position NFT.
     *  @return tokenId The tokenId of the newly minted NFT.
     */
    function mint(
        MintParams calldata params
    ) external payable returns (uint256 tokenId);

    /**
     *  @notice Called by owners to move liquidity between two price buckets.
     *  @param  params  Calldata struct supplying inputs required to move liquidity tokens.
     */
    function moveLiquidity(
        MoveLiquidityParams calldata params
    ) external;

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


    /**********************/
    /*** View Functions ***/
    /**********************/

    /**
     *  @notice Returns the lpTokens accrued to a given tokenId, price pairing.
     *  @dev    Nested mappings aren't returned normally as part of the default getter for a mapping.
     *  @param  tokenId  Unique ID of token.
     *  @param  index    Index of price bucket to check LP balance of.
     *  @return lpTokens Balance of lpTokens in the price bucket for this position.
    */
    function getLPTokens(
        uint256 tokenId,
        uint256 index
    ) external view returns (uint256 lpTokens);

    /**
     *  @notice Checks if a given tokenId has a given position price
     *  @param  tokenId          Unique ID of token.
     *  @param  index            Index of price bucket to check if in position prices.
     *  @return priceInPostition True if tokenId has the position price
    */
    function isIndexInPosition(
        uint256 tokenId,
        uint256 index
    ) external view returns (bool priceInPostition);

}
