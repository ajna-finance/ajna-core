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