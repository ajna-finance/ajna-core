// SPDX-License-Identifier: MIT
pragma solidity 0.8.11;

import {PositionNFT} from './PositionNFT.sol';

interface IPositionManager {

    struct MintParams {
        address collateral;
        address quoteToken;
    }

    function mint(MintParams calldata params) external payable returns (uint256 tokenId);

    function burn(uint256 tokenId) external payable;

    function redeem() external payable;

    function modifyPosition () external payable;

    // function getPosition(uint256 tokenId) external view returns (Position position);


}

// https://github.com/Uniswap/v3-periphery/blob/main/contracts/NonfungiblePositionManager.sol
contract PositionManager is IPositionManager, PositionNFT {

    event Mint(address lender, uint256 price, uint256 amount);
    event Burn(address lender, uint256 price);
    event Redeem(address lender, uint256 price, uint256 amount);

    constructor(address factory) PositionNFT("Ajna Positions NFT-V1", "AJNA-V1-POS", "1") {

    }

    /// @dev Details about Ajna positions - used for both Borrowers and Lenders
    struct Position {
        address owner; // owner of a position
        uint256 price; // price bucket a position is associated with
        uint256 liquidity; // the amount 
        address pool; // address of the pool contract the position is associated to
    }

    /// @dev Mapping of tokenIds to Position information
    mapping(uint256 => Position) private positions;

    // TODO: finish implementing
    function mint (MintParams calldata params) external payable returns (uint256 tokenId) {
        // TODO: implement call to addQuoteToken
    }

    // TODO: finish implementing
    function burn (uint256 tokenId) external payable {
        Position storage position = positions[tokenId];
        require(position.liquidity == 0, 'Not Redeemed');
        delete positions[tokenId];
        emit Burn(msg.sender, position.price);
    }

    // TODO: finish implementing
    function redeem () external payable {}

    function modifyPosition () external payable {}


    // -------------------- Position State View functions --------------------

    function getPosition(uint256 tokenId) public view returns (Position memory position) {
        Position memory position = positions[tokenId];
        require(position.liquidity != 0, 'Invalid position');
        return position;
    }

    // TODO: implement
    function getPositionOwnedCollateral(uint256 tokenId) public view returns (uint256 collateral) {}

    // TODO: implement
    function getPositionOwnedQuoteTokens(uint256 tokenId) public view returns (uint256 quoteTokens) {}

}