// SPDX-License-Identifier: MIT

pragma solidity 0.8.10;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract Erc20Pool {
    IERC20 public immutable UNDERLYING;

    constructor(IERC20 underlying) {
        UNDERLYING = underlying;
    }
}