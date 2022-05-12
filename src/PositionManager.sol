// SPDX-License-Identifier: MIT
pragma solidity 0.8.11;

import { ERC721 } from "@openzeppelin/contracts/token/ERC721/ERC721.sol";

import { Multicall }   from "./base/Multicall.sol";
import { PermitERC20 } from "./base/PermitERC20.sol";
import { PositionNFT } from "./base/PositionNFT.sol";

import { IPool }            from "./interfaces/IPool.sol";
import { IPositionManager } from "./interfaces/IPositionManager.sol";

import { Maths } from "./libraries/Maths.sol";

contract PositionManager is IPositionManager, Multicall, PositionNFT, PermitERC20 {

    constructor() PositionNFT("Ajna Positions NFT-V1", "AJNA-V1-POS", "1") {}

    /// @dev Mapping of tokenIds to Position struct
    mapping(uint256 => Position) public positions;

    /// @dev Details about Ajna positions - used by Lenders interacting through PositionManager instead of directly with the Pool
    struct Position {
        uint96 nonce; // nonce used for permits
        address owner; // owner of a position
        address pool; // address of the pool contract the position is associated to
        mapping(uint256 => uint256) lpTokens; // priceIndex => lpTokens
    }

    /// @dev The ID of the next token that will be minted. Skips 0
    uint176 private _nextId = 1;

    modifier isAuthorizedForToken(uint256 tokenId_) {
        if (_isApprovedOrOwner(msg.sender, tokenId_) == false) {
            revert NotApproved();
        }
        _;
    }

    function tokenURI(uint256 tokenId_) public view override(ERC721) returns (string memory) {
        require(_exists(tokenId_));

        // get position information for the given token
        Position storage position = positions[tokenId_];

        // TODO: access the prices at which a tokenId has added liquidity
        uint256[] memory prices;

        ConstructTokenURIParams memory params = ConstructTokenURIParams(
            tokenId_,
            position.pool,
            prices
        );

        return constructTokenURI(params);
    }

    function mint(MintParams calldata params_) external payable returns (uint256 tokenId_) {
        _safeMint(params_.recipient, (tokenId_ = _nextId++));

        // create a new position associated with the newly minted tokenId
        Position storage position = positions[tokenId_];
        position.pool = params_.pool;

        emit Mint(params_.recipient, params_.pool, tokenId_);
        return tokenId_;
    }

    /// TODO: (X) prices can be memorialized at a time
    function memorializePositions(MemorializePositionsParams calldata params_) external {
        Position storage position = positions[params_.tokenId];
        for (uint256 i = 0; i < params_.prices.length; ) {
            position.lpTokens[params_.prices[i]] = IPool(params_.pool).getLPTokenBalance(
                params_.owner,
                params_.prices[i]
            );
            // increment call counter in gas efficient way by skipping safemath checks
            unchecked {
                ++i;
            }
        }

        emit MemorializePosition(params_.owner, params_.tokenId);
    }

    // TODO: update burn check to ensure all position prices have removed liquidity
    function burn(BurnParams calldata params_)
        external
        payable
        isAuthorizedForToken(params_.tokenId)
    {
        Position storage position = positions[params_.tokenId];
        if (position.lpTokens[params_.price] != 0) {
            revert LiquidityNotRemoved();
        }
        emit Burn(msg.sender, params_.price);
        delete positions[params_.tokenId];
    }

    function increaseLiquidity(IncreaseLiquidityParams calldata params_)
        external
        payable
        isAuthorizedForToken(params_.tokenId)
    {
        Position storage position = positions[params_.tokenId];

        // call out to pool contract to add quote tokens
        uint256 lpTokensAdded = IPool(params_.pool).addQuoteToken(
            params_.recipient,
            params_.amount,
            params_.price
        );
        // TODO: figure out how to test this case
        if (lpTokensAdded == 0) {
            revert IncreaseLiquidityFailed();
        }

        // update position with newly added lp shares
        position.lpTokens[params_.price] += lpTokensAdded;

        emit IncreaseLiquidity(params_.recipient, params_.amount, params_.price);
    }

    function decreaseLiquidity(DecreaseLiquidityParams calldata params_)
        external
        payable
        isAuthorizedForToken(params_.tokenId)
    {
        Position storage position = positions[params_.tokenId];

        IPool pool = IPool(params_.pool);

        // calulate equivalent underlying assets for given lpTokens
        (uint256 collateralToRemove, uint256 quoteTokenToRemove) = pool.getLPTokenExchangeValue(
            params_.lpTokens,
            params_.price
        );

        pool.removeQuoteToken(params_.recipient, quoteTokenToRemove, params_.price);

        // enable lenders to remove quote token from a bucket that no debt is added to
        if (collateralToRemove != 0) {
            // claim any unencumbered collateral accrued to the price bucket
            pool.claimCollateral(
                params_.recipient,
                Maths.rayToWad(collateralToRemove),
                params_.price
            );
        }

        // update position with newly removed lp shares
        position.lpTokens[params_.price] -= params_.lpTokens;

        // TODO: check if price updates

        emit DecreaseLiquidity(
            params_.recipient,
            collateralToRemove,
            quoteTokenToRemove,
            params_.price
        );
    }

    /**
     * @notice Override ERC721 afterTokenTransfer hook to ensure that transferred NFT's are properly tracked within the PositionManager data struct
     * @dev This call also executes upon Mint
    */
    function _afterTokenTransfer(
        address,
        address to_,
        uint256 tokenId_
    ) internal virtual override(ERC721) {
        Position storage position = positions[tokenId_];
        position.owner = to_;
    }

    /** @dev used for tracking nonce input to permit function */
    function _getAndIncrementNonce(uint256 tokenId_) internal override returns (uint256) {
        return uint256(positions[tokenId_].nonce++);
    }

    // -------------------- Position State View functions --------------------

    /**
     * @notice Returns the lpTokens accrued to a given tokenId, price pairing
     * @dev Nested mappings aren't returned normally as part of the default getter for a mapping
    */
    function getLPTokens(uint256 tokenId_, uint256 price_) external view returns (uint256 lpTokens_) {
        lpTokens_ = positions[tokenId_].lpTokens[price_];
    }
    /**
     * @notice Called to determine the amount of quote and collateral tokens, in quote terms, represented by a given tokenId
     * @return quoteTokens_ The value of a NFT in terms of the pools quote token
    */
    function getPositionValueInQuoteTokens(uint256 tokenId_, uint256 price_)
        external
        view
        returns (uint256 quoteTokens_)
    {
        Position storage position = positions[tokenId_];

        uint256 lpTokens = position.lpTokens[price_];

        (uint256 collateral, uint256 quote) = IPool(position.pool).getLPTokenExchangeValue(
            lpTokens,
            price_
        );

        quoteTokens_ = quote + (collateral * price_);
    }

}
