// SPDX-License-Identifier: MIT

pragma solidity 0.8.14;

/**
 * @title ERC721 Pool Lender Actions
 */
interface IERC721PoolLenderActions {

    /**
     *  @notice Deposit claimable collateral into a specified bucket.
     *  @param  tokenIds Array of collateral to deposit.
     *  @param  index    The bucket index to which collateral will be deposited.
     */
    function addCollateral(
        uint256[] calldata tokenIds,
        uint256 index
    ) external returns (uint256);

    /**
     *  @notice Merge collateral accross a number of buckets, removeAmountAtIndex_to reconstitute an NFT
     *  @param  removeAmountAtIndex_ Array of bucket indexes to remove all collateral that the caller has ownership over.
     *  @param  toIndex_             The bucket index to which merge collateral into.
     *  @param  noOfNFTsToRemove_    Intergral number of NFTs to remove if collateral amount is met noOfNFTsToRemove_, else merge at bucket index, toIndex_.
     *  @return collateralMerged_     Amount of collateral merged into toIndex.
     *  @return bucketLPs_           If non-zero, amount of LPs in toIndex when collateral is merged into bucket. If 0, no collateral is merged.
     */
    function mergeOrRemoveCollateral(
        uint256[] calldata removeAmountAtIndex_,
        uint256 noOfNFTsToRemove_,
        uint256 toIndex_
    ) external returns (uint256 collateralMerged_, uint256 bucketLPs_);
}