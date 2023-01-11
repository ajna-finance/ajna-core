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
     *  @return lpbChange The amount of LPs for deposited collateral.
     */
    function addCollateral(
        uint256[] calldata tokenIds,
        uint256 index
    ) external returns (
        uint256 lpbChange
    );

    /**
     *  @notice Merge collateral accross a number of buckets, removeAmountAtIndex_to reconstitute an NFT
     *  @param  removeAmountAtIndex Array of bucket indexes to remove all collateral that the caller has ownership over.
     *  @param  toIndex           The bucket index to which merge collateral into.
     *  @param  noOfNFTsToRemove  Intergral number of NFTs to remove if collateral amount is met noOfNFTsToRemove_, else merge at bucket index, toIndex_.
     *  @return collateralMerged  Amount of collateral merged into toIndex.
     *  @return bucketLPs         If non-zero, amount of LPs in toIndex when collateral is merged into bucket. If 0, no collateral is merged.
     */
    function mergeOrRemoveCollateral(
        uint256 noOfNFTsToRemove,
        uint256[] calldata removeAmountAtIndex,
        uint256 toIndex
    ) external returns (
        uint256 collateralMerged,
        uint256 bucketLPs
    );
}