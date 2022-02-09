// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.11;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20PerpPool} from "../../ERC20PerpPool.sol";

contract UserWithCollateral {
    function approveAndDepositTokenAsCollateral(
        IERC20 token,
        ERC20PerpPool pool,
        uint256 amount
    ) public {
        token.approve(address(pool), amount);
        pool.depositCollateral(amount);
    }

    function approveToken(
        IERC20 token,
        address spender,
        uint256 amount
    ) public {
        token.approve(spender, amount);
    }

    function depositCollteral(ERC20PerpPool pool, uint256 amount) public {
        pool.depositCollateral(amount);
    }

    function borrow(ERC20PerpPool pool, uint256 amount) public {
        pool.borrow(amount);
    }
}

contract UserWithQuoteToken {
    function depositQuoteToken(
        ERC20PerpPool pool,
        uint256 amount,
        uint256 price
    ) public {
        pool.depositQuoteToken(amount, price);
    }

    function approveToken(
        IERC20 token,
        address spender,
        uint256 amount
    ) public {
        token.approve(spender, amount);
    }
}
