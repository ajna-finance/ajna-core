// SPDX-License-Identifier: MIT
pragma solidity 0.8.11;

import {ERC721} from '@openzeppelin/contracts/token/ERC721/ERC721.sol';
import {ERC721Enumerable} from '@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol';

// TODO: determine if tokens should be burnable
import {ERC721Burnable} from '@openzeppelin/contracts/token/ERC721/extensions/ERC721Burnable.sol';

interface IPositionNFT {

    function tokenURI(uint256 tokenId) external view returns (string memory);
}

abstract contract PositionNFT is ERC721, ERC721Enumerable {

    constructor(string memory name, string memory symbol, string memory version) ERC721(name, symbol) {}

    /// @notice Get tokenURI metadata for a given tokenId
    function tokenURI(uint256 tokenId) public view override returns (string memory) {

    }

    /// @dev Override required by solidity to use ERC721Enumerable library 
    function _beforeTokenTransfer(address from, address to, uint256 tokenId)
        internal
        override(ERC721, ERC721Enumerable)
    {
        super._beforeTokenTransfer(from, to, tokenId);
    }

    /// @dev Override required by solidity to use ERC721Enumerable library 
    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721, ERC721Enumerable)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }

}
