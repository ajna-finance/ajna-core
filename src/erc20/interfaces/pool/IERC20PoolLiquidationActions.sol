// SPDX-License-Identifier: MIT
pragma solidity 0.8.14;

/**
 * @title ERC20 Pool Liquidation Actions
 */
interface IERC20PoolLiquidationActions {

    /**
     *  @notice Called by actors to purchase collateral from the auction in exchange for quote token.
     *  @param  borrower     Address of the borower take is being called upon.
     *  @param  maxAmount    Max amount of collateral that will be taken from the auction.
     *  @param  swapCalldata If provided, delegate call will be invoked after sending collateral to msg.sender,
     *                       such that sender will have a sufficient quote token balance prior to payment.
     */
    function take(
        address borrower,
        uint256 maxAmount,
        bytes memory swapCalldata
    ) external;

    /**
     *  @notice Called by actors to settle an amount of debt in a completed liquidation.
     *  @param  borrower Identifies the loan under liquidation.
     *  @param  maxDepth Measured from HPB, maximum number of buckets deep to settle debt.
     *  @dev maxDepth is used to prevent unbounded iteration clearing large liquidations.
     */
    function heal(
        address borrower,
        uint256 maxDepth
    ) external;
}