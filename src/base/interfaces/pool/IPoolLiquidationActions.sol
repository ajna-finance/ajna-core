// SPDX-License-Identifier: MIT

pragma solidity 0.8.14;

/**
 * @title Pool Liquidation Actions
 */
interface IPoolLiquidationActions {
    /**
     *  @notice Called by actors to use quote token to arb higher-priced deposit off the book.
     *  @param  borrower    Identifies the loan to liquidate.
     *  @param  depositTake If true then the take will happen at an auction price equal with bucket price. Auction price is used otherwise.
     *  @param  index       Index of a bucket, likely the HPB, in which collateral will be deposited.
     */
    function bucketTake(
        address borrower,
        bool    depositTake,
        uint256 index
    ) external;

    /**
     *  @notice Called by actors to settle an amount of debt in a completed liquidation.
     *  @param  borrowerAddress Address of the auctioned borrower.
     *  @param  maxDepth        Measured from HPB, maximum number of buckets deep to settle debt.
     *  @dev    maxDepth is used to prevent unbounded iteration clearing large liquidations.
     */
    function settle(
        address borrowerAddress,
        uint256 maxDepth
    ) external;

    /**
     *  @notice Called by actors to initiate a liquidation.
     *  @param  borrower Identifies the loan to liquidate.
     */
    function kick(
        address borrower
    ) external;

}