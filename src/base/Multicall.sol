// SPDX-License-Identifier: MIT

pragma solidity 0.8.11;

import {console} from "@hardhat/hardhat-core/console.sol"; // TESTING ONLY

/// @notice Functionality to enable contracts to implement multicall method for method call aggregation into single transactions
/// @dev Implementing multicall internally enables gas savings compared to making a call to externally deployed contracts
abstract contract Multicall {

    /// @notice Make a series of contract calls in a single transaction 
    /// @param data Externally aggregated function calls serialized into a byte array
    /// @return results Array of the results from each aggregated call
    function multicall(bytes[] calldata data) public returns (bytes[] memory results) {
        results = new bytes[](data.length);
        for (uint256 i = 0; i < data.length;) {
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

            // increment call counter in gas efficient way
            unchecked {++i; }
        }
    }
}
