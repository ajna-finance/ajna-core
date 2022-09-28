// SPDX-License-Identifier: MIT

pragma solidity 0.8.14;

/**
 * @title Pool Liquidation Actions
 */
interface IPoolLiquidationActions {
    /**
     *  @notice Called by actors to use quote token to arb higher-priced deposit off the book.
     *  @param  borrower Identifies the loan to liquidate.
     *  @param  amount   Amount of bucket deposit to use to exchange for collateral.
     *  @param  index    Index of a bucket, likely the HPB, in which collateral will be deposited.
     */
    function arbTake(
        address borrower,
        uint256 amount,
        uint256 index
    ) external;

    /**
     *  @notice Called by actors to settle an amount of debt in a completed liquidation.
     *  @param  borrower Identifies the loan under liquidation.
     *  @param  maxDepth Measured from HPB, maximum number of buckets deep to settle debt.
     *  @dev maxDepth is used to prevent unbounded iteration clearing large liquidations.
     */
    function clear(
        address borrower,
        uint256 maxDepth
    ) external;

    /**
     *  @notice Called by actors to purchase collateral using quote token already on the book.
     *  @param  borrower Identifies the loan under liquidation.
     *  @param  amount   Amount of bucket deposit to use to exchange for collateral.
     *  @param  index    Index of the bucket which has amount_ quote token available.
     */
    function depositTake(
        address borrower,
        uint256 amount,
        uint256 index
    ) external;

    /**
     *  @notice Called by actors to initiate a liquidation.
     *  @param  borrower Identifies the loan to liquidate.
     */
    function kick(
        address borrower
    ) external;
}