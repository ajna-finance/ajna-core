// SPDX-License-Identifier: MIT

pragma solidity 0.8.14;

/**
 * @title Ajna Positions Manager Derived State
 */
interface IPositionManagerDerivedState {

    /**
     *  @notice Returns the lpTokens accrued to a given tokenId, price pairing.
     *  @dev    Nested mappings aren't returned normally as part of the default getter for a mapping.
     *  @param  index    Index of price bucket to check LP balance of.
     *  @param  tokenId  Unique ID of token.
     *  @return lpTokens Balance of lpTokens in the price bucket for this position.
    */
    function getLPTokens(
        uint256 index,
        uint256 tokenId
    ) external view returns (uint256 lpTokens);

    /**
     *  @notice Checks if a given tokenId has a given position price
     *  @param  index            Index of price bucket to check if in position prices.
     *  @param  tokenId          Unique ID of token.
     *  @return priceInPostition True if tokenId has the position price
    */
    function isIndexInPosition(
        uint256 index,
        uint256 tokenId
    ) external view returns (bool priceInPostition);
}