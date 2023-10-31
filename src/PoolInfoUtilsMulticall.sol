// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.18;

import { Multicall } from '@openzeppelin/contracts/utils/Multicall.sol';
import { IERC20 } from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import { IERC721 } from "@openzeppelin/contracts/token/ERC721/IERC721.sol";

import { PoolInfoUtils } from "./PoolInfoUtils.sol";

import { IPool } from "./interfaces/pool/IPool.sol";
import { IERC20Pool } from "./interfaces/pool/erc20/IERC20Pool.sol";

contract PoolInfoUtilsMulticall {

    PoolInfoUtils public immutable poolInfoUtils;

    struct PoolLoansInfo {
        uint256 poolSize;
        uint256 loansCount;
        address maxBorrower;
        uint256 pendingInflator;
        uint256 pendingInterestFactor;
    }

    struct PoolPriceInfo {
        uint256 hpb;
        uint256 hpbIndex;
        uint256 htp;
        uint256 htpIndex;
        uint256 lup;
        uint256 lupIndex;
    }

    struct PoolRatesAndFees {
        uint256 lenderInterestMargin;
        uint256 borrowFeeRate;
        uint256 depositFeeRate;
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

    struct PoolBalanceDetails {
        uint256 debt;                   // debtInfo()
        uint256 accruedDebt;            // debtInfo()
        uint256 debtInAuction;          // debtInfo()
        uint256 t0Debt2ToCollateral;    // debtInfo()
        uint256 depositUpToIndex;
        uint256 quoteTokenBalance;
        uint256 collateralTokenBalance;
    }

    constructor(PoolInfoUtils poolInfoUtils_) {
        poolInfoUtils = poolInfoUtils_;
    }

    /**
     *  @notice Retrieves PoolLoansInfo, PoolPriceInfo, PoolRatesAndFees, PoolReservesInfo and PoolUtilizationInfo
     *  @dev    This function is used to retrieve pool details available from PoolInfoUtils in a single RPC call for Indexers.
     *  @param  ajnaPool_    Address of `Ajna` pool
     *  @return poolLoansInfo_       Pool loans info struct
     *  @return poolPriceInfo_       Pool price info struct
     *  @return poolRatesAndFees_    Pool rates and fees struct
     *  @return poolReservesInfo_    Pool reserves info struct
     *  @return poolUtilizationInfo_ Pool utilization info struct
     */
    function poolDetailsMulticall(address ajnaPool_) external view returns (
        PoolLoansInfo memory poolLoansInfo_,
        PoolPriceInfo memory poolPriceInfo_,
        PoolRatesAndFees memory poolRatesAndFees_,
        PoolReservesInfo memory poolReservesInfo_,
        PoolUtilizationInfo memory poolUtilizationInfo_
    ) {
        // retrieve loans info
        (
            poolLoansInfo_.poolSize,
            poolLoansInfo_.loansCount,
            poolLoansInfo_.maxBorrower,
            poolLoansInfo_.pendingInflator,
            poolLoansInfo_.pendingInterestFactor
        ) = poolInfoUtils.poolLoansInfo(ajnaPool_);

        // retrieve prices info
        (
            poolPriceInfo_.hpb,
            poolPriceInfo_.hpbIndex,
            poolPriceInfo_.htp,
            poolPriceInfo_.htpIndex,
            poolPriceInfo_.lup,
            poolPriceInfo_.lupIndex
        ) = poolInfoUtils.poolPricesInfo(ajnaPool_);

        // retrieve rates and fees
        poolRatesAndFees_.lenderInterestMargin = poolInfoUtils.lenderInterestMargin(ajnaPool_);
        poolRatesAndFees_.borrowFeeRate        = poolInfoUtils.borrowFeeRate(ajnaPool_);
        poolRatesAndFees_.depositFeeRate       = poolInfoUtils.unutilizedDepositFeeRate(ajnaPool_);

        // retrieve reserves info
        (
            poolReservesInfo_.reserves,
            poolReservesInfo_.claimableReserves,
            poolReservesInfo_.claimableReservesRemaining,
            poolReservesInfo_.auctionPrice,
            poolReservesInfo_.timeRemaining
        ) = poolInfoUtils.poolReservesInfo(ajnaPool_);

        // retrieve utilization info
        (
            poolUtilizationInfo_.poolMinDebtAmount,
            poolUtilizationInfo_.poolCollateralization,
            poolUtilizationInfo_.poolActualUtilization,
            poolUtilizationInfo_.poolTargetUtilization
        ) = poolInfoUtils.poolUtilizationInfo(ajnaPool_);
    }

    /**
     *  @notice Retrieves info of lenderInterestMargin, borrowFeeRate and depositFeeRate
     *  @param  ajnaPool_            Address of `Ajna` pool
     *  @return lenderInterestMargin Lender interest margin in pool
     *  @return borrowFeeRate        Borrow fee rate calculated from the pool interest ra
     *  @return depositFeeRate       Deposit fee rate calculated from the pool interest rate
     */
    function poolRatesAndFeesMulticall(address ajnaPool_)
        external
        returns
        (
            uint256 lenderInterestMargin,
            uint256 borrowFeeRate,
            uint256 depositFeeRate
        )
    {
        lenderInterestMargin = poolInfoUtils.lenderInterestMargin(ajnaPool_);
        borrowFeeRate        = poolInfoUtils.borrowFeeRate(ajnaPool_);
        depositFeeRate       = poolInfoUtils.unutilizedDepositFeeRate(ajnaPool_);
    }

    /**
        *  @notice Retrieves pool debtInfo, depositUpToIndex, quoteTokenBalance and collateralTokenBalance
        *  @dev    This function is used to retrieve pool balance details in a single RPC call for Indexers.
        *  @param  ajnaPool_               Address of `Ajna` pool
        *  @param  index_                  Index of deposit
        *  @param  quoteTokenAddress_      Address of quote token
        *  @param  collateralTokenAddress_ Address of collateral token
        *  @param  isNFT_                  Boolean indicating if the pool is an NFT pool
        *  @return poolBalanceDetails_     Pool balance details struct
     */
    function poolBalanceDetails(address ajnaPool_, uint256 index_, address quoteTokenAddress_, address collateralTokenAddress_, bool isNFT_)
        external view
        returns (PoolBalanceDetails memory poolBalanceDetails_)
    {
        IPool pool = IPool(ajnaPool_);

        // pool debtInfo
        (poolBalanceDetails_.debt, poolBalanceDetails_.accruedDebt, poolBalanceDetails_.debtInAuction, poolBalanceDetails_.t0Debt2ToCollateral) = pool.debtInfo();

        // depositUpToIndex(index_)
        poolBalanceDetails_.depositUpToIndex = pool.depositUpToIndex(index_);

        // get pool quote token balance
        uint256 poolQuoteBalance = IERC20(quoteTokenAddress_).balanceOf(ajnaPool_);
        uint256 quoteScale = pool.quoteTokenScale();
        // normalize token balance to WAD scale
        poolBalanceDetails_.quoteTokenBalance = poolQuoteBalance * quoteScale;

        // get pool collateral token balance
        if (isNFT_) {
            // convert whole NFT amounts to WAD to match pool accounting
            poolBalanceDetails_.collateralTokenBalance = IERC721(collateralTokenAddress_).balanceOf(ajnaPool_) * 10**18;
        } else {
            // normalize token balance to WAD scale
            uint256 collateralScale = IERC20Pool(ajnaPool_).collateralScale();
            uint256 poolCollateralBalance = IERC20(collateralTokenAddress_).balanceOf(ajnaPool_);
            poolBalanceDetails_.collateralTokenBalance = poolCollateralBalance * collateralScale;
        }
    }

    /**
     *  @notice Aggregate results from multiple read-only function calls
     *  @param  functionSignatures_ Array of signatures of read-only functions to be called
     *  @param  args_               Array of serialized function arguments of all read-only functions to called
     *  @return results_            Array of result of all read-only function calls in bytes
     */
    function multicall(string[] calldata functionSignatures_, string[] calldata args_) external returns (bytes[] memory results_) {
        uint256 currentIndex = 0;
        results_ = new bytes[](functionSignatures_.length);
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
            (, results_[i]) = address(poolInfoUtils).call(callData);
        }
    }

    // Returns all function parameters
    function _parseFunctionSignature(string memory signature_) internal pure returns (string[] memory parameters_) {
        // Remove the function name and parentheses from the signature
        string memory parametersString = _removeParentheses(signature_);

        parameters_ = _splitString(parametersString, ",");
    }

    // Remove function name and Parentheses from signature
    function _removeParentheses(string memory signature_) internal pure returns (string memory trimmedSignature_) {
        // Remove function name
        trimmedSignature_ = _trimFunctionName(signature_);

        // Check if the string starts with '(' and ends with ')'
        if (bytes(trimmedSignature_).length >= 2 && bytes(trimmedSignature_)[0] == bytes("(")[0] && bytes(trimmedSignature_)[bytes(trimmedSignature_).length - 1] == bytes(")")[0]) {
            // Remove the first and last characters
            trimmedSignature_ = _substring(trimmedSignature_, 1, bytes(trimmedSignature_).length - 2);
        }
    }

    // Splits a string into an array of strings using a specified delimiter
    function _splitString(string memory str_, string memory delimiter_) internal pure returns (string[] memory parts_) {
        uint256 numDelimiters = _countOccurrences(str_, delimiter_) + 1;
        parts_ = new string[](numDelimiters);

        uint256 currentIndex = 0;
        for (uint256 i = 0; i < numDelimiters - 1; i++) {
            uint256 delimiterIndex = uint256(_indexOf(str_, delimiter_, currentIndex));
            parts_[i] = _substring(str_, currentIndex, delimiterIndex - 1);
            currentIndex = delimiterIndex + bytes(delimiter_).length;
        }
        parts_[numDelimiters - 1] = _substring(str_, currentIndex, bytes(str_).length - 1);
    }

    // Removes the function name from a string
    function _trimFunctionName(string memory str_) internal pure returns (string memory) {
        uint256 start = 0;
        uint256 end = bytes(str_).length - 1;

        while (start <= end && bytes(str_)[start] != bytes("(")[0]) {
            start++;
        }

        if (end >= start) {
            return _substring(str_, start, end);
        } else {
            return "";
        }
    }

    // Counts the occurrences of a pattern within a string
    function _countOccurrences(string memory str_, string memory pattern_) internal pure returns (uint256 count_) {
        uint256 lastIndex = 0;
        while (_indexOf(str_, pattern_, lastIndex) != int256(-1)) {
            lastIndex = uint256(_indexOf(str_, pattern_, lastIndex)) + bytes(pattern_).length;
            count_++;
        }
    }

    // Finds the index of a pattern within a string
    function _indexOf(string memory str_, string memory pattern_, uint256 startIndex_) internal pure returns (int256) {
        bytes memory strBytes = bytes(str_);
        bytes memory patternBytes = bytes(pattern_);

        for (uint256 i = startIndex_; i <= strBytes.length - patternBytes.length; i++) {
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

    // Extracts a substring from a given string
    function _substring(string memory str_, uint256 startIndex_, uint256 endIndex_) internal pure returns (string memory) {
        require(startIndex_ <= endIndex_, "Invalid substring indices");
        bytes memory strBytes = bytes(str_);
        bytes memory result = new bytes(endIndex_ - startIndex_ + 1);

        for (uint256 i = startIndex_; i <= endIndex_; i++) {
            result[i - startIndex_] = strBytes[i];
        }

        return string(result);
    }

    // Converts a string to an unsigned integer
    function _stringToUint(string memory str_) internal pure returns (uint256 result_) {
        bytes memory strBytes = bytes(str_);
        for (uint256 i = 0; i < strBytes.length; i++) {
            uint256 val = uint256(uint8(strBytes[i]));
            if (val >= 48 && val <= 57) {
                result_ = result_ * 10 + (val - 48);
            }
        }
    }

    // Converts a hexadecimal character to its decimal value
    function _hexCharToDecimal(uint8 character_) internal pure returns (uint8) {
        if (bytes1(character_) >= bytes1('0') && bytes1(character_) <= bytes1('9')) {
            return character_ - uint8(bytes1('0'));
        }
        if (bytes1(character_) >= bytes1('a') && bytes1(character_) <= bytes1('f')) {
            return 10 + character_ - uint8(bytes1('a'));
        }
        if (bytes1(character_) >= bytes1('A') && bytes1(character_) <= bytes1('F')) {
            return 10 + character_ - uint8(bytes1('A'));
        }
        return 0;
    }
    
    // Converts a hexadecimal string to bytes
    function _hexStringToBytes(string memory str_) internal pure returns (bytes memory bytesString_) {
        bytes memory strBytes = bytes(str_);
        require(strBytes.length % 2 == 0); // length must be even
        bytesString_ = new bytes(strBytes.length / 2);
        for (uint i = 1; i < strBytes.length / 2; ++i) {
            bytesString_[i] = bytes1(_hexCharToDecimal(uint8(strBytes[2 * i])) * 16 + _hexCharToDecimal(uint8(strBytes[2 * i + 1])));
        }
    }

    // Converts a hexadecimal string to an Ethereum address
    function _stringToAddress(string calldata str_) internal pure returns (address tempAddress_) {
        bytes memory strBytes = _hexStringToBytes(str_);
        require(strBytes.length >= 1 + 20, "toAddress_outOfBounds");

        assembly {
            tempAddress_ := div(mload(add(add(strBytes, 0x20), 1)), 0x1000000000000000000000000)
        }
    }
}