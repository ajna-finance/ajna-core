// SPDX-License-Identifier: MIT
pragma solidity 0.8.11;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {ERC721Enumerable} from "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

// TODO: determine if tokens should be burnable
import {ERC721Burnable} from "@openzeppelin/contracts/token/ERC721/extensions/ERC721Burnable.sol";

abstract contract PositionNFT is ERC721, ERC721Enumerable {
    constructor(
        string memory name,
        string memory symbol,
        string memory version
    ) ERC721(name, symbol) {}

    /// @notice Get tokenURI metadata for a given tokenId
    function tokenURI(uint256 tokenId)
        public
        view
        override
        returns (string memory)
    {
        require(_exists(tokenId), "not exist");
        string memory name = string(
            abi.encodePacked("Ajna Token #", Strings.toString(tokenId))
        );
        // string memory image = Base64.encode(bytes(generateSVGofTokenById(tokenId)));
        return name;
    }

    // TODO: finish implementing: https://github.com/scaffold-eth/scaffold-eth/blob/sipping-oe/packages/hardhat/contracts/OldEnglish.sol#L112-L234
    function generateSVGofTokenById(uint256 id)
        internal
        view
        returns (string memory)
    {}

    /// @dev Override required by solidity to use ERC721Enumerable library
    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 tokenId
    ) internal override(ERC721, ERC721Enumerable) {
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
