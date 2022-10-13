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
     *  @notice Emitted when an actor settles debt in a completed liquidation
     *  @param  borrower           Identifies the loan being liquidated.
     *  @param  hpbIndex           The index of the Highest Price Bucket where debt was cleared.
     *  @param  amount             Amount of debt cleared from the HPB in this transaction.
     *  @param  tokenIdsReturned   Array of NFTs returned to the borrower in this transaction.
     *  @param  amountRemaining    Amount of debt which still needs to be cleared.
     *  @dev    When amountRemaining_ == 0, the auction has been completed cleared and removed from the queue.
     */
    event ClearNFT(
        address   indexed borrower,
        uint256   hpbIndex,
        uint256   amount,
        uint256[] tokenIdsReturned,
        uint256   amountRemaining);

    /**
     *  @notice Emitted when borrower locks collateral in the pool.
     *  @param  borrower `msg.sender`.
     *  @param  tokenIds Array of tokenIds to be added to the pool.
     */
    event PledgeCollateralNFT(
        address indexed borrower,
        uint256[] tokenIds
    );

    /**
     *  @notice Emitted when borrower removes collateral from the pool.
     *  @param  borrower `msg.sender`.
     *  @param  tokenIds Array of tokenIds to be removed from the pool.
     */
    event PullCollateralNFT(
        address indexed borrower,
        uint256[] tokenIds
    );

    /**
     *  @notice Emitted when lender claims unencumbered collateral.
     *  @param  claimer  Recipient that claimed collateral.
     *  @param  price    Price at which unencumbered collateral was claimed.
     *  @param  tokenIds Array of tokenIds to be removed from the pool.
     */
    event RemoveCollateralNFT(
        address indexed claimer,
        uint256 indexed price,
        uint256[] tokenIds
    );
}