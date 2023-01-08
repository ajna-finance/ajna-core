// SPDX-License-Identifier: MIT

pragma solidity 0.8.14;

interface ICryptoKitties {
    function transferFrom(address from_, address to_, uint256 tokenId_) external;
    function transfer(address to_, uint256 tokenId_) external;
    function approve(address to_, uint256 tokenId_) external;
    function ownerOf(uint256 tokenId_) external returns(address);
    function kittyIndexToApproved(uint256 tokenId_) external returns(address);
}

interface ICryptoPunks {
    function buyPunk(uint punkIndex) external;
    function transferPunk(address to, uint punkIndex) external;
    function offerPunkForSaleToAddress(uint punkIndex, uint minSalePriceInWei, address toAddress) external;
    function punkIndexToAddress(uint punkIndex) external returns(address); 
}

enum NFTTypes{ STANDARD_ERC721, CRYPTOPUNKS, CRYPTOKITTIES }