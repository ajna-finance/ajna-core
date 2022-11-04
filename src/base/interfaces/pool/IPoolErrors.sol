// SPDX-License-Identifier: MIT

pragma solidity 0.8.14;

/**
 * @title Pool Errors
 */
interface IPoolErrors {
    /**************************/
    /*** Common Pool Errors ***/
    /**************************/

    /**
     *  @notice Pool already initialized.
     */
    error AlreadyInitialized();

    /**
     *  @notice Borrower is attempting to create or modify a loan such that their loan's quote token would be less than the pool's minimum debt amount.
     */
    error AmountLTMinDebt();

    /**
     *  @notice Borrower has a healthy over-collateralized position.
     */
    error BorrowerOk();

    /**
     *  @notice Borrower is attempting to borrow more quote token than they have collateral for.
     */
    error BorrowerUnderCollateralized();

    /**
     *  @notice User is attempting to move or pull more collateral than is available.
     */
    error InsufficientCollateral();

    /**
     *  @notice Lender is attempting to move or remove more collateral they have claim to in the bucket.
     *  @notice Lender is attempting to remove more collateral they have claim to in the bucket.
     *  @notice Lender must have enough LP tokens to claim the desired amount of quote from the bucket.
     */
    error InsufficientLPs();

    /**
     *  @notice Bucket must have more quote available in the bucket than the lender is attempting to claim.
     */
    error InsufficientLiquidity();

    /**
     *  @notice When transferring LP tokens between indices, the new index must be a valid index.
     */
    error InvalidIndex();

    /**
     *  @notice Borrower is attempting to borrow more quote token than is available before the supplied limitIndex.
     */
    error LimitIndexReached();

    /**
     *  @notice Borrower has a healthy over-collateralized position.
     */
    error LiquidateBorrowerOk();

    /**
     *  @notice When moving quote token HTP must stay below LUP.
     *  @notice When removing quote token HTP must stay below LUP.
     */
    error LUPBelowHTP();

    /**
     *  @notice Liquidation must result in LUP below the borrowers threshold price.
     */
    error LUPGreaterThanTP();

    /**
     *  @notice FromIndex_ and toIndex_ arguments to move are the same.
     */
    error MoveToSamePrice();

    /**
     *  @notice Owner of the LP tokens must have approved the new owner prior to transfer.
     */
    error NoAllowance();

    /**
     *  @notice Actor is attempting to take or clear an inactive reserves auction.
     */
    error NoReservesAuction();

    /**
     *  @notice Lender must have non-zero LPB when attemptign to remove quote token from the pool.
     */
    error NoClaim();

    /**
     *  @notice Borrower has no debt to liquidate.
     *  @notice Borrower is attempting to repay when they have no outstanding debt.
     */
    error NoDebt();

    /**
     *  @notice No pool reserves are claimable.
     */
    error NoReserves();

    /**
     *  @notice Underlying ERC20 transfer failed.
     */
    error ERC20TransferFailed();

    /**
     *  @notice Borrower is attempting to borrow an amount of quote tokens that will push the pool into under-collateralization.
     */
    error PoolUnderCollateralized();


    /**
     *  @notice Lender is attempting to remove quote tokens from a bucket that exists above active auction debt from top-of-book downward.
     */
    error RemoveDepositLockedByAuctionDebt();
}