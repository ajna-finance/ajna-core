// SPDX-License-Identifier: MIT

pragma solidity 0.8.14;

/**
 * @title Pool State
 */
interface IPoolState {

    /**
     *  @notice Returns the `interestRate` state variable.
     *  @return Current annual percentage rate of the pool
     */
    function interestRate() external view returns (uint208);

    /**
     *  @notice Returns the `interestRateUpdate` state variable.
     *  @return The timestamp of the last rate update.
     */
    function interestRateUpdate() external view returns (uint48);

    function pledgedCollateral() external view returns (uint256);

}