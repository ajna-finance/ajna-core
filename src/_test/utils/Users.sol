// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.14;

import { IERC20 }  from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { IERC721 } from "@openzeppelin/contracts/token/ERC721/IERC721.sol";

import { ERC20Pool }  from "../../erc20/ERC20Pool.sol";
import { ERC721Pool } from "../../erc721/ERC721Pool.sol";
import { ScaledPool } from "../../ScaledPool.sol";

import { BucketMath } from "../../libraries/BucketMath.sol";

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

contract UserWithCollateralInScaledPool {

    function approveAndDepositTokenAsCollateral(IERC20 token_, ScaledPool pool_, uint256 amount_, address oldPrev_, address newPrev_, uint256 radius_) public {
        token_.approve(address(pool_), amount_);
        pool_.addCollateral(amount_, oldPrev_, newPrev_, radius_);
    }

    function approveToken(IERC20 token_, address spender_, uint256 amount_) public {
        token_.approve(spender_, amount_);
    }

    function addCollateral(ScaledPool pool_, uint256 amount_, address oldPrev_, address newPrev_, uint256 radius_) public {
        pool_.addCollateral(amount_, oldPrev_, newPrev_, radius_);
    }

    function borrow(ScaledPool pool_, uint256 amount_, uint256 limitIndex_, address oldPrev_, address newPrev_, uint256 radius_) public {
        pool_.borrow(amount_, limitIndex_, oldPrev_, newPrev_, radius_);
    }

    function removeCollateral(ScaledPool pool_, uint256 amount_, address oldPrev_, address newPrev_, uint256 radius_) public {
        pool_.removeCollateral(amount_, oldPrev_, newPrev_, radius_);
    }

    function repay(ScaledPool pool_, uint256 amount_, address oldPrev_, address newPrev_, uint256 radius_) public {
        pool_.repay(amount_, oldPrev_, newPrev_, radius_);
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

    function addCollateralMultiple(ERC721Pool pool_, uint256[] memory tokenIds_) public {
        pool_.addCollateral(tokenIds_);
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

    function addQuoteToken(ERC20Pool pool_, uint256 amount_, uint256 price_) public {
        pool_.addQuoteToken(amount_, price_);
    }

    function removeQuoteToken(ERC20Pool pool_, uint256 lpTokensToRemove_, uint256 price_) public {
        pool_.removeQuoteToken(price_, lpTokensToRemove_);
    }

    function moveQuoteToken(
        ERC20Pool pool_, uint256 amount_, uint256 fromPrice_, uint256 toPrice_
    ) public {
        pool_.moveQuoteToken(amount_, fromPrice_, toPrice_);
    }

    function borrow(ERC20Pool pool_, uint256 amount_, uint256 limitPrice_) public {
        pool_.borrow(amount_, limitPrice_);
    }

    function claimCollateral(ERC20Pool pool_, uint256 amount_, uint256 price_) public {
        pool_.claimCollateral(amount_, price_);
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

contract UserWithQuoteTokenInScaledPool {

    function addQuoteToken(ScaledPool pool_, uint256 amount_, uint256 index_) public {
        pool_.addQuoteToken(amount_, index_);
    }

    function moveQuoteToken(
        ScaledPool pool_, uint256 amount_, uint256 fromIndex_, uint256 toIndex_
    ) public {
        pool_.moveQuoteToken(amount_, fromIndex_, toIndex_);
    }

    function purchaseQuote(ScaledPool pool_, uint256 amount_, uint256 index_) public {
        pool_.purchaseQuote(amount_, index_);
    }

    function removeQuoteToken(ScaledPool pool_, uint256 amount_, uint256 index_) public {
        pool_.removeQuoteToken(amount_, index_);
    }

    function claimCollateral(ScaledPool pool_, uint256 amount_, uint256 index_) public {
        pool_.claimCollateral(amount_, index_);
    }

    function approveToken(IERC20 token_, address spender_, uint256 amount_) public {
        token_.approve(spender_, amount_);
    }

}

contract UserWithQuoteTokenInNFTPool {
    function addQuoteToken(ERC721Pool pool_, uint256 amount_, uint256 price_) public {
        pool_.addQuoteToken(amount_, price_);
    }

    function removeQuoteToken(ERC721Pool pool_, uint256 lpTokensToRemove_, uint256 price_) public {
        pool_.removeQuoteToken(price_, lpTokensToRemove_);
    }

    function borrow(ERC721Pool pool_, uint256 amount_, uint256 stopPrice) public {
        pool_.borrow(amount_, stopPrice);
    }

    function claimCollateral(ERC721Pool pool_, uint256 tokenId_, uint256 price_) public {
        uint[] memory tokens = new uint[](1);
        tokens[0] = tokenId_;
        pool_.claimCollateral(tokens, price_);
    }

    function claimCollateralMultiple(ERC721Pool pool_, uint256[] memory tokenIds_, uint256 price_) public {
        pool_.claimCollateral(tokenIds_, price_);
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
