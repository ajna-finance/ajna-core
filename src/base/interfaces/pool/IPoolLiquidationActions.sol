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

    /**
     *  @notice Called by actors to purchase collateral from the auction in exchange for quote token.
     *  @param  borrower     Address of the borower take is being called upon.
     *  @param  maxAmount    Max amount of collateral that will be taken from the auction (max number of NFTs in case of ERC721 pool).
     *  @param  swapCalldata If provided, delegate call will be invoked after sending collateral to msg.sender,
     *                       such that sender will have a sufficient quote token balance prior to payment.
     */
    function take(
        address borrower,
        uint256 maxAmount,
        bytes memory swapCalldata
    ) external;

    /**
     *  @notice Called by kickers to withdraw their auction bonds (the amount of quote tokens that are not locked in active auctions).
     */
    function withdrawBonds() external;

}