// SPDX-License-Identifier: MIT
pragma solidity 0.8.14;

/**
 * @title ERC721 Pool Borrower Actions
 */
interface IERC721PoolBorrowerActions {

    /**
     *  @notice Emitted when borrower locks collateral in the pool.
     *  @param  tokenIds Array of tokenIds to be added to the pool.
     *  @param  borrower The address of borrower to pledge collateral for.
     */
    function pledgeCollateral(
        uint256[] calldata tokenIds,
        address borrower
    ) external;

    /**
     *  @notice Called by borrowers to remove an amount of collateral.
     *  @param  tokenIds Array of tokenIds to be removed from the pool.
     */
    function pullCollateral(
        uint256[] calldata tokenIds
    ) external;
}