// SPDX-License-Identifier: MIT
pragma solidity 0.8.14;

/**
 * @title ERC20 Pool Liquidation Actions
 */
interface IERC20PoolLiquidationActions {

    /**
     *  @notice Caller takes collateral from the auction in exchange for quote token.
     *  @param  borrower_      Address of the borower take is being called upon.
     *  @param  Maxamount_     Max amount of collateral that will be taken from the auction.
     *  @param  swapCalldata_  If provided, delegate call will be invoked after sending collateral to msg.sender,
     *                         such that sender will have a sufficient quote token balance prior to payment.
     */
    function take(
        address borrower_,
        uint256 Maxamount_,
        bytes memory swapCalldata_
    ) external;
}