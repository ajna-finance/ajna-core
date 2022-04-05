// SPDX-License-Identifier: MIT
pragma solidity 0.8.11;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {ERC721Enumerable} from "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {Base64} from "@base64-sol/base64.sol";

import {IPositionManager} from "../PositionManager.sol";
import {Permit} from "./Permit.sol";

// TODO: determine if tokens should be burnable
import {ERC721Burnable} from "@openzeppelin/contracts/token/ERC721/extensions/ERC721Burnable.sol";

abstract contract PositionNFT is ERC721, ERC721Enumerable, Permit {
    constructor(
        string memory name,
        string memory symbol,
        string memory version
    ) Permit(name, symbol, version) {}

    function constructTokenURI(
        IPositionManager.ConstructTokenURIParams memory params
    ) public pure returns (string memory) {
        string memory _name = string(
            abi.encodePacked("Ajna Token #", Strings.toString(params.tokenId))
        );
        string memory image = Base64.encode(
            bytes(generateSVGofTokenById(params.tokenId))
        );
        string memory description = "Ajna Positions NFT-V1";

        // address tokenOwner = ownerOf(params.tokenId);
        // string memory ownerHexString = (uint160(tokenOwner)).toHexString(20);
        string memory ownerHexString = "owner_address";

        return
            string(
                abi.encodePacked(
                    "data:application/json;base64,",
                    Base64.encode(
                        bytes(
                            abi.encodePacked(
                                '{"name":"',
                                _name,
                                '", "description":"',
                                description,
                                '"owner":"',
                                ownerHexString,
                                '", "image": "',
                                "data:image/svg+xml;base64,",
                                image,
                                '"}'
                            )
                        )
                    )
                )
            );
    }

    // TODO: finish implementing: https://github.com/scaffold-eth/scaffold-eth/blob/sipping-oe/packages/hardhat/contracts/OldEnglish.sol#L112-L234
    function generateSVGofTokenById(uint256 tokenId)
        internal
        pure
        returns (string memory)
    {
        string memory svg = string(
            abi.encodePacked(
                '<svg xmlns="http://www.w3.org/2000/svg" width="216.18" height="653.57">',
                renderTokenById(tokenId),
                "</svg>"
            )
        );
        return svg;
    }

    // TODO: add SVG string for Ajna Logo
    function renderTokenById(uint256) internal pure returns (string memory) {
        return string(abi.encodePacked(""));
    }

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
