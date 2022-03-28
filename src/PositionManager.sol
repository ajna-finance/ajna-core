// SPDX-License-Identifier: MIT
pragma solidity 0.8.11;

import {PositionNFT} from "./PositionNFT.sol";
import {IPool} from "./ERC20Pool.sol";

import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "../lib/hardhat/packages/hardhat-core/console.sol";

interface IPositionManager {
    struct MintParams {
        address recipient;
        address pool;
        uint256 amount;
        uint256 price;
    }

    struct IncreaseLiquidityParams {
        uint256 tokenId;
        address recipient; // TODO: potentially remove in favor of msg.sender
        address pool;
        uint256 amount;
        uint256 price;
    }

    struct DecreaseLiquidityParams {
        uint256 tokenId;
        address recipient; // TODO: potentially remove in favor of msg.sender
        address pool;
        uint256 price;
        uint256 lpTokens;
    }

    function mint(MintParams calldata params)
        external
        payable
        returns (uint256 tokenId);

    function burn(uint256 tokenId) external payable;

    function increaseLiquidity(IncreaseLiquidityParams calldata params)
        external
        payable;

    function decreaseLiquidity(DecreaseLiquidityParams calldata params)
        external
        payable;

}

contract PositionManager is IPositionManager, PositionNFT, IERC721Receiver {
    event Mint(address lender, uint256 amount, uint256 price);
    event Burn(address lender, uint256 price);
    event IncreaseLiquidity(address lender, uint256 amount, uint256 price);
    event DecreaseLiquidity(address lender, uint256 collateral, uint256 quote, uint256 price);

    constructor() PositionNFT("Ajna Positions NFT-V1", "AJNA-V1-POS", "1") {}

    /// @dev Mapping of tokenIds to Position information
    mapping(uint256 => Position) private positions;

    /// @dev The ID of the next token that will be minted. Skips 0
    uint176 private _nextId = 1;

    /// @dev Details about Ajna positions - used for both Borrowers and Lenders
    struct Position {
        address owner; // owner of a position
        uint256 price; // price bucket a position is associated with
        uint256 lpTokens; // tokens representing the share of a bucket owned by a position
        address pool; // address of the pool contract the position is associated to
    }

    // TODO: add the ability to mint across multiple price buckets?
    /// @notice Called by lenders to add quote tokens and receive a representative NFT
    /// @param params Calldata struct supplying inputs required to add quote tokens, and receive the NFT
    function mint(MintParams calldata params)
        external
        payable
        returns (uint256 tokenId)
    {
        address pool = params.pool;

        // call out to pool contract to add quote tokens
        uint256 lpTokensAdded = IPool(params.pool).addQuoteToken(
            params.recipient,
            params.amount,
            params.price
        );
        require(lpTokensAdded != 0, "No liquidity added");

        _safeMint(params.recipient, (tokenId = _nextId++));

        positions[tokenId] = Position(
            params.recipient,
            params.price,
            lpTokensAdded,
            params.pool
        );

        // TODO: update Mint() event to emit lp added
        emit Mint(params.recipient, params.amount, params.price);
        return tokenId;
    }

    // TODO: finish implementing
    function burn(uint256 tokenId) external payable {
        Position storage position = positions[tokenId];
        require(position.lpTokens == 0, "Not Redeemed");
        delete positions[tokenId];
        emit Burn(msg.sender, position.price);
    }

    /// @notice Called by lenders to add liquidity to an existing position
    /// @param params Calldata struct supplying inputs required to update the underlying assets owed to an NFT
    function increaseLiquidity(IncreaseLiquidityParams calldata params)
        external
        payable
    {
        Position storage position = positions[params.tokenId];

        uint256 lpTokensAdded = IPool(params.pool).addQuoteToken(
            params.recipient,
            params.amount,
            params.price
        );
        require(lpTokensAdded != 0, "No liquidity added");

        positions[params.tokenId].lpTokens += lpTokensAdded;

        // TODO: update collateral accrued accounting

        // TODO: update to position.liquidity
        // position.amount += params.amount;

        // TODO: check if price bucket changes at all from reallocation
        // position.price = returnedData.price;

        emit IncreaseLiquidity(params.recipient, params.amount, params.price);
    }

    // TODO: finish implementing -> what happens if liquidity goes to 0...
    // TODO: add multicall support here
    function decreaseLiquidity(DecreaseLiquidityParams calldata params)
        external
        payable
    {
        Position storage position = positions[params.tokenId];

        IPool pool = IPool(params.pool);

        // calulate equivalent underlying assets for given lpTokens
        (uint256 collateralToRemove, uint256 quoteTokenToRemove) = pool
            .getLPTokenExchangeValue(params.lpTokens, params.price);

        // TODO: update lp token equation with a minimum factor to avoid rounding issues and provide base
        pool.removeQuoteToken(
            params.recipient,
            quoteTokenToRemove,
            params.price
        );

        // require(quoteTokensRemoved != 0, "No quote tokens removed");

        // enable lenders to remove quote token from a bucket that no debt is added to
        if (collateralToRemove != 0) {
            // TODO: transfer collateral received to the recipient address
            pool.claimCollateral(collateralToRemove, params.price);
            // TODO: check that collateral was > 0
        }

        positions[params.tokenId].lpTokens -= params.lpTokens;

        // TODO: check if price updates

        // TOdO: update this to emit both the quote and collateral amounts claimed... OR lpTokens
        emit DecreaseLiquidity(params.recipient, collateralToRemove, quoteTokenToRemove, params.price);
    }

    // -------------------- Position State View functions --------------------

    // TODO: remove in favor of default getter?
    function getPosition(uint256 tokenId)
        public
        view
        returns (Position memory position)
    {
        Position memory position = positions[tokenId];
        return position;
    }

    // TODO: implement
    function getPositionOwnedCollateral(uint256 tokenId)
        public
        view
        returns (uint256 collateral)
    {}

    // TODO: implement
    function getPositionOwnedQuoteTokens(uint256 tokenId)
        public
        view
        returns (uint256 quoteTokens)
    {}

    // TODO: finish implementing to enable the reception of collateral tokens -> and/or does this need to be added to the pool?
    // https://forum.openzeppelin.com/t/erc721holder-ierc721receiver-and-onerc721received/11828
    function onERC721Received(
        address operator,
        address from,
        uint256 tokenId,
        bytes memory data
    ) external returns (bytes4) {}
}
