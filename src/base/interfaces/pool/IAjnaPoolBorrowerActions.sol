// SPDX-License-Identifier: MIT
pragma solidity 0.8.14;

/**
 * @title Ajna Pool Borrower Actions
 */
interface IAjnaPoolBorrowerActions {
    /**
     *  @notice Called by a borrower to open or expand a position.
     *  @dev    Can only be called if quote tokens have already been added to the pool.
     *  @param  limitIndex Lower bound of LUP change (if any) that the borrower will tolerate from a creating or modifying position.
     *  @param  amount     The amount of quote token to borrow.
     */
    function borrow(
        uint256 limitIndex,
        uint256 amount
    ) external;

    /**
     *  @notice Called by a borrower to repay some amount of their borrowed quote tokens.
     *  @param  maxAmount WAD The maximum amount of quote token to repay.
     *  @param  borrower  The address of borrower to repay quote token amount for.
     */
    function repay(
        uint256 maxAmount,
        address borrower
    ) external;
}