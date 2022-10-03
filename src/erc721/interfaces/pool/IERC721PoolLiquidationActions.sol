// SPDX-License-Identifier: MIT
pragma solidity 0.8.14;

import { EnumerableSet } from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

/**
 * @title ERC721 Pool Liquidation Actions
 */
interface IERC721PoolLiquidationActions {


    /**
     *  @notice Caller takes collateral from the auction in exchange for quote token.
     *  @param  borrower_     Address of the borower take is being called upon.
     *  @param  tokenIds_     Array of token ids that the taker requests to purchase.
     *  @param  swapCalldata_ If provided, delegate call will be invoked after sending collateral to msg.sender,
     *                        such that sender will have a sufficient quote token balance prior to payment.
     */
    function take(
        address borrower_,
        uint256[] calldata tokenIds_,
        bytes memory swapCalldata_
    ) external;
}