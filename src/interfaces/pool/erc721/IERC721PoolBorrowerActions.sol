// SPDX-License-Identifier: MIT

pragma solidity 0.8.14;

/**
 * @title ERC721 Pool Borrower Actions
 */
interface IERC721PoolBorrowerActions {

    /**
     *  @notice Called by borrowers to add collateral to the pool and/or borrow quote from the pool.
     *  @dev    Can be called by borrowers with either 0 amountToBorrow or 0 collateralToPledge, if borrower only wants to take a single action. 
     *          Call with 0 amountToBorrow, and non-0 limitIndex to restamp loan's neutral price.
     *  @param  borrower         The address of borrower to drawDebt for.
     *  @param  amountToBorrow   The amount of quote tokens to borrow.
     *  @param  limitIndex       Lower bound of LUP change (if any) that the borrower will tolerate from a creating or modifying position.
     *  @param  tokenIdsToPledge Array of tokenIds to be pledged to the pool.
     */
    function drawDebt(
        address borrower,
        uint256 amountToBorrow,
        uint256 limitIndex,
        uint256[] calldata tokenIdsToPledge
    ) external;

    /**
     *  @notice Called by borrowers to repay borrowed quote to the pool, and/or pull collateral form the pool.
     *  @dev    Can be called by borrowers with either 0 maxQuoteTokenAmountToRepay or 0 collateralAmountToPull, if borrower only wants to take a single action. 
     *  @param  borrowerAddress            The borrower whose loan is being interacted with.
     *  @param  maxQuoteTokenAmountToRepay The amount of quote tokens to repay.
     *  @param  noOfNFTsToPull             The integer number of NFT collateral to be puled from the pool.
     */
    function repayDebt(
        address borrowerAddress,
        uint256 maxQuoteTokenAmountToRepay,
        uint256 noOfNFTsToPull
    ) external;
}
