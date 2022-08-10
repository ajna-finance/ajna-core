// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.14;

import { IERC20 }  from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { IERC721 } from "@openzeppelin/contracts/token/ERC721/IERC721.sol";

import { ERC20Pool }  from "../../erc20/ERC20Pool.sol";
import { ERC721Pool } from "../../erc721/ERC721Pool.sol";

import { BucketMath } from "../../libraries/BucketMath.sol";

contract UserWithCollateral {

    function approveAndDepositTokenAsCollateral(IERC20 token_, ERC20Pool pool_, uint256 amount_, address oldPrev_, address newPrev_) public {
        token_.approve(address(pool_), amount_);
        pool_.addCollateral(amount_, oldPrev_, newPrev_);
    }

    function approveToken(IERC20 token_, address spender_, uint256 amount_) public {
        token_.approve(spender_, amount_);
    }

    function addCollateral(ERC20Pool pool_, uint256 amount_, address oldPrev_, address newPrev_) public {
        pool_.addCollateral(amount_, oldPrev_, newPrev_);
    }

    function borrow(ERC20Pool pool_, uint256 amount_, uint256 limitIndex_, address oldPrev_, address newPrev_) public {
        pool_.borrow(amount_, limitIndex_, oldPrev_, newPrev_);
    }

    function removeCollateral(ERC20Pool pool_, uint256 amount_, address oldPrev_, address newPrev_) public {
        pool_.removeCollateral(amount_, oldPrev_, newPrev_);
    }

    function repay(ERC20Pool pool_, uint256 amount_, address oldPrev_, address newPrev_) public {
        pool_.repay(amount_, oldPrev_, newPrev_);
    }
}

contract UserWithNFTCollateral {

    function approveAndDepositTokenAsCollateral(
        IERC721 token_,
        ERC721Pool pool_,
        uint256 tokenId_,
        address oldPrev_, 
        address newPrev_
    ) public {
        token_.approve(address(pool_), tokenId_);
        uint[] memory tokens = new uint[](1);
        tokens[0] = tokenId_;
        pool_.addCollateral(tokens, oldPrev_, newPrev_);
    }

    function approveToken(IERC721 token_, address spender_, uint256 _tokenId) public {
        token_.approve(spender_, _tokenId);
    }

    function approveCollection(IERC721 token_, address spender_) public {
        token_.setApprovalForAll(spender_, true);
    }

    function approveQuoteToken(IERC20 token_, address spender_, uint256 _tokenId) public {
        token_.approve(spender_, _tokenId);
    }

    function addCollateral(ERC721Pool pool_, uint256[] memory tokenIds_, address oldPrev_, address newPrev_) public {
        pool_.addCollateral(tokenIds_, oldPrev_, newPrev_);
    }

    function borrow(ERC721Pool pool_, uint256 amount_, uint256 index_, address oldPrev_, address newPrev_) public {
        pool_.borrow(amount_, index_, oldPrev_, newPrev_);
    }

    function purchaseQuote(ERC721Pool pool_, uint256 amount_, uint256 index_, uint256[] memory tokenIds_) public {
        pool_.purchaseQuote(amount_, index_, tokenIds_);
    }

    function repay(ERC721Pool pool_, uint256 amount_, address oldPrev_, address newPrev_) public {
        pool_.repay(amount_, oldPrev_, newPrev_);
    }

    function removeCollateral(ERC721Pool pool_, uint256[] memory tokenIds_, address oldPrev_, address newPrev_) public {
        pool_.removeCollateral(tokenIds_, oldPrev_, newPrev_);
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

    function addQuoteToken(ERC20Pool pool_, uint256 amount_, uint256 index_) public {
        pool_.addQuoteToken(amount_, index_);
    }

    function moveQuoteToken(
        ERC20Pool pool_, uint256 amount_, uint256 fromIndex_, uint256 toIndex_
    ) public {
        pool_.moveQuoteToken(amount_, fromIndex_, toIndex_);
    }

    function purchaseQuote(ERC20Pool pool_, uint256 amount_, uint256 index_) public {
        pool_.purchaseQuote(amount_, index_);
    }

    function removeQuoteToken(ERC20Pool pool_, uint256 amount_, uint256 index_) public {
        pool_.removeQuoteToken(amount_, index_);
    }

    function claimCollateral(ERC20Pool pool_, uint256 amount_, uint256 index_) public {
        pool_.claimCollateral(amount_, index_);
    }

    function approveToken(IERC20 token_, address spender_, uint256 amount_) public {
        token_.approve(spender_, amount_);
    }
}

contract UserWithQuoteTokenInNFTPool {

    function addQuoteToken(ERC721Pool pool_, uint256 amount_, uint256 index_) public {
        pool_.addQuoteToken(amount_, index_);
    }

    function moveQuoteToken(
        ERC721Pool pool_, uint256 amount_, uint256 fromIndex_, uint256 toIndex_
    ) public {
        pool_.moveQuoteToken(amount_, fromIndex_, toIndex_);
    }

    function removeQuoteToken(ERC721Pool pool_, uint256 lpTokensToRemove_, uint256 index_) public {
        pool_.removeQuoteToken(index_, lpTokensToRemove_);
    }

    function claimCollateral(ERC721Pool pool_, uint256[] memory tokenIds_, uint256 index_) public {
        pool_.claimCollateral(tokenIds_, index_);
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
