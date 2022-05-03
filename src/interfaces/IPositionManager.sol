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

    function mint(MintParams calldata params_) external payable returns (uint256 tokenId_);

    struct MintParams {
        address recipient;
        address pool;
    }

    function memorializePositions(MemorializePositionsParams calldata params_) external;

    struct MemorializePositionsParams {
        uint256 tokenId;
        address owner;
        address pool;
        uint256[] prices; // the array of price buckets with LP tokens to be tracked by a NFT
    }

    function burn(BurnParams calldata params_) external payable;

    struct BurnParams {
        uint256 tokenId;
        address recipient;
        uint256 price;
    }

    function increaseLiquidity(IncreaseLiquidityParams calldata params_) external payable;

    struct IncreaseLiquidityParams {
        uint256 tokenId;
        address recipient;
        address pool;
        uint256 amount;
        uint256 price;
    }

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
