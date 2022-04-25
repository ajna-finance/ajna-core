// SPDX-License-Identifier: MIT

pragma solidity 0.8.11;

/// @notice Functionality to enable contracts to implement multicall method for method call aggregation into single transactions
/// @dev Implementing multicall internally enables gas savings compared to making a call to externally deployed contracts
abstract contract Multicall {
    /// @notice Make a series of contract calls in a single transaction
    /// @param data Externally aggregated function calls serialized into a byte array
    /// @return results Array of the results from each aggregated call
    function multicall(bytes[] calldata data) public returns (bytes[] memory results) {
        results = new bytes[](data.length);
        for (uint256 i = 0; i < data.length; ) {
            (bool success, bytes memory result) = address(this).delegatecall(data[i]);

            // retrieve revert reason as a string
            if (!success) {
                revert(_getRevertMsg(result));
            }

            results[i] = result;

            // increment call counter in gas efficient way
            unchecked {
                ++i;
            }
        }
    }

    /// @notice Get the revert reason from a delagtecall that failed
    /// @dev Retrieved from discussion here: https://ethereum.stackexchange.com/a/83577
    /// @param _response The response of the call to retrieve reason from
    /// @return reason String describing revert reason
    function _getRevertMsg(bytes memory _response) internal pure returns (string memory reason) {
        uint256 length = _response.length;
        if (length < 68) {
            return "Transaction reverted silently";
        }
        uint256 t;
        assembly {
            _response := add(_response, 4)
            t := mload(_response) // Save the content of the length slot
            mstore(_response, sub(length, 4)) // Set proper length
        }
        reason = abi.decode(_response, (string));
        assembly {
            mstore(_response, t) // Restore the content of the length slot
        }
    }
}
