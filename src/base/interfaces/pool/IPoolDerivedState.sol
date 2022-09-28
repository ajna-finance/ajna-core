// SPDX-License-Identifier: MIT

pragma solidity 0.8.14;

/**
 * @title Pool Derived State
 */
interface IPoolDerivedState {

    /**
     *  @notice Returns the amount of quote tokens deposited at a given bucket.
     *  @param  index_  The price bucket index for which the value should be calculated.
     *  @return Amount of quote tokens in bucket.
     */
    function bucketDeposit(
        uint256 index_
    ) external view returns (uint256);

    /**
     *  @notice Returns the multiplier of a given bucket.
     *  @param  index_  The price bucket index for which the value should be calculated.
     *  @return Bucket multiplier.
     */
    function bucketScale(
        uint256 index_
    ) external view returns (uint256);

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
     *  @notice Returns the deposit utilization for given debt and collateral amounts.
     *  @param  debt_       The debt amount to calculate utilization for.
     *  @param  collateral_ The collateral amount to calculate utilization for.
     *  @return Deposit utilization.
     */
    function depositUtilization(
        uint256 debt_,
        uint256 collateral_
    ) external view returns (uint256);

    /**
     *  @notice Calculate the amount of quote tokens for a given amount of LP Tokens.
     *  @param  deposit_     The amount of quote tokens available at this bucket index.
     *  @param  lpTokens_    The number of lpTokens to calculate amounts for.
     *  @param  index_       The price bucket index for which the value should be calculated.
     *  @return quoteAmount_ The exact amount of quote tokens that can be exchanged for the given LP Tokens, WAD units.
     */
    function lpsToQuoteTokens(
        uint256 deposit_,
        uint256 lpTokens_,
        uint256 index_
    ) external view returns (uint256 quoteAmount_);

}