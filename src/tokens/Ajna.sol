// SPDX-License-Identifier: MIT

pragma solidity 0.8.11;

import { ERC20 }       from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { ERC20Permit } from "@openzeppelin/contracts/token/ERC20/extensions/draft-ERC20Permit.sol";

contract AjnaToken is ERC20("AjnaToken", "AJNA"), ERC20Permit {

    constructor(uint256 initialSupply) ERC20Permit("AjnaToken") {
        _mint(msg.sender, initialSupply);
    }

    function _beforeTokenTransfer(
        address from_,
        address,
        uint256
    ) internal view override {
        // This can be achived by setting _balances[address(this)] to the max value uint256.
        // But _balances are private variable in the OpenZeppelin ERC20 contract implementation.

        require(from_ != address(this), "Cannot transfer tokens from the contract itself");
    }

}
