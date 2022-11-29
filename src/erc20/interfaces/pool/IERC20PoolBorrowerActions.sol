// SPDX-License-Identifier: MIT
pragma solidity 0.8.14;

/**
 * @title ERC20 Pool Borrower Actions
 */
interface IERC20PoolBorrowerActions {

    function drawDebt(
        address borrower_,
        uint256 amountToBorrow_,
        uint256 limitIndex_,
        uint256 collateralToPledge_
    ) external;

    // TODO: REMOVE
    // /**
    //  *  @notice Called by borrowers to add collateral to the pool.
    //  *  @param  borrower The address of borrower to pledge collateral for.
    //  *  @param  amount   The amount of collateral in deposit tokens to be added to the pool.
    //  */
    // function pledgeCollateral(
    //     address borrower,
    //     uint256 amount
    // ) external;
}
