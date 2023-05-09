pragma solidity 0.8.14;

import { PermitERC721 } from '../../src/base/PermitERC721.sol';

contract PermitERC721Harness is PermitERC721 { 

    // overrides internal nonces
    mapping(uint256 => uint96) public nonces;

    constructor() PermitERC721("Ajna Positions NFT-V1", "AJNA-V1-POS", "1") public {}

    // PostionManager.sol
    function _getAndIncrementNonce(
        uint256 tokenId_
    ) internal override returns (uint256) {
        return uint256(nonces[tokenId_]++);
    }
}
