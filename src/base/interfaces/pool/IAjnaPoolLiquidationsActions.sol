// SPDX-License-Identifier: MIT
pragma solidity 0.8.14;

/**
 * @title Ajna Pool Liquidation Actions
 */
interface IAjnaPoolLiquidationsActions {
    /**
     *  @notice Called by actors to use quote token to arb higher-priced deposit off the book.
     *  @param  index    Index of a bucket, likely the HPB, in which collateral will be deposited.
     *  @param  amount   Amount of bucket deposit to use to exchange for collateral.
     *  @param  borrower Identifies the loan to liquidate.
     */
    function arbTake(
        uint256 index,
        uint256 amount,
        address borrower
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
     *  @param  index    Index of the bucket which has amount_ quote token available.
     *  @param  amount   Amount of bucket deposit to use to exchange for collateral.
     *  @param  borrower Identifies the loan under liquidation.
     */
    function depositTake(
        uint256 index,
        uint256 amount,
        address borrower
    ) external;

    /**
     *  @notice Called by actors to initiate a liquidation.
     *  @param  borrower Identifies the loan to liquidate.
     */
    function kick(
        address borrower
    ) external;
}