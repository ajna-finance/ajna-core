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

    function addQuoteToken(ERC20Pool pool, address recipient, uint256 amount, uint256 price) public {
        pool.addQuoteToken(recipient, amount, price);
    }

    function removeQuoteToken(ERC20Pool pool, address recipient, uint256 amount, uint256 price) public {
        pool.removeQuoteToken(recipient, amount, price);
    }

    function borrow(ERC20Pool pool, uint256 amount, uint256 stopPrice) public {
        pool.borrow(amount, stopPrice);
    }

    function claimCollateral(ERC20Pool pool, address recipient, uint256 amount, uint256 price) public {
        pool.claimCollateral(recipient, amount, price);
    }

    function liquidate(ERC20Pool pool, address borrower) public {
        pool.liquidate(borrower);
    }

    function approveToken(IERC20 token, address spender, uint256 amount) public {
        token.approve(spender, amount);
    }

    // Implementing this method allows contracts to receive ERC721 tokens
    // https://forum.openzeppelin.com/t/erc721holder-ierc721receiver-and-onerc721received/11828
    function onERC721Received(address, address, uint256, bytes memory) external pure returns (bytes4) {
        return this.onERC721Received.selector;
    }

    function updateInterestRate(ERC20Pool pool) public {
        pool.updateInterestRate();
    }

}
