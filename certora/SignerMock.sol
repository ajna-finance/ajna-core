// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.14;

contract SignerMock {
    bytes32 sig;

    function isValidSignature(bytes32, bytes memory) external view returns (bytes32) {
        return sig;
    }
}
