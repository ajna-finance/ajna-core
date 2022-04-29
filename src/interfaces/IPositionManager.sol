// SPDX-License-Identifier: MIT
pragma solidity 0.8.11;

interface IPositionManager {
    struct MintParams {
        address recipient;
        address pool;
    }

    struct MemorializePositionsParams {
        uint256 tokenId;
        address owner;
        address pool;
        uint256[] prices; // the array of price buckets with LP tokens to be tracked by a NFT
    }

    struct BurnParams {
        uint256 tokenId;
        address recipient;
        uint256 price;
    }

    struct IncreaseLiquidityParams {
        uint256 tokenId;
        address recipient;
        address pool;
        uint256 amount;
        uint256 price;
    }

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

    function mint(MintParams calldata params) external payable returns (uint256 tokenId);

    function memorializePositions(MemorializePositionsParams calldata params) external;

    function burn(BurnParams calldata params) external payable;

    function increaseLiquidity(IncreaseLiquidityParams calldata params) external payable;

    function decreaseLiquidity(DecreaseLiquidityParams calldata params) external payable;
}