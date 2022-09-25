// SPDX-License-Identifier: MIT
pragma solidity 0.8.14;

/**
 * @title Ajna Pool Derived State
 */
interface IAjnaPoolDerivedState {

    function bucketDeposit(
        uint256 index_
    ) external view returns (uint256);

    function bucketScale(
        uint256 index_
    ) external view returns (uint256);

    function depositSize() external view returns (uint256);

    function depositIndex(
        uint256 debt
    ) external view returns (uint256);

    function depositUtilization(
        uint256 debt,
        uint256 collateral
    ) external view returns (uint256);

    /**
     *  @notice Calculate the amount of quote tokens for a given amount of LP Tokens.
     *  @param  deposit     The amount of quote tokens available at this bucket index.
     *  @param  lpTokens    The number of lpTokens to calculate amounts for.
     *  @param  index       The price bucket index for which the value should be calculated.
     *  @return quoteAmount The exact amount of quote tokens that can be exchanged for the given LP Tokens, WAD units.
     */
    function lpsToQuoteTokens(
        uint256 deposit,
        uint256 lpTokens,
        uint256 index
    ) external view returns (uint256 quoteAmount);


    function noOfLoans() external view returns (uint256);

    function maxBorrower() external view returns (address);

    function maxThresholdPrice() external view returns (uint256);
}