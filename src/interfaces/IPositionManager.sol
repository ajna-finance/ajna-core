// SPDX-License-Identifier: MIT
pragma solidity 0.8.11;

interface IPositionManager {

    event Mint(address lender, address pool, uint256 tokenId);
    event MemorializePosition(address lender, uint256 tokenId);
    event Burn(address lender, uint256 price);
    event IncreaseLiquidity(address lender, uint256 amount, uint256 price);
    event DecreaseLiquidity(address lender, uint256 collateral, uint256 quote, uint256 price);

    /// @dev Caller is not approved to interact with the token
    error NotApproved();
    /// @dev increaseLiquidity() call failed
    error IncreaseLiquidityFailed();
    /// @dev Unable to burn as liquidity still present at price
    error LiquidityNotRemoved();

    /**
     * @notice Called by lenders to add quote tokens and receive a representative NFT
     * @param params_ Calldata struct supplying inputs required to add quote tokens, and receive the NFT
     * @return tokenId_ The tokenId of the newly minted NFT
    */
    function mint(MintParams calldata params_) external payable returns (uint256 tokenId_);

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

    struct MemorializePositionsParams {
        uint256 tokenId;
        address owner;
        address pool;
        uint256[] prices; // the array of price buckets with LP tokens to be tracked by a NFT
    }

    /**
     * @notice Called by lenders to burn an existing NFT
     * @dev Requires that all lp tokens have been removed from the NFT prior to calling
     * @param params_ Calldata struct supplying inputs required to update the underlying assets owed to an NFT
    */
    function burn(BurnParams calldata params_) external payable;

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

    struct DecreaseLiquidityParams {
        uint256 tokenId;
        address recipient;
        address pool;
        uint256 price;
        uint256 lpTokens;
    }

    struct ConstructTokenURIParams {
        uint256 tokenId;
        address pool;
        uint256[] prices;
    }

}
