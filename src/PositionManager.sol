// SPDX-License-Identifier: MIT
pragma solidity 0.8.11;

import {PositionNFT} from "./PositionNFT.sol";
import {IPool} from "./ERC20Pool.sol";

import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "../lib/hardhat/packages/hardhat-core/console.sol";

interface IPositionManager {
    struct MintParams {
        address recipient;
        // address collateral;
        // address quoteToken;
        address pool;
        uint256 amount;
        uint256 price;
    }

    function mint(MintParams calldata params)
        external
        payable
        returns (uint256 tokenId);

    function burn(uint256 tokenId) external payable;

    function redeem() external payable;

    function modifyPosition() external payable;

    // function getPosition(uint256 tokenId) external view returns (Position position);
}

contract PositionManager is IPositionManager, PositionNFT, IERC721Receiver {
    event Mint(address lender, uint256 amount, uint256 price);
    event Burn(address lender, uint256 price);
    event Redeem(address lender, uint256 price, uint256 amount);

    constructor() PositionNFT("Ajna Positions NFT-V1", "AJNA-V1-POS", "1") {}

    /// @dev Mapping of tokenIds to Position information
    mapping(uint256 => Position) private positions;

    /// @dev The ID of the next token that will be minted. Skips 0
    uint176 private _nextId = 1;

    /// @dev Details about Ajna positions - used for both Borrowers and Lenders
    struct Position {
        address owner; // owner of a position
        uint256 price; // price bucket a position is associated with
        uint256 liquidity; // the amount
        address pool; // address of the pool contract the position is associated to
    }

    function mint(MintParams calldata params)
        external
        payable
        returns (uint256 tokenId)
    {
        address pool = params.pool;

        // call out to pool contract to add quote tokens
        // bytes4(keccak256("addQuoteToken(uint256,uint256)")));
        // seth sig $(seth --from-ascii "addQuoteToken(uint256,uint256)")
        (bool success, bytes memory returnedData) = pool.delegatecall(abi.encodeWithSelector(0x438d1ff0, params.amount, params.price));
        require(success, string(returnedData));

        _safeMint(params.recipient, (tokenId = _nextId++));

        positions[tokenId] = Position(
            params.recipient,
            params.price,
            params.amount, // TODO: fix to be returned from addQuoteToken
            params.pool
        );

        emit Mint(params.recipient, params.amount, params.price);
        return tokenId;
    }

    // TODO: finish implementing
    function burn(uint256 tokenId) external payable {
        Position storage position = positions[tokenId];
        require(position.liquidity == 0, "Not Redeemed");
        delete positions[tokenId];
        emit Burn(msg.sender, position.price);
    }

    // TODO: finish implementing
    function redeem() external payable {}

    function modifyPosition() external payable {}

    // -------------------- Position State View functions --------------------

    function getPosition(uint256 tokenId)
        public
        view
        returns (Position memory position)
    {
        Position memory position = positions[tokenId];
        require(position.liquidity != 0, "Invalid position");
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
    function onERC721Received(address operator, address from, uint256 tokenId, bytes memory data) external returns (bytes4) {

    }
}
