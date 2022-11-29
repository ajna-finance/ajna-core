// SPDX-License-Identifier: MIT
pragma solidity 0.8.14;

/**
 * @title ERC20 Pool State
 */
interface IERC20PoolState {

    /**
     *  @notice Returns the `collateralScale` state variable.
     *  @return The precision of the collateral ERC-20 token based on decimals.
     */
    function collateralScale() external view returns (uint128);

}