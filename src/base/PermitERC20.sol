// SPDX-License-Identifier: MIT
pragma solidity 0.8.11;

// import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import {IERC20Permit} from '@openzeppelin/contracts/token/ERC20/extensions/draft-IERC20Permit.sol';

// TODO: implement this method to enable permit based interactions with quote and collaterla tokens
// https://github.com/Uniswap/v3-periphery/blob/main/contracts/base/SelfPermit.sol
// https://github.com/Uniswap/v3-periphery/commit/1af94fe666bfc86dbcec053d57719affa5c0438a
abstract contract PermitERC20 {
    function selfPermit(
        address token,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) public payable {
        IERC20Permit(token).permit(msg.sender, address(this), value, deadline, v, r, s);
    }
}