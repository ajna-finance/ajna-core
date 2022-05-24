// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.11;

import { ERC20Pool } from "../../ERC20Pool.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

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

    function updateInterestRate(ERC20Pool pool_) public {
        pool_.updateInterestRate();
    }

}
