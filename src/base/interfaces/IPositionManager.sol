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
     *  @param  lender_ Lender address.
     *  @param  price_  The bucket price corresponding to NFT that was burned.
     */
    event Burn(address indexed lender_, uint256 indexed price_);

    /**
     *  @notice Emitted when liquidity of the pool was increased.
     *  @param  lender_     Lender address.
     *  @param  price_      The price at quote tokens were added.
     */
    event DecreaseLiquidity(address indexed lender_, uint256 indexed price_);

    /**
     *  @notice Emitted when liquidity of the pool was increased.
     *  @param  lender_     Lender address.
     *  @param  price_      The price at quote tokens were added.
     */
    event DecreaseLiquidityNFT(address indexed lender_, uint256 indexed price_);

    /**
     *  @notice Emitted when liquidity of the pool was increased.
     *  @param  lender_ Lender address.
     *  @param  price_  The price at quote tokens were added.
     *  @param  amount_ The amount of quote tokens added to the pool.
     */
    event IncreaseLiquidity(address indexed lender_, uint256 indexed price_, uint256 amount_);

    /**
     *  @notice Emitted when existing positions were memorialized for a given NFT.
     *  @param  tokenId_ The tokenId of the NFT.
     */
    event MemorializePosition(address indexed lender_, uint256 tokenId_);

    /**
     *  @notice Emitted when representative NFT minted.
     *  @param  lender_  Lender address.
     *  @param  pool_    Pool address.
     *  @param  tokenId_ The tokenId of the newly minted NFT.
     */
    event Mint(address indexed lender_, address indexed pool_, uint256 tokenId_);

    /**
     *  @notice Emitted when a position's liquidity is moved between prices.
     *  @param  lender_  Lender address.
     *  @param  tokenId_ The tokenId of the newly minted NFT.
     */
    event MoveLiquidity(address indexed lender_, uint256 tokenId_);

    /***************/
    /*** Structs ***/
    /***************/

    /**
     *  @notice Struct holding parameters for burning an NFT.
     *  @param  tokenId   The tokenId of the NFT to burn.
     *  @param  recipient The NFT owner address.
     *  @param  index     The price bucket index.
     *  @param  pool      The pool address to burn the token from.
     */
    struct BurnParams {
        uint256 tokenId;
        address recipient;
        uint256 index;
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
     *  @notice Struct holding parameters for decreasing liquidity.
     *  @param  tokenId   The tokenId of the NFT to burn.
     *  @param  recipient The NFT owner address.
     *  @param  pool      The pool address to remove quote tokens from.
     *  @param  index     The price bucket index from where liquidity should be removed.
     *  @param  lpTokens  The number of LP tokens to use.
     */
    struct DecreaseLiquidityParams {
        uint256 tokenId;
        address recipient;
        address pool;
        uint256 index;
        uint256 lpTokens;
    }

    /**
     *  @notice Struct holding parameters for decreasing liquidity.
     *  @param  tokenId   The tokenId of the NFT to burn.
     *  @param  recipient The NFT owner address.
     *  @param  pool      The pool address to remove quote tokens from.
     *  @param  index     The price bucket index from where liquidity should be removed.
     *  @param  lpTokens  The number of LP tokens to use.
     *  @param  lpTokens  The number of LP tokens to use.

     */
    struct DecreaseLiquidityNFTParams {
        uint256 tokenId;
        address recipient;
        address pool;
        uint256 index;
        uint256 lpTokens;
        uint256[] tokenIdsToRemove;
    }

    /**
     *  @notice Struct holding parameters for increasing liquidity.
     *  @param  tokenId   The tokenId of the NFT tracking liquidity.
     *  @param  recipient The NFT owner address.
     *  @param  pool      The pool address to deposit quote tokens.
     *  @param  amount    The amount of quote tokens to be added to the pool.
     *  @param  index     The price bucket index where liquidity should be added.
     */
    struct IncreaseLiquidityParams {
        uint256 tokenId;
        address recipient;
        address pool;
        uint256 amount;
        uint256 index;
    }

    /**
     *  @notice Struct holding parameters for memorializing positions.
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
     *  @notice Struct holding position info.
     *  @param  nonce    Nonce used for permits.
     *  @param  owner    Address of owner of the position.
     *  @param  lpTokens Mapping of price to lpTokens for the owner.
     */
    struct Position {
        uint96 nonce;
        address owner;
        address pool;
        mapping(uint256 => uint256) lpTokens;
    }

    /************************/
    /*** Lender Functions ***/
    /************************/

    /**
     *  @notice Called by lenders to burn an existing NFT.
     *  @dev    Requires that all lp tokens have been removed from the NFT prior to calling.
     *  @param  params_ Calldata struct supplying inputs required to update the underlying assets owed to an NFT.
     */
    function burn(BurnParams calldata params_) external payable;

    /**
     *  @notice Called by lenders to remove liquidity from an existing position.
     *  @dev    Called to operate on an ERC20 type pool.
     *  @param  params_ Calldata struct supplying inputs required to update the underlying assets owed to an NFT.
     */
    function decreaseLiquidity(DecreaseLiquidityParams calldata params_) external payable;

    /**
     *  @notice Called by lenders to remove liquidity from an existing position.
     *  @dev    Called to operate on an ERC721 type pool.
     *  @param  params_ Calldata struct supplying inputs required to update the underlying assets owed to an NFT.
     */
    function decreaseLiquidityNFT(DecreaseLiquidityNFTParams calldata params_) external payable;

    /**
     *  @notice Called by lenders to add liquidity to an existing position.
     *  @param  params_ Calldata struct supplying inputs required to update the underlying assets owed to an NFT.
     */
    function increaseLiquidity(IncreaseLiquidityParams calldata params_) external payable;

    /**
     *  @notice Called to memorialize existing positions with a given NFT.
     *  @dev    The array of price is expected to be constructed off chain by scanning events for that lender.
     *  @dev    The NFT must have already been created, and only TODO: (X) prices can be memorialized at a time.
     *  @dev    An additional call is made to the pool to transfer the LP tokens from their previous owner, to the Position Manager.
     *  @dev    Pool.setPositionOwner() must be called prior to calling this method.
     *  @param  params_ Calldata struct supplying inputs required to conduct the memorialization.
     */
    function memorializePositions(MemorializePositionsParams calldata params_) external;

    /**
     *  @notice Called by lenders to add quote tokens and receive a representative NFT.
     *  @param  params_  Calldata struct supplying inputs required to mint a position NFT.
     *  @return tokenId_ The tokenId of the newly minted NFT.
     */
    function mint(MintParams calldata params_) external payable returns (uint256 tokenId_);

    /**
     *  @notice Called by lenders to move liquidity between two price buckets.
     *  @param  params_  Calldata struct supplying inputs required to move liquidity tokens.
     */
    function moveLiquidity(MoveLiquidityParams calldata params_) external;


    /**********************/
    /*** View Functions ***/
    /**********************/

    /**
     *  @notice Returns the lpTokens accrued to a given tokenId, price pairing.
     *  @dev    Nested mappings aren't returned normally as part of the default getter for a mapping.
     *  @param  tokenId_  Unique ID of token.
     *  @param  index_    Index of price bucket to check LP balance of.
     *  @return lpTokens_ Balance of lpTokens in the price bucket for this position.
    */
    function getLPTokens(uint256 tokenId_, uint256 index_) external view returns (uint256 lpTokens_);

    /**
     *  @notice Checks if a given tokenId has a given position price
     *  @param  tokenId_          Unique ID of token.
     *  @param  index_            Index of price bucket to check if in position prices.
     *  @return priceInPostition_ True if tokenId has the position price
    */
    function isIndexInPosition(uint256 tokenId_, uint256 index_) external view returns (bool priceInPostition_);

}
