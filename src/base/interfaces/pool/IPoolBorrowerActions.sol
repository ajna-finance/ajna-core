// SPDX-License-Identifier: MIT

pragma solidity 0.8.14;

/**
 * @title Pool Borrower Actions
 */
interface IPoolBorrowerActions {
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
}
