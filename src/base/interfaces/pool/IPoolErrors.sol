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
    error BorrowAmountLTMinDebt();

    /**
     *  @notice Borrower is attempting to borrow more quote token than they have collateral for.
     */
    error BorrowBorrowerUnderCollateralized();

    /**
     *  @notice Borrower is attempting to borrow more quote token than is available before the supplied limitIndex.
     */
    error BorrowLimitIndexReached();

    /**
     *  @notice Borrower is attempting to borrow an amount of quote tokens that will push the pool into under-collateralization.
     */
    error BorrowPoolUnderCollateralized();

    /**
     *  @notice Liquidation must result in LUP below the borrowers threshold price.
     */
    error KickLUPGreaterThanTP();

    /**
     *  @notice Borrower has no debt to liquidate.
     */
    error KickNoDebt();

    /**
     *  @notice No pool reserves are claimable.
     */
    error KickNoReserves();

    /**
     *  @notice Borrower has a healthy over-collateralized position.
     */
    error LiquidateBorrowerOk();

    /**
     *  @notice User is attempting to move more collateral than is available.
     */
    error MoveCollateralInsufficientCollateral();

    /**
     *  @notice Lender is attempting to move more collateral they have claim to in the bucket.
     */
    error MoveCollateralInsufficientLP();

    /**
     *  @notice FromIndex_ and toIndex_ arguments to moveQuoteToken() are the same.
     */
    error MoveCollateralToSamePrice();

    /**
     *  @notice FromIndex_ and toIndex_ arguments to moveQuoteToken() are the same.
     */
    error MoveQuoteToSamePrice();

    /**
     *  @notice When moving quote token HTP must stay below LUP.
     */
    error MoveQuoteLUPBelowHTP();

    /**
     *  @notice Actor is attempting to take or clear an inactive auction.
     */
    error NoAuction();

    /**
     *  @notice User is attempting to pull more collateral than is available.
     */
    error PullCollateralInsufficientCollateral();

    /**
     *  @notice Lender is attempting to remove more collateral they have claim to in the bucket.
     */
    error RemoveCollateralInsufficientLP();

    /**
     *  @notice Lender must have enough LP tokens to claim the desired amount of quote from the bucket.
     */
    error RemoveQuoteInsufficientLPB();

    /**
     *  @notice Bucket must have more quote available in the bucket than the lender is attempting to claim.
     */
    error RemoveQuoteInsufficientQuoteAvailable();

    /**
     *  @notice When removing quote token HTP must stay below LUP.
     */
    error RemoveQuoteLUPBelowHTP();

    /**
     *  @notice Lender must have non-zero LPB when attemptign to remove quote token from the pool.
     */
    error RemoveQuoteNoClaim();

    /**
     *  @notice Borrower is attempting to repay when they have no outstanding debt.
     */
    error RepayNoDebt();

    /**
     *  @notice Take was called before 1 hour had passed from kick time.
     */
    error TakeNotPastCooldown();

    /**
     *  @notice When transferring LP tokens between indices, the new index must be a valid index.
     */
    error TransferLPInvalidIndex();

    /**
     *  @notice Owner of the LP tokens must have approved the new owner prior to transfer.
     */
    error TransferLPNoAllowance();
}