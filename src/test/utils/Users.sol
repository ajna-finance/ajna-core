// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.10;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Pool} from "../../ERC20Pool.sol";

contract UserWithCollateral {
    function approveAndDepositTokenAsCollateral(
        IERC20 token,
        ERC20Pool pool,
        uint256 amount
    ) public {
        token.approve(address(pool), amount);
        pool.addCollateral(amount);
    }

    function approveToken(
        IERC20 token,
        address spender,
        uint256 amount
    ) public {
        token.approve(spender, amount);
    }

    function addCollteral(ERC20Pool pool, uint256 amount) public {
        pool.addCollateral(amount);
    }

    function borrow(
        ERC20Pool pool,
        uint256 amount,
        uint256 price
    ) public {
        pool.borrow(amount, price);
    }
}

contract UserWithQuoteToken {
    function addQuoteToken(
        ERC20Pool pool,
        uint256 amount,
        uint256 price
    ) public {
        pool.addQuoteToken(amount, price);
    }

    function approveToken(
        IERC20 token,
        address spender,
        uint256 amount
    ) public {
        token.approve(spender, amount);
    }
}
