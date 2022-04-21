// SPDX-License-Identifier: MIT

pragma solidity 0.8.11;

// Multicall Guides:
// - https://github.com/gnosis/safe-contracts/blob/186a21a74b327f17fc41217a927dea7064f74604/contracts/libraries/MultiSend.sol

// https://github.com/gakonst/v3-periphery-foundry

abstract contract Multicall {
    function multicall(bytes[] calldata data) public payable returns (bytes[] memory results) {
        results = new bytes[](data.length);
        for (uint256 i = 0; i < data.length; i++) {
            (bool success, bytes memory result) = address(this).delegatecall(data[i]);

            if (!success) {
                // Next 5 lines from https://ethereum.stackexchange.com/a/83577
                if (result.length < 68) revert();
                assembly {
                    result := add(result, 0x04)
                }
                revert(abi.decode(result, (string)));
            }

            results[i] = result;
        }
    }
}
