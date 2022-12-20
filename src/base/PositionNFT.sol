// SPDX-License-Identifier: MIT
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
        // string memory description = "Ajna Positions NFT-V1";

        // address tokenOwner = ownerOf(params_.tokenId);
        // string memory ownerHexString = (uint256(uint160(tokenOwner))).toHexString(20);

        return image;
        // return
        //     string(
        //         abi.encodePacked(
        //             "data:application/json;base64,",
        //             Base64.encode(
        //                 bytes(
        //                     abi.encodePacked(
        //                         '{"name":"',
        //                         _name,
        //                         '", "description":"',
        //                         description,
        //                         '"owner":"',
        //                         ownerHexString,
        //                         '", "image": "',
        //                         "data:image/svg+xml;base64,",
        //                         image,
        //                         '"}'
        //                     )
        //                 )
        //             )
        //         )
        //     );
    }

    // TODO: finish implementing: https://github.com/scaffold-eth/scaffold-eth/blob/sipping-oe/packages/hardhat/contracts/OldEnglish.sol#L112-L234
    function _generateSVGofTokenById(uint256 tokenId_) internal pure returns (string memory svg_) {
        svg_ = string(
            abi.encodePacked(
                '<svg fill="none" viewBox="0 0 512 512" xmlns="http://www.w3.org/2000/svg"',
                    _generateBackground(),
                    _generateSVGDefs(),
                    _generatePoolTag(tokenId_),
                    _generateTokenIdTag(tokenId_),
                "</svg>"
            )
        );
    }

    function _generateBackground() private pure returns (string memory background_) {
        string memory backgroundTop = string(abi.encodePacked(
                '<rect width="512" height="512" rx="32" fill="url(#a)"/>',
                '<rect width="512" height="512" rx="32" fill="#000" fill-opacity=".5"/>',
                '<g filter="url(#b)">',
                '<ellipse cx="374" cy="402.5" rx="122" ry="121.5" fill="#B45CD6"/>',
                '<circle cx="157" cy="315" r="122" fill="#37FCFB"/>',
                '<ellipse cx="137.78" cy="137.5" rx="121.78" ry="121.5" fill="#642DD2"/>',
                '</g>'
        ));

        string memory backgroundBottom = string(abi.encodePacked(
                '<rect x="16" y="16" width="480" height="480" rx="24" fill="#000" opacity=".5"/>',
                '<circle cx="256" cy="256" r="224" stroke="#fff" stroke-width="2"/>',
                '<path d="m410.27 467c-0.069 0-0.134-0.026-0.195-0.078-0.052-0.061-0.078-0.126-0.078-0.195 0-0.043 4e-3 -0.082 0.013-0.117l3.055-8.346c0.026-0.095 0.078-0.178 0.156-0.247 0.087-0.078 0.204-0.117 0.351-0.117h1.924c0.147 0 0.26 0.039 0.338 0.117 0.087 0.069 0.143 0.152 0.169 0.247l3.042 8.346c0.017 0.035 0.026 0.074 0.026 0.117 0 0.069-0.03 0.134-0.091 0.195-0.052 0.052-0.117 0.078-0.195 0.078h-1.599c-0.13 0-0.23-0.03-0.299-0.091-0.061-0.069-0.1-0.13-0.117-0.182l-0.507-1.326h-3.471l-0.494 1.326c-0.017 0.052-0.056 0.113-0.117 0.182-0.061 0.061-0.165 0.091-0.312 0.091h-1.599zm3.055-3.471h2.418l-1.222-3.432-1.196 3.432z" fill="#fff"/>',
                '<path d="m431.12 467.13c-0.494 0-0.967-0.061-1.417-0.182-0.442-0.13-0.837-0.321-1.183-0.572-0.347-0.251-0.624-0.563-0.832-0.936-0.2-0.373-0.308-0.806-0.325-1.3 0-0.078 0.026-0.143 0.078-0.195 0.052-0.061 0.121-0.091 0.208-0.091h1.755c0.121 0 0.212 0.03 0.273 0.091 0.069 0.061 0.125 0.152 0.169 0.273 0.043 0.243 0.125 0.442 0.247 0.598 0.121 0.147 0.273 0.26 0.455 0.338 0.19 0.069 0.403 0.104 0.637 0.104 0.433 0 0.767-0.139 1.001-0.416 0.234-0.286 0.351-0.702 0.351-1.248v-3.757h-4.212c-0.087 0-0.165-0.03-0.234-0.091-0.061-0.061-0.091-0.139-0.091-0.234v-1.287c0-0.095 0.03-0.173 0.091-0.234 0.069-0.061 0.147-0.091 0.234-0.091h6.292c0.095 0 0.173 0.03 0.234 0.091 0.069 0.061 0.104 0.139 0.104 0.234v5.434c0 0.754-0.165 1.391-0.494 1.911-0.33 0.511-0.78 0.901-1.352 1.17-0.572 0.26-1.235 0.39-1.989 0.39z" fill="#fff"/>',
                '<path d="m445.01 467c-0.096 0-0.174-0.03-0.234-0.091-0.061-0.061-0.091-0.139-0.091-0.234v-8.45c0-0.095 0.03-0.173 0.091-0.234 0.06-0.061 0.138-0.091 0.234-0.091h1.378c0.147 0 0.251 0.035 0.312 0.104 0.069 0.061 0.112 0.108 0.13 0.143l3.172 5.005v-4.927c0-0.095 0.03-0.173 0.091-0.234 0.06-0.061 0.138-0.091 0.234-0.091h1.56c0.095 0 0.173 0.03 0.234 0.091 0.06 0.061 0.091 0.139 0.091 0.234v8.45c0 0.087-0.031 0.165-0.091 0.234-0.061 0.061-0.139 0.091-0.234 0.091h-1.391c-0.139 0-0.243-0.035-0.312-0.104-0.061-0.069-0.1-0.117-0.117-0.143l-3.172-4.81v4.732c0 0.095-0.031 0.173-0.091 0.234-0.061 0.061-0.139 0.091-0.234 0.091h-1.56z" fill="#fff"/>',
                '<path d="m461.5 467c-0.069 0-0.134-0.026-0.195-0.078-0.052-0.061-0.078-0.126-0.078-0.195 0-0.043 5e-3 -0.082 0.013-0.117l3.055-8.346c0.026-0.095 0.078-0.178 0.156-0.247 0.087-0.078 0.204-0.117 0.351-0.117h1.924c0.148 0 0.26 0.039 0.338 0.117 0.087 0.069 0.143 0.152 0.169 0.247l3.042 8.346c0.018 0.035 0.026 0.074 0.026 0.117 0 0.069-0.03 0.134-0.091 0.195-0.052 0.052-0.117 0.078-0.195 0.078h-1.599c-0.13 0-0.229-0.03-0.299-0.091-0.06-0.069-0.099-0.13-0.117-0.182l-0.507-1.326h-3.471l-0.494 1.326c-0.017 0.052-0.056 0.113-0.117 0.182-0.06 0.061-0.164 0.091-0.312 0.091h-1.599zm3.055-3.471h2.418l-1.222-3.432-1.196 3.432z" fill="#fff"/>',
                '<path d="M106.178 169.5L256 429L405.822 169.5H106.178Z" stroke="#fff"/>',
                '<path d="M106.178 342.5L256 83L405.822 342.5H106.178Z" stroke="#fff"/>',
                '<circle cx="256" cy="256" r="71.5" stroke="#fff"/>',
                '<circle cx="256" cy="256" r="20" fill="#974EEA"/>',
                '<circle cx="264" cy="248" r="4" fill="#fff"/>',
                '<path d="m406.5 170-150.5-87.5-150 87.5v172.5l150 87 150.5-87v-172.5z" stroke="#fff"/>',
                '<path d="m184 256s26.5-30 72-30 72 30 72 30" stroke="#fff"/>',
                '<path d="m328 256s-26.5 30-72 30-72-30-72-30" stroke="#fff"/>'
        ));

        background_ = string(abi.encodePacked(
            '<g clip-path="url(#c)">',
            backgroundTop,
            backgroundBottom,
            '</g>'
        ));
    }

    function _generateSVGDefs() private pure returns (string memory defs_) {
        defs_ = string(abi.encodePacked(
            '<defs>',
                '<filter id="b" x="-184" y="-184" width="880" height="908" color-interpolation-filters="sRGB" filterUnits="userSpaceOnUse">',
                    '<feFlood flood-opacity="0" result="BackgroundImageFix"/>',
                    '<feBlend in="SourceGraphic" in2="BackgroundImageFix" result="shape"/>',
                    '<feGaussianBlur result="effect1_foregroundBlur_115_51" stdDeviation="100"/>',
                '</filter>',
                '<linearGradient id="a" x1="15.059" x2="512" y1="152.62" y2="152.62" gradientUnits="userSpaceOnUse">',
                    '<stop stop-color="#B1A6CE" offset="0"/>',
                    '<stop stop-color="#B45CD6" offset=".50521"/>',
                    '<stop stop-color="#642DD2" offset="1"/>',
                '</linearGradient>',
                '<clipPath id="c">',
                    '<rect width="512" height="512" rx="32" fill="#fff"/>',
                '</clipPath>',
            '</defs>'
        ));
    }

    function _generatePoolTag(uint256 tokenId_) private pure returns (string memory poolTag_) {
        poolTag_ = string(abi.encodePacked(
            '<text x="32px" y="46px" fill="white" font-family="\'andale mono\', Courier New", monospace" font-size="18px">',
                abi.encodePacked(_getPoolText(tokenId_)),
            '</text>'
        ));
    }

    function _generateTokenIdTag(uint256 tokenId_) private pure returns (string memory tokenIdTag_) {
        tokenIdTag_ = string(abi.encodePacked(
            '<g style="transform:translate(32px, 456px)">',
                '<rect width="92px" height="26px" rx="8px" ry="8px" fill="rgba(0,0,0,0.8)"/>',
                '<text x="12px" y="17px" fill="violet" font-family="\'andale mono\', Courier New", monospace" font-size="12px">',
                    '<tspan fill="rgba(255,255,255,0.6)">ID: </tspan>',
                    abi.encodePacked(tokenId_),
                '</text>',
            '</g>'
        ));
    }

    function _getPoolText(uint256 tokenId) internal pure returns (string memory) {
        return "ETH/DAI";
    }

}
