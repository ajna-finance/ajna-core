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

            // Process any failing calls and revert the transaction accordingly
            if (!success) {
                handleRevert(result);
            }

            results[i] = result;

            // increment call counter in gas efficient way
            unchecked {
                ++i;
            }
        }
    }

    /// @notice Processes and bubbles up the relevent revert from a failing call
    /// @dev Supports Panic, Error, and Custom Errors
    /// @dev Retrieved from discussion here: https://ethereum.stackexchange.com/a/123588
    /// @dev Based upon Superfluid code: https://github.com/superfluid-finance/protocol-monorepo/blob/dev/packages/ethereum-contracts/contracts/libs/CallUtils.sol
    /// @param _result The failing call result to process and bubble up revert from
    function handleRevert(bytes memory _result) internal pure {
        uint256 len = _result.length;

        if (len < 4) {
            revert("Multicall: transaction reverted silently");
        }

        bytes4 errorSelector;
        assembly {
            errorSelector := mload(add(_result, 0x20))
        }

        // handle Panic(uint256) built in errors
        // seth sig "Panic(uint256)" == 0x4e487b71
        // ref: https://docs.soliditylang.org/en/v0.8.0/control-structures.html#panic-via-assert-and-error-via-require)
        if (errorSelector == bytes4(0x4e487b71)) {
            string memory reason = "Multicall: target panicked: 0x__";
            uint256 errorCode;
            assembly {
                errorCode := mload(add(_result, 0x24))
                let reasonWord := mload(add(reason, 0x20))
                // [0..9] is converted to ['0'..'9']
                // [0xa..0xf] is not correctly converted to ['a'..'f']
                // but since panic code doesn't have those cases, we will ignore them for now!
                let e1 := add(and(errorCode, 0xf), 0x30)
                let e2 := shl(8, add(shr(4, and(errorCode, 0xf0)), 0x30))
                reasonWord := or(
                    and(
                        reasonWord,
                        0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff0000
                    ),
                    or(e2, e1)
                )
                mstore(add(reason, 0x20), reasonWord)
            }
            revert(reason);
        } else {
            // handle custom errors
            // handle errors with strings
            assembly {
                revert(add(_result, 32), len)
            }
        }
    }
}
