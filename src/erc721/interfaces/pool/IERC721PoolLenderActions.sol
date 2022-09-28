// SPDX-License-Identifier: MIT
pragma solidity 0.8.14;

/**
 * @title ERC721 Pool Lender Actions
 */
interface IERC721PoolLenderActions {

    /**
     *  @notice Deposit unencumbered collateral into a specified bucket.
     *  @param  tokenIds Array of collateral to deposit.
     *  @param  index    The bucket index to which collateral will be deposited.
     */
    function addCollateral(
        uint256[] calldata tokenIds,
        uint256 index
    ) external returns (uint256);

    /**
     *  @notice Called by lenders to claim unencumbered collateral from a price bucket.
     *  @param  tokenIds NFT token ids to be removed from the pool.
     *  @param  index    The index of the bucket from which unencumbered collateral will be claimed.
     *  @return lpAmount The amount of LP tokens used for removing collateral amount.
     */
    function removeCollateral(
        uint256[] calldata tokenIds,
        uint256 index
    ) external returns (uint256 lpAmount);
}