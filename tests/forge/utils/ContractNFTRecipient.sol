// SPDX-License-Identifier: MIT

pragma solidity 0.8.14;

import '@openzeppelin/contracts/token/ERC721/IERC721.sol';

contract ContractNFTRecipient {

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
