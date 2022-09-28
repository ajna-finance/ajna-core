// SPDX-License-Identifier: MIT

pragma solidity 0.8.14;

/**
 * @title ERC20 Pool Errors
 */
interface IERC20PoolErrors {

    /**
     *  @notice Lender is attempting to remove collateral when they have no claim to collateral in the bucket.
     */
    error RemoveCollateralNoClaim();
}