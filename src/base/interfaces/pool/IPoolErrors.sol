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
     *  @notice The action cannot be executed on an active auction.
     */
    error AuctionActive();

    /**
     *  @notice Attempted auction to clear doesn't meet conditions.
     */
    error AuctionNotClearable();

    /**
     *  @notice Head auction should be cleared prior of executing this action.
     */
    error AuctionNotCleared();

    /**
     *  @notice The auction price is greater than the arbed bucket price.
     */
    error AuctionPriceGtBucketPrice();

    /**
     *  @notice Pool already initialized.
     */
    error AlreadyInitialized();

    /**
     *  @notice Borrower is attempting to create or modify a loan such that their loan's quote token would be less than the pool's minimum debt amount.
     */
    error AmountLTMinDebt();

    /**
     *  @notice Recipient of borrowed quote tokens doesn't match the caller of the drawDebt function.
     */
    error BorrowerNotSender();

    /**
     *  @notice Borrower has a healthy over-collateralized position.
     */
    error BorrowerOk();

    /**
     *  @notice Borrower is attempting to borrow more quote token than they have collateral for.
     */
    error BorrowerUnderCollateralized();

    /**
     *  @notice Operation cannot be executed in the same block when bucket becomes insolvent.
     */
    error BucketBankruptcyBlock();

    /**
     *  @notice User attempted to merge collateral from a lower price bucket into a higher price bucket.
     */
    error CannotMergeToHigherPrice();

    /**
     *  @notice User attempted an operation which does not exceed the dust amount, or leaves behind less than the dust amount.
     */
    error DustAmountNotExceeded();

    /**
     *  @notice Callback invoked by flashLoan function did not return the expected hash (see ERC-3156 spec).
     */
    error FlashloanCallbackFailed();

    /**
     *  @notice Pool cannot facilitate a flashloan for the specified token address.
     */
    error FlashloanUnavailableForToken();

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
     *  @notice Actor is attempting to take or clear an inactive auction.
     */
    error NoAuction();

    /**
     *  @notice No pool reserves are claimable.
     */
    error NoReserves();

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
     *  @notice Borrower is attempting to borrow an amount of quote tokens that will push the pool into under-collateralization.
     */
    error PoolUnderCollateralized();

    /**
     *  @notice Actor is attempting to remove using a bucket with price below the LUP.
     */
    error PriceBelowLUP();

    /**
     *  @notice Lender is attempting to remove quote tokens from a bucket that exists above active auction debt from top-of-book downward.
     */
    error RemoveDepositLockedByAuctionDebt();

    /**
     * @notice User attempted to kick off a new auction less than 2 weeks since the last auction completed.
     */
    error ReserveAuctionTooSoon();

    /**
     *  @notice Take was called before 1 hour had passed from kick time.
     */
    error TakeNotPastCooldown();

    /**
     *  @notice The threshold price of the loan to be inserted in loans heap is zero.
     */
    error ZeroThresholdPrice();

}
