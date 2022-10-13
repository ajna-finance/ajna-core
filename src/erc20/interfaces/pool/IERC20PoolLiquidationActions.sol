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
}