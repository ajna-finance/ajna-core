// SPDX-License-Identifier: MIT

pragma solidity 0.8.14;

/**
 * @title Positions Manager Derived State
 */
interface IPositionManagerDerivedState {

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
     *  @notice Returns an array of price indexes in which an NFT has liquidity.
     *  @param  tokenId  Unique ID of token.
     *  @return Array of price indexes.
    */
    function getPositionIndexes(uint256 tokenId) external view returns (uint256[] memory);

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
