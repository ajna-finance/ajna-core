// SPDX-License-Identifier: MIT

pragma solidity 0.8.14;

/**
 * @title ERC20 Pool Borrower Actions
 */
interface IERC20PoolBorrowerActions {

    /**
     *  @notice Called by borrowers to add collateral to the pool and/or borrow quote from the pool.
     *  @dev    Can be called by borrowers with either 0 amountToBorrow_ or 0 collateralToPledge_, if borrower only wants to take a single action. 
     *          Call with 0 amountToBorrow_, and non-0 limitIndex_ to restamp loan's neutral price.
     *  @param  borrowerAddress    The borrower to whom collateral was pledged, and/or debt was drawn for.
     *  @param  amountToBorrow     The amount of quote tokens to borrow.
     *  @param  limitIndex         Lower bound of LUP change (if any) that the borrower will tolerate from a creating or modifying position.
     *  @param  collateralToPledge The amount of collateral to be added to the pool.
     */
    function drawDebt(
        address borrowerAddress,
        uint256 amountToBorrow,
        uint256 limitIndex,
        uint256 collateralToPledge
    ) external;

    /**
     *  @notice Called by borrowers to repay borrowed quote to the pool, and/or pull collateral form the pool.
     *  @dev    Can be called by borrowers with either 0 maxQuoteTokenAmountToRepay or 0 collateralAmountToPull, if borrower only wants to take a single action. 
     *  @param  borrowerAddress            The borrower whose loan is being interacted with.
     *  @param  maxQuoteTokenAmountToRepay The amount of quote tokens to repay.
     *  @param  collateralAmountToPull     The amount of collateral to be puled from the pool.
     */
    function repayDebt(
        address borrowerAddress,
        uint256 maxQuoteTokenAmountToRepay,
        uint256 collateralAmountToPull
    ) external;
}
