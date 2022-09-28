// SPDX-License-Identifier: MIT
pragma solidity 0.8.14;

import { EnumerableSet } from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

/**
 * @title ERC721 Pool Liquidation Actions
 */
interface IERC721PoolLiquidationActions {

    /**
     *  @notice Called by actors to purchase collateral using quote token they provide themselves.
     *  @param  borrower     Identifies the loan being liquidated.
     *  @param  tokenIds     NFT token ids caller wishes to purchase from the liquidation.
     *  @param  swapCalldata If provided, delegate call will be invoked after sending collateral to msg.sender,
     *                        such that sender will have a sufficient quote token balance prior to payment.
     */
    function take(
        address borrower,
        uint256[] calldata tokenIds,
        bytes memory swapCalldata
    ) external;
}