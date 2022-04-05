// SPDX-License-Identifier: MIT
pragma solidity 0.8.11;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {console} from "@hardhat/hardhat-core/console.sol"; // TESTING ONLY

import {PositionNFT} from "./PositionNFT.sol";
import {IPool} from "./ERC20Pool.sol";

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

    function mint(MintParams calldata params)
        external
        payable
        returns (uint256 tokenId);

    function memorializePositions(MemorializePositionsParams calldata params)
        external;

    function burn(BurnParams calldata params) external payable;

    function increaseLiquidity(IncreaseLiquidityParams calldata params)
        external
        payable;

    function decreaseLiquidity(DecreaseLiquidityParams calldata params)
        external
        payable;
}

contract PositionManager is IPositionManager, PositionNFT {
    event Mint(address lender, address pool, uint256 tokenId);
    event MemorializePosition(address lender, uint256 tokenId);
    event Burn(address lender, uint256 price);
    event IncreaseLiquidity(address lender, uint256 amount, uint256 price);
    event DecreaseLiquidity(
        address lender,
        uint256 collateral,
        uint256 quote,
        uint256 price
    );

    constructor() PositionNFT("Ajna Positions NFT-V1", "AJNA-V1-POS", "1") {}

    /// @dev Mapping of tokenIds to Position struct
    mapping(uint256 => Position) public positions;

    /// @dev Details about Ajna positions - used by Lenders interacting through PositionManager instead of directly with the Pool
    struct Position {
        address owner; // owner of a position
        address pool; // address of the pool contract the position is associated to
        mapping(uint256 => uint256) lpTokens; // priceIndex => lpTokens
    }

    /// @dev The ID of the next token that will be minted. Skips 0
    uint176 private _nextId = 1;

    modifier isAuthorizedForToken(uint256 tokenId) {
        require(_isApprovedOrOwner(msg.sender, tokenId), "ajna/not-approved");
        _;
    }

    function tokenURI(uint256 tokenId)
        public
        view
        override(ERC721)
        returns (string memory)
    {
        require(_exists(tokenId));

        // get position information for the given token
        Position storage position = positions[tokenId];

        // TODO: access the prices at which a tokenId has added liquidity
        uint256[] memory prices;

        ConstructTokenURIParams memory params = ConstructTokenURIParams(
            tokenId,
            position.pool,
            prices
        );

        return constructTokenURI(params);
    }

    /// @notice Called by lenders to add quote tokens and receive a representative NFT
    /// @param params Calldata struct supplying inputs required to add quote tokens, and receive the NFT
    /// @return tokenId The tokenId of the newly minted NFT
    function mint(MintParams calldata params)
        external
        payable
        returns (uint256 tokenId)
    {
        _safeMint(params.recipient, (tokenId = _nextId++));

        // create a new position associated with the newly minted tokenId
        Position storage position = positions[tokenId];
        position.pool = params.pool;

        emit Mint(params.recipient, params.pool, tokenId);
        return tokenId;
    }

    /// @notice Called to memorialize existing positions with a given NFT
    /// @dev The array of price is expected to be constructed off chain by scanning events for that lender
    /// @dev The NFT must have already been created, and only TODO: (X) prices can be memorialized at a time
    /// @param params Calldata struct supplying inputs required to conduct the memorialization
    function memorializePositions(MemorializePositionsParams calldata params)
        external
    {
        Position storage position = positions[params.tokenId];

        for (uint256 i = 0; i < params.prices.length; i++) {
            position.lpTokens[params.prices[i]] = IPool(params.pool)
                .getLPTokenBalance(params.owner, params.prices[i]);
        }

        emit MemorializePosition(params.owner, params.tokenId);
    }

    // TODO: add support for ERC721Burnable?
    /// @notice Called by lenders to burn an existing NFT
    /// @dev Requires that all lp tokens have been removed from the NFT prior to calling
    /// @param params Calldata struct supplying inputs required to update the underlying assets owed to an NFT
    function burn(BurnParams calldata params)
        external
        payable
        isAuthorizedForToken(params.tokenId)
    {
        Position storage position = positions[params.tokenId];
        require(
            position.lpTokens[params.price] == 0,
            "ajna/liquidity-not-removed"
        );
        emit Burn(msg.sender, params.price);
        delete positions[params.tokenId];
    }

    /// @notice Called by lenders to add liquidity to an existing position
    /// @param params Calldata struct supplying inputs required to update the underlying assets owed to an NFT
    function increaseLiquidity(IncreaseLiquidityParams calldata params)
        external
        payable
        isAuthorizedForToken(params.tokenId)
    {
        Position storage position = positions[params.tokenId];

        // call out to pool contract to add quote tokens
        uint256 lpTokensAdded = IPool(params.pool).addQuoteToken(
            params.recipient,
            params.amount,
            params.price
        );
        require(lpTokensAdded != 0, "ajna/increase-liquidity-failed");

        // update position with newly added lp shares
        position.lpTokens[params.price] += lpTokensAdded;

        emit IncreaseLiquidity(params.recipient, params.amount, params.price);
    }

    /// @notice Called by lenders to remove liquidity from an existing position
    /// @param params Calldata struct supplying inputs required to update the underlying assets owed to an NFT
    function decreaseLiquidity(DecreaseLiquidityParams calldata params)
        external
        payable
        isAuthorizedForToken(params.tokenId)
    {
        Position storage position = positions[params.tokenId];

        IPool pool = IPool(params.pool);

        // calulate equivalent underlying assets for given lpTokens
        (uint256 collateralToRemove, uint256 quoteTokenToRemove) = pool
            .getLPTokenExchangeValue(params.lpTokens, params.price);

        pool.removeQuoteToken(
            params.recipient,
            quoteTokenToRemove,
            params.price
        );

        // enable lenders to remove quote token from a bucket that no debt is added to
        if (collateralToRemove != 0) {
            // claim any unencumbered collateral accrued to the price bucket
            pool.claimCollateral(
                params.recipient,
                collateralToRemove,
                params.price
            );
        }

        // update position with newly removed lp shares
        position.lpTokens[params.price] -= params.lpTokens;

        // TODO: check if price updates

        emit DecreaseLiquidity(
            params.recipient,
            collateralToRemove,
            quoteTokenToRemove,
            params.price
        );
    }

    /// @notice Override ERC721 afterTokenTransfer hook to ensure that transferred NFT's are properly tracked within the PositionManager data struct
    /// @dev This call also executes upon Mint
    function _afterTokenTransfer(
        address from,
        address to,
        uint256 tokenId
    ) internal virtual override(ERC721) {
        Position storage position = positions[tokenId];
        position.owner = to;
    }

    // -------------------- Position State View functions --------------------

    /// @notice Returns the lpTokens accrued to a given tokenId, price pairing
    /// @dev Nested mappings aren't returned normally as part of the default getter for a mapping
    function getLPTokens(uint256 tokenId, uint256 price)
        external
        view
        returns (uint256 lpTokens)
    {
        return positions[tokenId].lpTokens[price];
    }

    /// @notice Called to determine the amount of quote and collateral tokens, in quote terms, represented by a given tokenId
    /// @return quoteTokens The value of a NFT in terms of the pools quote token
    function getPositionValueInQuoteTokens(uint256 tokenId, uint256 price)
        external
        view
        returns (uint256 quoteTokens)
    {
        Position storage position = positions[tokenId];

        uint256 lpTokens = position.lpTokens[price];

        (uint256 collateral, uint256 quote) = IPool(position.pool)
            .getLPTokenExchangeValue(lpTokens, price);

        return quote + (collateral * price);
    }
}
