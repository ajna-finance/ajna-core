// SPDX-License-Identifier: MIT

pragma solidity 0.8.14;

/**
 * @title Pool Derived State
 */
interface IPoolDerivedState {

    function bucketExchangeRate(
        uint256 index_
    ) external view returns (uint256 exchangeRate_);

    /**
     *  @notice Returns the bucket index for a given debt amount.
     *  @param  debt_  The debt amount to calculate bucket index for.
     *  @return Bucket index.
     */
    function depositIndex(
        uint256 debt_
    ) external view returns (uint256);

    /**
     *  @notice Returns the total amount of quote tokens deposited in pool.
     *  @return Total amount of deposited quote tokens.
     */
    function depositSize() external view returns (uint256);

    /**
     *  @notice Returns the meaningful actual utilization of the pool.
     *  @return Deposit utilization.
     */
    function depositUtilization() external view returns (uint256);

}