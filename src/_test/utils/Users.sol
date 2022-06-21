// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.14;

import { IERC20 }  from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { IERC721 } from "@openzeppelin/contracts/token/ERC721/IERC721.sol";

import { ERC20Pool }  from "../../erc20/ERC20Pool.sol";
import { ERC721Pool } from "../../erc721/ERC721Pool.sol";

contract UserWithCollateral {

    function approveAndDepositTokenAsCollateral(IERC20 token_, ERC20Pool pool_, uint256 amount_) public {
        token_.approve(address(pool_), amount_);
        pool_.addCollateral(amount_);
    }

    function approveToken(IERC20 token_, address spender_, uint256 amount_) public {
        token_.approve(spender_, amount_);
    }

    function addCollateral(ERC20Pool pool_, uint256 amount_) public {
        pool_.addCollateral(amount_);
    }

    function borrow(ERC20Pool pool_, uint256 amount_, uint256 price_) public {
        pool_.borrow(amount_, price_);
    }

    function purchaseBid(ERC20Pool pool_, uint256 amount_, uint256 price_) public {
        pool_.purchaseBid(amount_, price_);
    }

    function repay(ERC20Pool pool_, uint256 amount_) public {
        pool_.repay(amount_);
    }

    function removeCollateral(ERC20Pool pool_, uint256 amount_) public {
        pool_.removeCollateral(amount_);
    }

}

contract UserWithNFTCollateral {

    function approveAndDepositTokenAsCollateral(
        IERC721 token_,
        ERC721Pool pool_,
        uint256 tokenId_
    ) public {
        token_.approve(address(pool_), tokenId_);
        uint[] memory tokens = new uint[](1);
        tokens[0] = tokenId_;
        pool_.addCollateral(tokens);
    }

    function approveToken(IERC721 token_, address spender_, uint256 _tokenId) public {
        token_.approve(spender_, _tokenId);
    }

    function addCollateral(ERC721Pool pool_, uint256 tokenId_) public {
        uint[] memory tokens = new uint[](1);
        tokens[0] = tokenId_;
        pool_.addCollateral(tokens);
    }

    function borrow(ERC721Pool pool_, uint256 amount_, uint256 price_) public {
        pool_.borrow(amount_, price_);
    }

    function purchaseBid(ERC721Pool pool_, uint256 amount_, uint256 price_, uint256[] memory tokenIds_) public {
        pool_.purchaseBid(amount_, price_, tokenIds_);
    }

    function repay(ERC721Pool pool_, uint256 amount_) public {
        pool_.repay(amount_);
    }

    function removeCollateral(ERC721Pool pool_, uint256 tokenId_) public {
        uint[] memory tokens = new uint[](1);
        tokens[0] = tokenId_;
        pool_.removeCollateral(tokens);
    }

    // Implementing this method allows contracts to receive ERC721 tokens
    // https://forum.openzeppelin.com/t/erc721holder-ierc721receiver-and-onerc721received/11828
    function onERC721Received(
        address,
        address,
        uint256,
        bytes memory
    ) external pure returns (bytes4) {
        return this.onERC721Received.selector;
    }
}

contract UserWithQuoteToken {

    function addQuoteToken(ERC20Pool pool_, address recipient_, uint256 amount_, uint256 price_) public {
        pool_.addQuoteToken(recipient_, amount_, price_);
    }

    function removeQuoteToken(ERC20Pool pool_, address recipient_, uint256 amount_, uint256 price_) public {
        pool_.removeQuoteToken(recipient_, amount_, price_);
    }

    function moveQuoteToken(
        ERC20Pool pool_, address recipient_, uint256 amount_, uint256 fromPrice_, uint256 toPrice_
    ) public {
        pool_.moveQuoteToken(recipient_, amount_, fromPrice_, toPrice_);
    }

    function borrow(ERC20Pool pool_, uint256 amount_, uint256 limitPrice_) public {
        pool_.borrow(amount_, limitPrice_);
    }

    function claimCollateral(ERC20Pool pool_, address recipient_, uint256 amount_, uint256 price_) public {
        pool_.claimCollateral(recipient_, amount_, price_);
    }

    function liquidate(ERC20Pool pool_, address borrower_) public {
        pool_.liquidate(borrower_);
    }

    function approveToken(IERC20 token_, address spender_, uint256 amount_) public {
        token_.approve(spender_, amount_);
    }

    // Implementing this method allows contracts to receive ERC721 tokens
    // https://forum.openzeppelin.com/t/erc721holder-ierc721receiver-and-onerc721received/11828
    function onERC721Received(address, address, uint256, bytes memory) external pure returns (bytes4) {
        return this.onERC721Received.selector;
    }

}

contract UserWithQuoteTokenInNFTPool {
    function addQuoteToken(ERC721Pool pool_, address recipient_, uint256 amount_, uint256 price_) public {
        pool_.addQuoteToken(recipient_, amount_, price_);
    }

    function removeQuoteToken(ERC721Pool pool_, address recipient_, uint256 amount_, uint256 price_) public {
        pool_.removeQuoteToken(recipient_, amount_, price_);
    }

    function borrow(ERC721Pool pool_, uint256 amount_, uint256 stopPrice) public {
        pool_.borrow(amount_, stopPrice);
    }

    function claimCollateral(ERC721Pool pool_, address recipient_, uint256 tokenId_, uint256 price_) public {
        uint[] memory tokens = new uint[](1);
        tokens[0] = tokenId_;
        pool_.claimCollateral(recipient_, tokens, price_);
    }

    function claimCollateralMultiple(ERC721Pool pool_, address recipient_, uint256[] memory tokenIds_, uint256 price_) public {
        pool_.claimCollateral(recipient_, tokenIds_, price_);
    }

    function liquidate(ERC721Pool pool_, address borrower) public {
        pool_.liquidate(borrower);
    }

    function approveToken(IERC20 token, address spender, uint256 amount_) public {
        token.approve(spender, amount_);
    }

    // Implementing this method allows contracts to receive ERC721 tokens
    // https://forum.openzeppelin.com/t/erc721holder-ierc721receiver-and-onerc721received/11828
    function onERC721Received(address, address, uint256, bytes memory) external pure returns (bytes4) {
        return this.onERC721Received.selector;
    }
}
