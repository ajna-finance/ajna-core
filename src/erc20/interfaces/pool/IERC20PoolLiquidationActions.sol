// SPDX-License-Identifier: MIT
pragma solidity 0.8.14;

/**
 * @title ERC20 Pool Liquidation Actions
 */
interface IERC20PoolLiquidationActions {

    /**
     *  @notice Called by actors to purchase collateral using quote token they provide themselves.
     *  @param  borrower     Identifies the loan under liquidation.
     *  @param  amount       Amount of quote token which will be used to purchase collateral at the auction price.
     *  @param  swapCalldata If provided, delegate call will be invoked after sending collateral to msg.sender,
     *                        such that sender will have a sufficient quote token balance prior to payment.
     */
    function take(
        address borrower,
        uint256 amount,
        bytes memory swapCalldata
    ) external;
}