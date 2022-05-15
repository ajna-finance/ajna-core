// SPDX-License-Identifier: MIT
pragma solidity 0.8.11;

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
    event Burn(address lender_, uint256 price_);

    /**
     *  @notice Emitted when liquidity of the pool was increased.
     *  @param  lender_     Lender address.
     *  @param  collateral_ The amount of collateral removed from the pool.
     *  @param  quote_      The amount of quote tokens removed from the pool.
     *  @param  price_      The price at quote tokens were added.
     */
    event DecreaseLiquidity(address lender_, uint256 collateral_, uint256 quote_, uint256 price_);

    /**
     *  @notice Emitted when liquidity of the pool was increased.
     *  @param  lender_ Lender address.
     *  @param  amount_ The amount of quote tokens added to the pool.
     *  @param  price_  The price at quote tokens were added.
     */
    event IncreaseLiquidity(address lender_, uint256 amount_, uint256 price_);

    /**
     *  @notice Emitted when existing positions were memorialized for a given NFT.
     *  @param  tokenId_ The tokenId of the NFT.
     */
    event MemorializePosition(address lender_, uint256 tokenId_);

    /**
     *  @notice Emitted when representative NFT minted.
     *  @param  lender_  Lender address.
     *  @param  pool_    Pool address.
     *  @param  tokenId_ The tokenId of the newly minted NFT.
     */
    event Mint(address lender_, address pool_, uint256 tokenId_);

    /*********************/
    /*** Custom Errors ***/
    /*********************/

    /**
     *  @notice `increaseLiquidity()` call failed.
     */
    error IncreaseLiquidityFailed();

    /**
     *  @notice Unable to burn as liquidity still present at price.
     */
    error LiquidityNotRemoved();

    /**
     *  @notice Caller is not approved to interact with the token.
     */
    error NotApproved();

    /***************/
    /*** Structs ***/
    /***************/

    /**
     *  @notice Struct holding parameters for burning an NFT.
     *  @param  tokenId   The tokenId of the NFT to burn.
     *  @param  recipient The NFT owner address.
     *  @param  price     The bucket price.
     */
    struct BurnParams {
        uint256 tokenId;
        address recipient;
        uint256 price;
    }

    /**
     *  @notice Struct holding parameters for constructing the NFT token URI.
     *  @param  tokenId The tokenId of the NFT.
     *  @param  pool    The pool address.
     *  @param  prices  The array of price buckets with LP tokens to be tracked by the NFT.
     */
    struct ConstructTokenURIParams {
        uint256 tokenId;
        address pool;
        uint256[] prices;
    }

    /**
     *  @notice Struct holding parameters for decreasing liquidity.
     *  @param  tokenId   The tokenId of the NFT to burn.
     *  @param  recipient The NFT owner address.
     *  @param  pool      The pool address to remove quote tokens from.
     *  @param  price     The bucket price from where liquidity should be removed.
     *  @param  lpTokens  The number of LP tokens to use.
     */
    struct DecreaseLiquidityParams {
        uint256 tokenId;
        address recipient;
        address pool;
        uint256 price;
        uint256 lpTokens;
    }

    /**
     *  @notice Struct holding parameters for increasing liquidity.
     *  @param  tokenId   The tokenId of the NFT tracking liquidity.
     *  @param  recipient The NFT owner address.
     *  @param  pool      The pool address to deposit quote tokens.
     *  @param  amount    The amount of quote tokens to be added to the pool.
     *  @param  price     The bucket price where liquidity should be added.
     */
    struct IncreaseLiquidityParams {
        uint256 tokenId;
        address recipient;
        address pool;
        uint256 amount;
        uint256 price;
    }

    /**
     *  @notice Struct holding parameters for memorializing positions.
     *  @param  tokenId The tokenId of the NFT.
     *  @param  owner   The NFT owner address.
     *  @param  pool    The pool address.
     *  @param  prices  The array of price buckets with LP tokens to be tracked by a NFT.
     */
    struct MemorializePositionsParams {
        uint256 tokenId;
        address owner;
        address pool;
        uint256[] prices;
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
     *  @param  params_ Calldata struct supplying inputs required to update the underlying assets owed to an NFT.
     */
    function decreaseLiquidity(DecreaseLiquidityParams calldata params_) external payable;

    /**
     *  @notice Called by lenders to add liquidity to an existing position.
     *  @param  params_ Calldata struct supplying inputs required to update the underlying assets owed to an NFT.
     */
    function increaseLiquidity(IncreaseLiquidityParams calldata params_) external payable;

    /**
     *  @notice Called to memorialize existing positions with a given NFT.
     *  @dev    The array of price is expected to be constructed off chain by scanning events for that lender.
     *  @dev    The NFT must have already been created, and only TODO: (X) prices can be memorialized at a time.
     *  @param  params_ Calldata struct supplying inputs required to conduct the memorialization.
     */
    function memorializePositions(MemorializePositionsParams calldata params_) external;

    /**
     *  @notice Called by lenders to add quote tokens and receive a representative NFT.
     *  @param  params_  Calldata struct supplying inputs required to add quote tokens, and receive the NFT.
     *  @return tokenId_ The tokenId of the newly minted NFT.
     */
    function mint(MintParams calldata params_) external payable returns (uint256 tokenId_);

    /**********************/
    /*** View Functions ***/
    /**********************/

    /**
     *  @notice Returns the lpTokens accrued to a given tokenId, price pairing.
     *  @dev    Nested mappings aren't returned normally as part of the default getter for a mapping.
     *  @param  tokenId_  Unique ID of token.
     *  @param  price_    Price of bucket to check LP balance of.
     *  @return lpTokens_ Balance of lpTokens in the price bucket for this position.
    */
    function getLPTokens(uint256 tokenId_, uint256 price_) external view returns (uint256 lpTokens_);

    /**
     *  @notice Called to determine the amount of quote and collateral tokens, in quote terms, represented by a given tokenId.
     *  @param  tokenId_      Unique ID of token.
     *  @param  price_        The price bucket to check the position value of.
     *  @return quoteTokens_ Value fo the LP tokens in the price bucket for this position, in quote token.
    */
    function getPositionValueInQuoteTokens(uint256 tokenId_, uint256 price_) external view returns (uint256 quoteTokens_);

    // TODO: Not sure how to make an interface for a function that returns a struct with a mapping.
    // function positions(uint256 tokenId_) external view returns ()

}
