// SPDX-License-Identifier: MIT

pragma solidity 0.8.14;

/**
 * @title Pool Borrower Actions
 */
interface IPoolBorrowerActions {

    /**
     *  @notice Called by borrowers to remove an amount of collateral.
     *  @param  amount The amount of collateral in deposit tokens (or number of NFTs) to be removed from a position.
     */
    function pullCollateral(
        uint256 amount
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