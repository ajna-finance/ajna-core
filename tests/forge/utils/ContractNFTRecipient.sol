// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.14;

import '@openzeppelin/contracts/token/ERC721/IERC721.sol';
import '@openzeppelin/contracts/interfaces/IERC1271.sol';
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

contract ContractNFTRecipient is IERC1271 {

    using ECDSA for bytes32;

    address contractOwner;

    // MAGICVALUE is defined in eip 1271,
    // as the value to return for valid signatures
    bytes4 internal constant MAGICVALUE = 0x1626ba7e;
    bytes4 internal constant INVALID_SIGNATURE = 0xffffffff;

    constructor(address owner_) {
        contractOwner = owner_;
    }

    function isValidSignature(bytes32 messageHash_, bytes memory signature_) external view returns (bytes4) {
        address signer = messageHash_.recover(signature_);

        if (signer == contractOwner) {
            return MAGICVALUE;
        } else {
            return INVALID_SIGNATURE;
        }
    }

    function transferNFT(address NFTAddress_, address receiver_, uint256 tokenId_) external {
        IERC721 nft = IERC721(NFTAddress_);

        nft.transferFrom(address(this), receiver_, tokenId_);
    }

    /** @notice Implementing this method allows contracts to receive ERC721 tokens
     *  @dev https://forum.openzeppelin.com/t/erc721holder-ierc721receiver-and-onerc721received/11828
     */
    function onERC721Received(address, address, uint256, bytes memory) external pure returns (bytes4) {
        return this.onERC721Received.selector;
    }

}
