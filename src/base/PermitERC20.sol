// SPDX-License-Identifier: MIT
pragma solidity 0.8.11;

import { IERC20Permit } from "@openzeppelin/contracts/token/ERC20/extensions/draft-IERC20Permit.sol";
import { IERC20 }       from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @notice Interface used by DAI/CHAI for permit
*/
interface IERC20PermitAllowed {

    /**
     * @notice Approve the spender to spend some tokens via the owner signature
     * @dev This is the permit interface used by DAI and CHAI
    */
    function permit(
        address owner_, address spender_, uint256 nonce_, uint256 expiry_, bool allowed_, uint8 v_, bytes32 r_, bytes32 s_
    ) external;

}

/**
 * @notice Functionality to enable EIP-2612 permit calls as part of a multicall batch to avoid seperate token approval transactions.
 * @dev This is intended to be implemented by proxy contracts.
 * @dev IfNecessary methods are added to resolve issues faced by potential front running of Permit: https://eips.ethereum.org/EIPS/eip-2612#security-considerations
 * Front running will result in the permit call failing, but will not enable the loss of any assets.
*/
abstract contract PermitERC20 {

    /**
     * @notice Permits the implementing contract to spend a given amount of a token
     * @dev Spender always assumed to be implementing contract
     * @dev Owner is passed through to enable implementing clone contracts to be called by other contracts.
    */
    function permitToken(
        address owner_, address token_, uint256 value_, uint256 deadline_, uint8 v_, bytes32 r_, bytes32 s_
    ) public payable {
        IERC20Permit(token_).permit(owner_, address(this), value_, deadline_, v_, r_, s_);
    }

    /**
     * @notice Permits the implementing contract to spend a given amount of a token
     * @dev Used to deal with frontrunning of permitToken() calls
     * @dev Spender always assumed to be implementing contract
     * @dev Owner is passed through to enable implementing clone contracts to be called by other contracts.
    */
    function permitTokenIfNecessary(
        address owner_, address token_, uint256 value_, uint256 deadline_, uint8 v_, bytes32 r_, bytes32 s_
    ) external payable {
        if (IERC20(token_).allowance(owner_, address(this)) < value_) {
            permitToken(owner_, token_, value_, deadline_, v_, r_, s_);
        }
    }

    /**
     * @notice Permits the implementing contract to spend a given amount of a token
     * @dev Used by tokens like DAI which have a non-standard Permit() interface
    */
    function permitTokensWithAllowedParam(
        address owner_, address token_, uint256 nonce_, uint256 expiry_, uint8 v_, bytes32 r_, bytes32 s_
    ) public payable {
        IERC20PermitAllowed(token_).permit(owner_, address(this), nonce_, expiry_, true, v_, r_, s_);
    }

    /**
     * @notice Permits the implementing contract to spend a given amount of a token
     * @dev Used by tokens like DAI which have a non-standard Permit() interface
     * @dev Used to deal with frontrunning of permitTokensWithAllowedParam() calls
     * @dev Spender always assumed to be implementing contract
     * @dev Owner is passed through to enable implementing clone contracts to be called by other contracts.
    */
    function permitTokensWithAllowedParamIfNecessary(
        address owner_, address token_, uint256 nonce_, uint256 expiry_, uint8 v_, bytes32 r_, bytes32 s_
    ) external payable {
        if (IERC20(token_).allowance(owner_, address(this)) < type(uint256).max) {
            permitTokensWithAllowedParam(owner_, token_, nonce_, expiry_, v_, r_, s_);
        }
    }

}
