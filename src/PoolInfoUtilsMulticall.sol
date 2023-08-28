// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.18;

import { PoolInfoUtils } from "./PoolInfoUtils.sol";

contract PoolInfoUtilsMulticall {

    PoolInfoUtils public immutable poolInfoUtils;

    struct PoolPriceInfo {
        uint256 hpb;
        uint256 hpbIndex;
        uint256 htp;
        uint256 htpIndex;
        uint256 lup;
        uint256 lupIndex;
    }

    struct PoolReservesInfo {
        uint256 reserves;
        uint256 claimableReserves;
        uint256 claimableReservesRemaining;
        uint256 auctionPrice;
        uint256 timeRemaining;
    }

    struct PoolUtilizationInfo {
        uint256 poolMinDebtAmount;
        uint256 poolCollateralization;
        uint256 poolActualUtilization;
        uint256 poolTargetUtilization;
    }

    struct BucketInfo {
        uint256 price;
        uint256 quoteTokens;
        uint256 collateral;
        uint256 bucketLP;
        uint256 scale;
        uint256 exchangeRate;
    }

    struct PoolRatesAndFeesInfo {
        uint256 lenderInterestMargin;
        uint256 borrowFeeRate;
        uint256 depositFeeRate;
    }

    constructor(PoolInfoUtils poolInfoUtils_) {
        poolInfoUtils = poolInfoUtils_;
    }

    function poolDetailsAndBucketInfo(address pool_, uint256 bucketIndex) 
        external 
        view 
        returns(
            PoolPriceInfo memory poolPriceInfo_,
            PoolReservesInfo memory poolReservesInfo_,
            PoolUtilizationInfo memory poolUtilizationInfo_,
            BucketInfo memory bucketInfo_
        )
    {
        (
            poolPriceInfo_.hpb,
            poolPriceInfo_.hpbIndex,
            poolPriceInfo_.htp,
            poolPriceInfo_.htpIndex,
            poolPriceInfo_.lup,
            poolPriceInfo_.lupIndex
        ) = poolInfoUtils.poolPricesInfo(pool_);

        (
            poolReservesInfo_.reserves,
            poolReservesInfo_.claimableReserves,
            poolReservesInfo_.claimableReservesRemaining,
            poolReservesInfo_.auctionPrice,
            poolReservesInfo_.timeRemaining
        ) = poolInfoUtils.poolReservesInfo(pool_);

        (
            poolUtilizationInfo_.poolMinDebtAmount,
            poolUtilizationInfo_.poolCollateralization,
            poolUtilizationInfo_.poolActualUtilization,
            poolUtilizationInfo_.poolTargetUtilization
        ) = poolInfoUtils.poolUtilizationInfo(pool_);
        
        (
            bucketInfo_.price,
            bucketInfo_.quoteTokens,
            bucketInfo_.collateral,
            bucketInfo_.bucketLP,
            bucketInfo_.scale,
            bucketInfo_.exchangeRate
        ) = poolInfoUtils.bucketInfo(pool_, bucketIndex);
    }

    function poolRatesAndFees(address pool_)
        external 
        view 
        returns
        (
            PoolRatesAndFeesInfo memory poolRatesAndFeesInfo
        )
    {
        poolRatesAndFeesInfo.lenderInterestMargin = poolInfoUtils.lenderInterestMargin(pool_);
        poolRatesAndFeesInfo.borrowFeeRate        = poolInfoUtils.borrowFeeRate(pool_);
        poolRatesAndFeesInfo.depositFeeRate       = poolInfoUtils.unutilizedDepositFeeRate(pool_);
    }

    function multicall(string[] calldata functionSignatures_, string[] calldata args_) external returns(
        bytes[] memory results
    ) {
        uint256 currentIndex = 0;
        results = new bytes[](functionSignatures_.length);
        for(uint256 i = 0; i < functionSignatures_.length; i++) {
            string[] memory parameters = _parseFunctionSignature(functionSignatures_[i]);
            uint256 noOfParams = parameters.length;
            bytes memory callData;
            if (noOfParams == 1) {
                if (keccak256(bytes(parameters[0])) == keccak256(bytes("uint256"))) {
                    uint256 arg = _stringToUint(args_[currentIndex]);
                    callData    = abi.encodeWithSignature(functionSignatures_[i], arg);
                }
                if (keccak256(bytes(parameters[0])) == keccak256(bytes("address"))) {
                    address arg = _stringToAddress(args_[currentIndex]);
                    callData    = abi.encodeWithSignature(functionSignatures_[i], arg);
                }
            }

            if (noOfParams == 2) {
                if (keccak256(bytes(parameters[1])) == keccak256(bytes("uint256"))) {
                    address arg1 = _stringToAddress(args_[currentIndex]);
                    uint256 arg2 = _stringToUint(args_[currentIndex + 1]);
                    callData     = abi.encodeWithSignature(functionSignatures_[i], arg1, arg2);
                }
                if (keccak256(bytes(parameters[1])) == keccak256(bytes("address"))) {
                    address arg1 = _stringToAddress(args_[currentIndex]);
                    address arg2 = _stringToAddress(args_[currentIndex + 1]);
                    callData     = abi.encodeWithSignature(functionSignatures_[i], arg1, arg2);
                }
            }

            if (noOfParams == 3) {
                address arg1 = _stringToAddress(args_[currentIndex]);
                uint256 arg2 = _stringToUint(args_[currentIndex + 1]);
                uint256 arg3 = _stringToUint(args_[currentIndex + 2]);
                callData     = abi.encodeWithSignature(functionSignatures_[i], arg1, arg2, arg3);
            }

            currentIndex += noOfParams;
            (, results[i]) = address(poolInfoUtils).call(callData);
        }
    }

    function _parseFunctionSignature(string memory signature) public pure returns (string[] memory) {
        // Remove the opening and closing parentheses from the signature
        signature = _removeParentheses(signature);

        // Split the parameters using commas
        string[] memory parameterTypes = _splitString(signature, ",");

        return parameterTypes;
    }

    function _removeParentheses(string memory str) internal pure returns (string memory) {
        // Remove leading and trailing whitespaces
        str = _trimFunctionName(str);

        // Check if the string starts with '(' and ends with ')'
        if (bytes(str).length >= 2 && bytes(str)[0] == bytes("(")[0] && bytes(str)[bytes(str).length - 1] == bytes(")")[0]) {
            // Remove the first and last characters
            str = _substring(str, 1, bytes(str).length - 2);
        }
        return str;
    }

    function _splitString(string memory str, string memory delimiter) internal pure returns (string[] memory) {
        uint256 numDelimiters = _countOccurrences(str, delimiter) + 1;
        string[] memory parts = new string[](numDelimiters);

        uint256 currentIndex = 0;
        for (uint256 i = 0; i < numDelimiters - 1; i++) {
            uint256 delimiterIndex = uint256(_indexOf(str, delimiter, currentIndex));
            parts[i] = _substring(str, currentIndex, delimiterIndex - 1);
            currentIndex = delimiterIndex + bytes(delimiter).length;
        }
        parts[numDelimiters - 1] = _substring(str, currentIndex, bytes(str).length - 1);

        return parts;
    }

    function _trimFunctionName(string memory str) internal pure returns (string memory) {
        uint256 start = 0;
        uint256 end = bytes(str).length - 1;

        while (start <= end && bytes(str)[start] != bytes("(")[0]) {
            start++;
        }

        if (end >= start) {
            return _substring(str, start, end);
        } else {
            return "";
        }
    }

    function _countOccurrences(string memory str, string memory pattern) internal pure returns (uint256 count) {
        uint256 lastIndex = 0;
        while (_indexOf(str, pattern, lastIndex) != int256(-1)) {
            lastIndex = uint256(_indexOf(str, pattern, lastIndex)) + bytes(pattern).length;
            count++;
        }
        return count;
    }

    function _indexOf(string memory str, string memory pattern, uint256 startIndex) internal pure returns (int256) {
        bytes memory strBytes = bytes(str);
        bytes memory patternBytes = bytes(pattern);

        for (uint256 i = startIndex; i <= strBytes.length - patternBytes.length; i++) {
            bool found = true;
            for (uint256 j = 0; j < patternBytes.length; j++) {
                if (strBytes[i + j] != patternBytes[j]) {
                    found = false;
                    break;
                }
            }
            if (found) {
                return int256(i);
            }
        }
        return int256(-1);
    }

    function _substring(string memory str, uint256 startIndex, uint256 endIndex) internal pure returns (string memory) {
        require(startIndex <= endIndex, "Invalid substring indices");
        bytes memory strBytes = bytes(str);
        bytes memory result = new bytes(endIndex - startIndex + 1);

        for (uint256 i = startIndex; i <= endIndex; i++) {
            result[i - startIndex] = strBytes[i];
        }

        return string(result);
    }

    function _stringToUint(string memory s) internal pure returns (uint256) {
        bytes memory b = bytes(s);
        uint256 result = 0;
        for (uint256 i = 0; i < b.length; i++) {
            uint256 val = uint256(uint8(b[i]));
            if (val >= 48 && val <= 57) {
                result = result * 10 + (val - 48);
            }
        }
        return result;
    }

    function _fromHexChar(uint8 c) internal pure returns (uint8) {
        if (bytes1(c) >= bytes1('0') && bytes1(c) <= bytes1('9')) {
            return c - uint8(bytes1('0'));
        }
        if (bytes1(c) >= bytes1('a') && bytes1(c) <= bytes1('f')) {
            return 10 + c - uint8(bytes1('a'));
        }
        if (bytes1(c) >= bytes1('A') && bytes1(c) <= bytes1('F')) {
            return 10 + c - uint8(bytes1('A'));
        }
        return 0;
    }
    
    function _hexStringToAddress(string calldata s) internal pure returns (bytes memory) {
        bytes memory ss = bytes(s);
        require(ss.length%2 == 0); // length must be even
        bytes memory r = new bytes(ss.length/2);
        for (uint i = 0; i < ss.length/2; ++i) {
            r[i] = bytes1(_fromHexChar(uint8(ss[2*i])) * 16 + _fromHexChar(uint8(ss[2*i+1])));
        }

        return r;
    }

    function _stringToAddress(string calldata s) internal pure returns (address) {
        bytes memory _bytes = _hexStringToAddress(s);
        require(_bytes.length >= 1 + 20, "toAddress_outOfBounds");
        address tempAddress;

        assembly {
            tempAddress := div(mload(add(add(_bytes, 0x20), 1)), 0x1000000000000000000000000)
        }

        return tempAddress;
    }
}