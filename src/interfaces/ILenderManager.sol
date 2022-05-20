// SPDX-License-Identifier: MIT
pragma solidity 0.8.11;

/**
 * @title Ajna Pool
 * @dev   Used to manage lender and borrower positions of ERC-20 tokens.
 */
interface ILenderManager {

    /**
     *  @notice Nested mapping of lender's LP token balance at different price buckets.
     *  @param  lp_          Address of the LP.
     *  @param  priceBucket_ Price of the bucket.
     *  @return balance_     LP token balance of the lender at the queried price bucket.
     */
    function lpBalance(address lp_, uint256 priceBucket_) external view returns (uint256 balance_);

    /**
     *  @notice Calculate the amount of collateral and quote tokens for a given amount of LP Tokens.
     *  @param  lpTokens_         The number of lpTokens to calculate amounts for.
     *  @param  price_            The price bucket for which the value should be calculated.
     *  @return collateralTokens_ The equivalent value of collateral tokens for the given LP Tokens, WAD units.
     *  @return quoteTokens_      The equivalent value of quote tokens for the given LP Tokens, WAD units.
     */
    function getLPTokenExchangeValue(uint256 lpTokens_, uint256 price_) external view returns (uint256 collateralTokens_, uint256 quoteTokens_);
}
