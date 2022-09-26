// SPDX-License-Identifier: MIT
pragma solidity 0.8.14;

/**
 * @title ERC721 Pool Lender Actions
 */
interface IERC721PoolLenderActions {

    /**
     *  @notice Deposit unencumbered collateral into a specified bucket.
     *  @param  index    The bucket index to which collateral will be deposited.
     *  @param  tokenIds Array of collateral to deposit.
     */
    function addCollateral(
        uint256 index,
        uint256[] calldata tokenIds
    ) external returns (uint256);

    /**
     *  @notice Called by lenders to claim unencumbered collateral from a price bucket.
     *  @param  index    The index of the bucket from which unencumbered collateral will be claimed.
     *  @param  tokenIds NFT token ids to be removed from the pool.
     *  @return lpAmount The amount of LP tokens used for removing collateral amount.
     */
    function removeCollateral(
        uint256 index,
        uint256[] calldata tokenIds
    ) external returns (uint256 lpAmount);
}