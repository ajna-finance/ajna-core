// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity 0.8.14;

// produces token descriptors from inconsistent or absent ERC20 symbol implementations that can return string or bytes32
// this library will always produce a string symbol to represent the token

    /**********************/
    /*** View Functions ***/
    /**********************/

    // attempts to extract the token symbol. if it does not implement symbol, returns a symbol derived from the address
    function tokenSymbol(address token) view returns (string memory symbol_) {
        // 0x95d89b41 = bytes4(keccak256("symbol()"))
        symbol_ = _callAndParseStringReturn(token, 0x95d89b41);
        if (bytes(symbol_).length == 0) {
            // fallback to 6 uppercase hex of address string in upper case
            return _toAsciiString(token, 6);
        }
    }

    // attempts to extract the token name. if it does not implement name, returns a name derived from the address
    function tokenName(address token) view returns (string memory name_) {
        // 0x06fdde03 = bytes4(keccak256("name()"))
        name_ = _callAndParseStringReturn(token, 0x06fdde03);
        if (bytes(name_).length == 0) {
            // fallback to full hex of address string in upper case
            return _toAsciiString(token, 40);
        }
    }

    /*************************/
    /*** Utility Functions ***/
    /*************************/

    // calls an external view token contract method that returns a symbol or name, and parses the output into a string
    function _callAndParseStringReturn(address token, bytes4 selector) view returns (string memory) {
        (bool success, bytes memory data) = token.staticcall(abi.encodeWithSelector(selector));
        // if not implemented, or returns empty data, return empty string
        if (!success || data.length == 0) {
            return '';
        }
        // bytes32 data always has length 32
        if (data.length == 32) {
            bytes32 decoded = abi.decode(data, (bytes32));
            return _bytes32ToString(decoded);
        } else if (data.length > 64) {
            return abi.decode(data, (string));
        }
        return '';
    }

    /*********************************/
    /*** Type Conversion Functions ***/
    /*********************************/

    function _bytes32ToString(bytes32 x) pure returns (string memory) {
        bytes memory bytesString = new bytes(32);
        uint256 charCount = 0;
        for (uint256 j = 0; j < 32; j++) {
            bytes1 char = x[j];
            if (char != 0) {
                bytesString[charCount] = char;
                charCount++;
            }
        }
        bytes memory bytesStringTrimmed = new bytes(charCount);
        for (uint256 j = 0; j < charCount; j++) {
            bytesStringTrimmed[j] = bytesString[j];
        }
        return string(bytesStringTrimmed);
    }

    // converts an address to the uppercase hex string, extracting only len bytes (up to 20, multiple of 2)
    function _toAsciiString(address addr, uint256 len) pure returns (string memory) {
        require(len % 2 == 0 && len > 0 && len <= 40, 'SafeERC20Namer: INVALID_LEN');

        bytes memory s = new bytes(len);
        uint256 addrNum = uint256(uint160(addr));
        for (uint256 i = 0; i < len / 2; i++) {
            // shift right and truncate all but the least significant byte to extract the byte at position 19-i
            uint8 b = uint8(addrNum >> (8 * (19 - i)));
            // first hex character is the most significant 4 bits
            uint8 hi = b >> 4;
            // second hex character is the least significant 4 bits
            uint8 lo = b - (hi << 4);
            s[2 * i] = _char(hi);
            s[2 * i + 1] = _char(lo);
        }
        return string(s);
    }

    // hi and lo are only 4 bits and between 0 and 16
    // this method converts those values to the unicode/ascii code point for the hex representation
    // uses upper case for the characters
    function _char(uint8 b) pure returns (bytes1 c) {
        if (b < 10) {
            return bytes1(b + 0x30);
        } else {
            return bytes1(b + 0x37);
        }
    }
