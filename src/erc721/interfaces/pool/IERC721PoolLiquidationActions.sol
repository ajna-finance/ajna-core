// SPDX-License-Identifier: MIT
pragma solidity 0.8.14;

import { EnumerableSet } from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

/**
 * @title ERC721 Pool Liquidation Actions
 */
interface IERC721PoolLiquidationActions {

    /**
     *  @notice Maintains the state of a liquidation.
     *  @param  kickTime            Time the liquidation was initiated.
     *  @param  referencePrice      Highest Price Bucket at time of liquidation.
     *  @param  remainingTokenIds   Liquidated NFTs which not yet been taken.
     *  @param  remainingDebt       Amount of debt which has not been covered by the liquidation.
     */
    struct NFTLiquidationInfo {
        uint128               kickTime;
        uint128               referencePrice;
        EnumerableSet.UintSet remainingTokenIds;
        uint256               remainingDebt;
    }

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