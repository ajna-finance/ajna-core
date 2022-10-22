// SPDX-License-Identifier: MIT
pragma solidity 0.8.14;

import { EnumerableSet } from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

/**
 * @title ERC721 Pool Liquidation Actions
 */
interface IERC721PoolLiquidationActions {

    /**
     *  @notice Called by actors to purchase collateral from the auction in exchange for quote token.
     *  @param  borrower     Address of the borower take is being called upon.
     *  @param  tokenIds     Array of token ids that the taker requests to purchase.
     *  @param  swapCalldata If provided, delegate call will be invoked after sending collateral to msg.sender,
     *                       such that sender will have a sufficient quote token balance prior to payment.
     */
    function take(
        address borrower,
        uint256[] calldata tokenIds,
        bytes memory swapCalldata
    ) external;


    /**
     *  @notice Called by actors to settle an amount of debt in a completed liquidation.
     *  @param  borrower Identifies the loan under liquidation.
     *  @param  tokenIds Measured from HPB, maximum number of buckets deep to settle debt.
     *  @param  maxDepth Measured from HPB, maximum number of buckets deep to settle debt.
     */
    function heal(
        address borrower,
        uint256[] calldata tokenIds,
        uint256 maxDepth
    ) external;
}