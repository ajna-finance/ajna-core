// SPDX-License-Identifier: MIT
pragma solidity 0.8.14;

/**
 * @title Pool Immutables
 */
interface IPoolImmutables {

    /**
     *  @notice Returns the address of the pool's collateral token
     */
    function collateralAddress() external pure returns (address);

    /**
     *  @notice Returns the `minFee` state variable.
     *  @return minimum fee that can be applied for early withdraw penalty
     */
    function minFee() external view returns (uint256);

    /**
     *  @notice Returns the address of the pools quote token
     */
    function quoteTokenAddress() external pure returns (address);

    /**
     *  @notice Returns the `quoteTokenScale` state variable.
     *  @return The precision of the quote ERC-20 token based on decimals.
     */
    function quoteTokenScale() external view returns (uint256);
}