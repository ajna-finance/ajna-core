// SPDX-License-Identifier: MIT

pragma solidity 0.8.14;

/**
 * @title Pool Derived State
 */
interface IPoolDerivedState {

    /**
     *  @notice Returns the bucket exchange rate.
     *  @param  index  Bucket index.
     *  @return Bucket exchange rate.
     */
    function bucketExchangeRate(
        uint256 index
    ) external view returns (uint256);

    /**
     *  @notice Returns the bucket index for a given debt amount.
     *  @param  debt  The debt amount to calculate bucket index for.
     *  @return Bucket index.
     */
    function depositIndex(
        uint256 debt
    ) external view returns (uint256);

    /**
     *  @notice Returns the total amount of quote tokens deposited in pool.
     *  @return Total amount of deposited quote tokens.
     */
    function depositSize() external view returns (uint256);

    /**
     *  @notice Returns the deposit utilization for given debt and collateral amounts.
     *  @param  debt       The debt amount to calculate utilization for.
     *  @param  collateral The collateral amount to calculate utilization for.
     *  @return Deposit utilization.
     */
    function depositUtilization(
        uint256 debt,
        uint256 collateral
    ) external view returns (uint256);

}