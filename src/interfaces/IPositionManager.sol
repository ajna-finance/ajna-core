// SPDX-License-Identifier: MIT
pragma solidity 0.8.11;

interface IPositionManager {

    /**
     * @notice Emitted when representative NFT minted
     * @param lender lender address
     * @param pool pool address
     * @param tokenId the tokenId of the newly minted NFT
    */
    event Mint(address lender, address pool, uint256 tokenId);

    /**
     * @notice Emitted when existing positions were memorialized for a given NFT
     * @param tokenId the tokenId of the NFT
    */
    event MemorializePosition(address lender, uint256 tokenId);

    /**
     * @notice Emitted when an existing NFT was burned
     * @param lender lender address
     * @param price the bucket price corresponding to NFT that was burned
    */
    event Burn(address lender, uint256 price);

    /**
     * @notice Emitted when liquidity of the pool was increased
     * @param lender lender address
     * @param amount the amount of quote tokens added to the pool
     * @param price the price at quote tokens were added
    */
    event IncreaseLiquidity(address lender, uint256 amount, uint256 price);

    /**
     * @notice Emitted when liquidity of the pool was increased
     * @param lender lender address
     * @param collateral the amount of collateral removed from the pool
     * @param quote the amount of quote tokens removed from the pool
     * @param price the price at quote tokens were added
    */
    event DecreaseLiquidity(address lender, uint256 collateral, uint256 quote, uint256 price);

    /** @notice Caller is not approved to interact with the token */
    error NotApproved();

    /** @notice increaseLiquidity() call failed */
    error IncreaseLiquidityFailed();

    /** @notice Unable to burn as liquidity still present at price */
    error LiquidityNotRemoved();

    /**
     * @notice Called by lenders to add quote tokens and receive a representative NFT
     * @param params_ Calldata struct supplying inputs required to add quote tokens, and receive the NFT
     * @return tokenId_ The tokenId of the newly minted NFT
    */
    function mint(MintParams calldata params_) external payable returns (uint256 tokenId_);

    /**
     * @notice struct holding mint parameters
     * @param recipient / lender address
     * @param pool address
    */
    struct MintParams {
        address recipient;
        address pool;
    }

    /**
     * @notice Called to memorialize existing positions with a given NFT
     * @dev The array of price is expected to be constructed off chain by scanning events for that lender
     * @dev The NFT must have already been created, and only TODO: (X) prices can be memorialized at a time
     * @param params_ Calldata struct supplying inputs required to conduct the memorialization
    */
    function memorializePositions(MemorializePositionsParams calldata params_) external;

    /**
     * @notice struct holding parameters for memorializing positions
     * @param tokenId the tokenId of the NFT
     * @param owner the NFT owner address
     * @param pool the pool address
     * @param prices the array of price buckets with LP tokens to be tracked by a NFT
    */
    struct MemorializePositionsParams {
        uint256 tokenId;
        address owner;
        address pool;
        uint256[] prices;
    }

    /**
     * @notice Called by lenders to burn an existing NFT
     * @dev Requires that all lp tokens have been removed from the NFT prior to calling
     * @param params_ Calldata struct supplying inputs required to update the underlying assets owed to an NFT
    */
    function burn(BurnParams calldata params_) external payable;

    /**
     * @notice struct holding parameters for burning an NFT
     * @param tokenId the tokenId of the NFT to burn
     * @param recipient the NFT owner address
     * @param price the bucket price
    */
    struct BurnParams {
        uint256 tokenId;
        address recipient;
        uint256 price;
    }

    /**
     * @notice Called by lenders to add liquidity to an existing position
     * @param params_ Calldata struct supplying inputs required to update the underlying assets owed to an NFT
    */
    function increaseLiquidity(IncreaseLiquidityParams calldata params_) external payable;

    /**
     * @notice struct holding parameters for increasing liquidity
     * @param tokenId the tokenId of the NFT tracking liquidity
     * @param recipient the NFT owner address
     * @param pool the pool address to deposit quote tokens
     * @param amount the amount of quote tokens to be added to the pool
     * @param price the bucket price where liquidity should be added
    */
    struct IncreaseLiquidityParams {
        uint256 tokenId;
        address recipient;
        address pool;
        uint256 amount;
        uint256 price;
    }

    /**
     * @notice Called by lenders to remove liquidity from an existing position
     * @param params_ Calldata struct supplying inputs required to update the underlying assets owed to an NFT
    */
    function decreaseLiquidity(DecreaseLiquidityParams calldata params_) external payable;

    /**
     * @notice struct holding parameters for decreasing liquidity
     * @param tokenId the tokenId of the NFT to burn
     * @param recipient the NFT owner address
     * @param pool the pool address to remove quote tokens from
     * @param price the bucket price from where liquidity should be removed
     * @param lpTokens the number of LP tokens to use
    */
    struct DecreaseLiquidityParams {
        uint256 tokenId;
        address recipient;
        address pool;
        uint256 price;
        uint256 lpTokens;
    }

    /**
     * @notice struct holding parameters for constructing the NFT token URI
     * @param tokenId the tokenId of the NFT
     * @param pool the pool address
     * @param prices the array of price buckets with LP tokens to be tracked by the NFT
    */
    struct ConstructTokenURIParams {
        uint256 tokenId;
        address pool;
        uint256[] prices;
    }

}
