// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.14;

import { Base64 } from '@base64-sol/base64.sol';

import '@openzeppelin/contracts/token/ERC721/ERC721.sol';
import '@openzeppelin/contracts/utils/Strings.sol';

import './interfaces/IPositionManager.sol';

import './PermitERC721.sol';

abstract contract PositionNFT is ERC721, PermitERC721 {
    using Strings for uint256;

    constructor(
        string memory name_, string memory symbol_, string memory version_
    ) PermitERC721(name_, symbol_, version_) {
    }

    function constructTokenURI(IPositionManager.ConstructTokenURIParams memory params_) public view returns (string memory) {
        string memory _name = string(
            abi.encodePacked("Ajna Token #", Strings.toString(params_.tokenId))
        );
        string memory image = Base64.encode(bytes(_generateSVGofTokenById(params_.tokenId)));
        string memory description = "Ajna Positions NFT-V1";

        address tokenOwner = ownerOf(params_.tokenId);
        string memory ownerHexString = (uint256(uint160(tokenOwner))).toHexString(20);

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
    function _generateSVGofTokenById(uint256 tokenId_) internal pure returns (string memory) {
        string memory svg = string(
            abi.encodePacked(
                '<svg xmlns="http://www.w3.org/2000/svg" width="216.18" height="653.57">',
                _renderTokenById(tokenId_),
                "</svg>"
            )
        );
        return svg;
    }

    // TODO: add SVG string for Ajna Logo
    function _renderTokenById(uint256) internal pure returns (string memory) {
        return string(abi.encodePacked(""));
    }

}
