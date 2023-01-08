// SPDX-License-Identifier: MIT

pragma solidity 0.8.14;

/**
 * @title ERC20 Pool Immutables
 */
interface IERC20PoolImmutables {

    /**
     *  @notice Returns the `collateralScale` immutable.
     *  @return The precision of the collateral ERC-20 token based on decimals.
     */
    function collateralScale() external view returns (uint256);

}