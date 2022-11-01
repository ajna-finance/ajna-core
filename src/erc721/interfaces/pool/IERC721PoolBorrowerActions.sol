// SPDX-License-Identifier: MIT
pragma solidity 0.8.14;

/**
 * @title ERC721 Pool Borrower Actions
 */
interface IERC721PoolBorrowerActions {

    /**
     *  @notice Emitted when borrower locks collateral in the pool.
     *  @param  borrower The address of borrower to pledge collateral for.
     *  @param  tokenIds Array of tokenIds to be added to the pool.
     */
    function pledgeCollateral(
        address borrower,
        uint256[] calldata tokenIds
    ) external;
}