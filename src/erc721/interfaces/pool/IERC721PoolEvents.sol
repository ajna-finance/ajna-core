// SPDX-License-Identifier: MIT
pragma solidity 0.8.14;

/**
 * @title ERC721 Pool Events
 */
interface IERC721PoolEvents {

    /**
     *  @notice Emitted when actor adds unencumbered collateral to a bucket.
     *  @param  actor    Recipient that added collateral.
     *  @param  price    Price at which collateral were added.
     *  @param  tokenIds Array of tokenIds to be added to the pool.
     */
    event AddCollateralNFT(
        address indexed actor,
        uint256 indexed price,
        uint256[] tokenIds
    );

    /**
     *  @notice Emitted when borrower locks collateral in the pool.
     *  @param  borrower `msg.sender`.
     *  @param  tokenIds Array of tokenIds to be added to the pool.
     */
    event PledgeCollateralNFT(
        address indexed borrower,
        uint256[] tokenIds
    );

}