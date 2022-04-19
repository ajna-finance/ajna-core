// SPDX-License-Identifier: MIT
pragma solidity 0.8.11;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/draft-IERC20Permit.sol";

/// @notice Interface used by DAI/CHAI for permit
interface IERC20PermitAllowed {
    /// @notice Approve the spender to spend some tokens via the owner signature
    /// @dev This is the permit interface used by DAI and CHAI
    function permit(
        address owner,
        address spender,
        uint256 nonce,
        uint256 expiry,
        bool allowed,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external;
}

/// @notice Functionality to enable EIP-2612 permit calls as part of a multicall batch to avoid seperate token approval transactions.
/// @dev This is intended to be implemented by proxy contracts.
/// @dev IfNecessary methods are added to resolve issues faced by potential front running of Permit: https://eips.ethereum.org/EIPS/eip-2612#security-considerations
/// Front running will result in the permit call failing, but will not enable the loss of any assets.
abstract contract PermitERC20 {
    /// @notice Permits the implementing contract to spend a given amount of a token
    /// @dev Spender always assumed to be implementing contract
    /// @dev Owner is passed through to enable implementing clone contracts to be called by other contracts.
    function permitToken(
        address owner,
        address token,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) public payable {
        IERC20Permit(token).permit(owner, address(this), value, deadline, v, r, s);
    }

    /// @notice Permits the implementing contract to spend a given amount of a token
    /// @dev Used to deal with frontrunning of permitToken() calls
    /// @dev Spender always assumed to be implementing contract
    /// @dev Owner is passed through to enable implementing clone contracts to be called by other contracts.
    function permitTokenIfNecessary(
        address owner,
        address token,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external payable {
        if (IERC20(token).allowance(owner, address(this)) < value) {
            permitToken(owner, token, value, deadline, v, r, s);
        }
    }

    /// @notice Permits the implementing contract to spend a given amount of a token
    /// @dev Used by tokens like DAI which have a non-standard Permit() interface
    function permitTokensWithAllowedParam(
        address owner,
        address token,
        uint256 nonce,
        uint256 expiry,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) public payable {
        IERC20PermitAllowed(token).permit(owner, address(this), nonce, expiry, true, v, r, s);
    }

    /// @notice Permits the implementing contract to spend a given amount of a token
    /// @dev Used by tokens like DAI which have a non-standard Permit() interface
    /// @dev Used to deal with frontrunning of permitTokensWithAllowedParam() calls
    /// @dev Spender always assumed to be implementing contract
    /// @dev Owner is passed through to enable implementing clone contracts to be called by other contracts.
    function permitTokensWithAllowedParamIfNecessary(
        address owner,
        address token,
        uint256 nonce,
        uint256 expiry,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external payable {
        if (IERC20(token).allowance(owner, address(this)) < type(uint256).max) {
            permitTokensWithAllowedParam(owner, token, nonce, expiry, v, r, s);
        }
    }
}
