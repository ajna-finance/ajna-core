// SPDX-License-Identifier: MIT
pragma solidity 0.8.14;

/**
 * @title Ajna Pool Borrower Actions
 */
interface IAjnaPoolBorrowerActions {
    /**
     *  @notice Called by a borrower to open or expand a position.
     *  @dev    Can only be called if quote tokens have already been added to the pool.
     *  @param  amount     The amount of quote token to borrow.
     *  @param  limitIndex Lower bound of LUP change (if any) that the borrower will tolerate from a creating or modifying position.
     */
    function borrow(
        uint256 amount,
        uint256 limitIndex
    ) external;

    /**
     *  @notice Called by a borrower to repay some amount of their borrowed quote tokens.
     *  @param  borrower  The address of borrower to repay quote token amount for.
     *  @param  maxAmount WAD The maximum amount of quote token to repay.
     */
    function repay(
        address borrower,
        uint256 maxAmount
    ) external;
}