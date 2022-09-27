// SPDX-License-Identifier: MIT
pragma solidity 0.8.14;

/**
 * @title ERC20 Pool Borrower Actions
 */
interface IERC20PoolBorrowerActions {

    /**
     *  @notice Called by borrowers to add collateral to the pool.
     *  @param  borrower The address of borrower to pledge collateral for.
     *  @param  amount   The amount of collateral in deposit tokens to be added to the pool.
     */
    function pledgeCollateral(
        address borrower,
        uint256 amount
    ) external;

    /**
     *  @notice Called by borrowers to remove an amount of collateral.
     *  @param  amount The amount of collateral in deposit tokens to be removed from a position.
     */
    function pullCollateral(
        uint256 amount
    ) external;
}