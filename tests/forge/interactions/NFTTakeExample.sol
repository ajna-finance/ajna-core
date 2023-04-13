// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.14;

import './Interfaces.sol';
import 'src/interfaces/pool/erc721/IERC721Taker.sol';

contract NFTTakeExample is IERC721Taker {
    INFTMarketPlace marketplace;

    constructor(address marketplaceAddress_) {
        marketplace = INFTMarketPlace(marketplaceAddress_);
    }

    function atomicSwapCallback(
        uint256[] memory tokenIds, 
        uint256          quoteAmountDue,
        bytes calldata   data
    ) external {
        // swap collateral for quote token using Uniswap
        address ajnaPoolAddress = abi.decode(data, (address));
        IAjnaPool ajnaPool = IAjnaPool(ajnaPoolAddress);

        for (uint256 i = 0; i < tokenIds.length;) {
            marketplace.sellNFT(ajnaPool.collateralAddress(), tokenIds[i]);
            unchecked {
                ++i;
            }
        }

        // confirm the swap produced enough quote token for the take
        IERC20 quoteToken = IERC20(ajnaPool.quoteTokenAddress());
        assert(quoteToken.balanceOf(address(this)) > quoteAmountDue);
    }

    /** @notice Implementing this method allows contracts to receive ERC721 tokens
     *  @dev https://forum.openzeppelin.com/t/erc721holder-ierc721receiver-and-onerc721received/11828
     */
    function onERC721Received(address, address, uint256, bytes memory) external pure returns (bytes4) {
        return this.onERC721Received.selector;
    }
}

contract NFTMarketPlace is INFTMarketPlace {
    IERC20 currency;
    uint256 collectionOffer = 750 * 1e18;

    constructor(IERC20 currency_) {
        currency = currency_;
    }

    function sellNFT(address collection, uint tokenId) external {
        // take the NFT from the caller
        IERC721(collection).safeTransferFrom(msg.sender, address(this), tokenId);

        // pay the caller our standing offer
        require(currency.balanceOf(address(this)) > collectionOffer);
        currency.transfer(msg.sender, collectionOffer);
    }

    /** @notice Implementing this method allows contracts to receive ERC721 tokens
     *  @dev https://forum.openzeppelin.com/t/erc721holder-ierc721receiver-and-onerc721received/11828
     */
    function onERC721Received(address, address, uint256, bytes memory) external pure returns (bytes4) {
        return this.onERC721Received.selector;
    }
}

contract NFTNoopTakeExample is IERC721Taker {
    uint256[] public tokenIdsReceived;
    uint256   public quoteAmountDueReceived;
    address   public poolAddressReceived;

    function atomicSwapCallback(
        uint256[] memory tokenIds,
        uint256          quoteAmountDue,
        bytes calldata   data
    ) external {
        // NOOP, records inputs passed from pool to be checked in tests
        tokenIdsReceived       = tokenIds;
        quoteAmountDueReceived = quoteAmountDue;
        poolAddressReceived    = abi.decode(data, (address));
    }

    /** @notice Implementing this method allows contracts to receive ERC721 tokens
     *  @dev https://forum.openzeppelin.com/t/erc721holder-ierc721receiver-and-onerc721received/11828
     */
    function onERC721Received(address, address, uint256, bytes memory) external pure returns (bytes4) {
        return this.onERC721Received.selector;
    }
}