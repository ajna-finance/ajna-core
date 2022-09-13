// SPDX-License-Identifier: MIT
pragma solidity 0.8.14;

/**
 * @title Ajna Pool
 * @dev   Used to manage lender and borrower positions.
 */
interface IScaledPool {

    /*********************/
    /*** Common Events ***/
    /*********************/

    /**
     *  @notice Emitted when lender adds quote token to the pool.
     *  @param  lender_ Recipient that added quote tokens.
     *  @param  price_  Price at which quote tokens were added.
     *  @param  amount_ Amount of quote tokens added to the pool.
     *  @param  lup_    LUP calculated after deposit.
     */
    event AddQuoteToken(address indexed lender_, uint256 indexed price_, uint256 amount_, uint256 lup_);

    /**
     *  @notice Emitted when an actor uses quote token to arb higher-priced deposit off the book.
     *  @param  borrower_   Identifies the loan being liquidated.
     *  @param  index_      The index of the Highest Price Bucket used for this take.
     *  @param  amount_     Amount of quote token used to purchase collateral.
     *  @param  collateral_ Amount of collateral purchased with quote token.
     *  @param  bondChange_ Impact of this take to the liquidation bond.
     *  @dev    amount_ / collateral_ implies the auction price.
     */
    event ArbTake(address indexed borrower_, uint256 index_, uint256 amount_, uint256 collateral_, int256 bondChange_);

    /**
     *  @notice Emitted when an actor uses quote token outside of the book to purchase collateral under liquidation.
     *  @param  borrower_   Identifies the loan being liquidated.
     *  @param  index_      Index of the price bucket from which quote token was exchanged for collateral.
     *  @param  amount_     Amount of quote token taken from the bucket to purchase collateral.
     *  @param  collateral_ Amount of collateral purchased with quote token.
     *  @param  bondChange_ Impact of this take to the liquidation bond.
     *  @dev    amount_ / collateral_ implies the auction price.
     */
    event DepositTake(address indexed borrower_, uint256 index_, uint256 amount_, uint256 collateral_, int256 bondChange_);

    /**
     *  @notice Emitted when a liquidation is initiated.
     *  @param  borrower_   Identifies the loan being liquidated.
     *  @param  debt_       Debt the liquidation will attempt to cover.
     *  @param  collateral_ Amount of collateral up for liquidation.
     */
    event Kick(address indexed borrower_, uint256 debt_, uint256 collateral_);

    /**
     *  @notice Emitted when lender moves quote token from a bucket price to another.
     *  @param  lender_ Recipient that moved quote tokens.
     *  @param  from_   Price bucket from which quote tokens were moved.
     *  @param  to_     Price bucket where quote tokens were moved.
     *  @param  amount_ Amount of quote tokens moved.
     *  @param  lup_    LUP calculated after removal.
     */
    event MoveQuoteToken(address indexed lender_, uint256 indexed from_, uint256 indexed to_, uint256 amount_, uint256 lup_);

    /**
     *  @notice Emitted when lender removes quote token from the pool.
     *  @param  lender_ Recipient that removed quote tokens.
     *  @param  price_  Price at which quote tokens were removed.
     *  @param  amount_ Amount of quote tokens removed from the pool.
     *  @param  lup_    LUP calculated after removal.
     */
    event RemoveQuoteToken(address indexed lender_, uint256 indexed price_, uint256 amount_, uint256 lup_);

    /**
     *  @notice Emitted when a Claimaible Reserve Auction is started or taken.
     *  @return claimableReservesRemaining_ Amount of claimable reserves which has not yet been taken.
     *  @return auctionPrice_               Current price at which 1 quote token may be purchased, denominated in Ajna.
     */
    event ReserveAuction(uint256 claimableReservesRemaining_, uint256 auctionPrice_);

    /**
     *  @notice Emitted when a lender transfers their LP tokens to a different address.
     *  @dev    Used by PositionManager.memorializePositions().
     *  @param  owner_    The original owner address of the position.
     *  @param  newOwner_ The new owner address of the position.
     *  @param  indexes_  Array of price bucket indexes at which LP tokens were transferred.
     *  @param  lpTokens_ Amount of LP tokens transferred.
     */
    event TransferLPTokens(address owner_, address newOwner_, uint256[] indexes_, uint256 lpTokens_);

    /**
     *  @notice Emitted when pool interest rate is updated.
     *  @param  oldRate_ Old pool interest rate.
     *  @param  newRate_ New pool interest rate.
     */
    event UpdateInterestRate(uint256 oldRate_, uint256 newRate_);

    /*********************/
    /*** Shared Errors ***/
    /*********************/

    // TODO: add a test for this
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
    error RemoveCollateralInsufficientCollateral();

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
     *  @notice When transferring LP tokens between indices, the new index must be a valid index.
     */
    error TransferLPInvalidIndex();

    /**
     *  @notice Owner of the LP tokens must have approved the new owner prior to transfer.
     */
    error TransferLPNoAllowance();


    /***********************/
    /*** State Variables ***/
    /***********************/

    /**
     *  @notice Returns the `borrowerDebt` state variable.
     *  @return borrowerDebt_ Total amount of borrower debt in pool.
     */
    function borrowerDebt() external view returns (uint256 borrowerDebt_);

    /**
     *  @notice Mapping of buckets indexes to {Bucket} structs.
     *  @dev    NOTE: Cannot use appended underscore syntax for return params since struct is used.
     *  @param  index_        Bucket index.
     *  @return lpAccumulator       Amount of LPs accumulated in current bucket.
     *  @return availableCollateral Amount of collateral available in current bucket.
     */
    function buckets(uint256 index_) external view returns (uint256 lpAccumulator, uint256 availableCollateral);

    /**
     *  @notice Mapping of buckets indexes and owner addresses to {BucketLender} structs.
     *  @dev    NOTE: Cannot use appended underscore syntax for return params since struct is used.
     *  @param  index_           Bucket index.
     *  @param  lp_              Address of the liquidity provider.
     *  @return lpBalance        Amount of LPs owner has in current bucket.
     *  @return lastQuoteDeposit Time the user last deposited quote token.
     */
    function bucketLenders(uint256 index_, address lp_) external view returns (uint256 lpBalance, uint256 lastQuoteDeposit);

    /**
     *  @notice Returns the `debtEma` state variable.
     *  @return debtEma_ Exponential debt moving average.
     */
    function debtEma() external view returns (uint256 debtEma_);

    /**
     *  @notice Returns the `inflatorSnapshot` state variable.
     *  @return inflatorSnapshot_ A snapshot of the last inflator value, in RAY units.
     */
    function inflatorSnapshot() external view returns (uint256 inflatorSnapshot_);

    /**
     *  @notice Returns the `interestRate` state variable.
     *  @return interestRate_ TODO
     */
    function interestRate() external view returns (uint256 interestRate_);

    /**
     *  @notice Returns the `interestRateUpdate` state variable.
     *  @return interestRateUpdate_ The timestamp of the last rate update.
     */
    function interestRateUpdate() external view returns (uint256 interestRateUpdate_);

    /**
     *  @notice Returns the `lastInflatorSnapshotUpdate` state variable.
     *  @return lastInflatorSnapshotUpdate_ The timestamp of the last `inflatorSnapshot` update.
     */
    function lastInflatorSnapshotUpdate() external view returns (uint256 lastInflatorSnapshotUpdate_);

    /**
     *  @notice Returns the `lenderInterestFactor` state variable.
     *  @return lenderInterestFactor_ TODO
     */
    function lenderInterestFactor() external view returns (uint256 lenderInterestFactor_);

    /**
     *  @notice Returns the amount of liquidation bond across all liquidators.
     *  @return liquidationBondEscrowed_ Total amount of quote token being escrowed.
     */
    function liquidationBondEscrowed() external view returns (uint256 liquidationBondEscrowed_);

    /**
     *  @notice Returns the amount of quote token in the book down to the specified bucket index.
     *  @return quoteToken_ Amount of quote token (deposit + interest), regardless of pool debt.
     */
    function liquidityToPrice(uint256 index_) external view returns (uint256 quoteToken_);

    /**
     *  @notice Returns the `lupColEma` state variable.
     *  @return lupColEma_ Exponential LUP * pledged collateral moving average.
     */
    function lupColEma() external view returns (uint256 lupColEma_);

    /**
     *  @notice Returns the `lupEma` state variable.
     *  @return lupEma_ Exponential moving average of the lowest utilized price.
     */
    function lupEma() external view returns (uint256 lupEma_);

    /**
     *  @notice Returns the `minFee` state variable.
     *  @return minFee_ TODO
     */
    function minFee() external view returns (uint256 minFee_);

    /**
     *  @notice Returns the `pledgedCollateral` state variable.
     *  @return pledgedCollateral_ The total pledged collateral in the system, in WAD units.
     */
    function pledgedCollateral() external view returns (uint256 pledgedCollateral_);

    /**
     *  @notice Returns the `poolPriceEma` state variable.
     *  @return poolPriceEma_ Exponential moving average of the pool price (debt / encumbered collateral).
     */
    function poolPriceEma() external view returns (uint256 poolPriceEma_);

    /**
     *  @notice Returns the `quoteTokenScale` state variable.
     *  @return quoteTokenScale_ The precision of the quote ERC-20 token based on decimals.
     */
    function quoteTokenScale() external view returns (uint256 quoteTokenScale_);

    /**
     *  @notice Returns the amount of excess quote tokens.
     */
    function reserves() external view returns (uint256 reserves_);

    /***************/
    /*** Structs ***/
    /***************/

    /**
     *  @notice struct holding bucket info
     *  @param lpAccumulator       Bucket LP accumulator, RAY
     *  @param availableCollateral Available collateral tokens deposited in the bucket, WAD
     */
    struct Bucket {
        uint256 lpAccumulator;       // [RAY]
        uint256 availableCollateral; // [WAD]
    }

    struct BucketLender {
        uint256 lpBalance;           // [RAY]
        uint256 lastQuoteDeposit;    // timestamp
    }


    /*********************************/
    /*** Lender External Functions ***/
    /*********************************/

    /**
     *  @notice Called by lenders to add an amount of credit at a specified price bucket.
     *  @param  amount_    The amount of quote token to be added by a lender.
     *  @param  index_     The index of the bucket to which the quote tokens will be added.
     *  @return lpbChange_ The amount of LP Tokens changed for the added quote tokens.
     */
    function addQuoteToken(uint256 amount_, uint256 index_) external returns (uint256 lpbChange_);

    /**
     *  @notice Called by lenders to approve transfer of LP tokens to a new owner.
     *  @dev    Intended for use by the PositionManager contract.
     *  @param  allowedNewOwner_ The new owner of the LP tokens.
     *  @param  index_           The index of the bucket from where LPs tokens are transferred.
     *  @param  amount_          The amount of LP tokens approved to transfer.
     */
    function approveLpOwnership(address allowedNewOwner_, uint256 index_, uint256 amount_) external;

    /**
     *  @notice Called by lenders to move an amount of credit from a specified price bucket to another specified price bucket.
     *  @param  maxAmount_     The maximum amount of quote token to be moved by a lender.
     *  @param  fromIndex_     The bucket index from which the quote tokens will be removed.
     *  @param  toIndex_       The bucket index to which the quote tokens will be added.
     *  @return lpbAmountFrom_ The amount of LPs moved out from bucket.
     *  @return lpbAmountTo_   The amount of LPs moved to destination bucket.
     */
    function moveQuoteToken(uint256 maxAmount_, uint256 fromIndex_, uint256 toIndex_) external returns (uint256 lpbAmountFrom_, uint256 lpbAmountTo_);

    /**
     *  @notice Called by lenders to redeem the maximum amount of LP for quote token.
     *  @param  index_       The bucket index from which quote tokens will be removed.
     *  @return amount_      The amount of quote token removed.
     *  @return lpAmount_    The amount of LP used for removing quote tokens.
     */
    function removeAllQuoteToken(uint256 index_) external returns (uint256 amount_, uint256 lpAmount_);

    /**
     *  @notice Called by lenders to remove an amount of credit at a specified price bucket.
     *  @param  amount_      The amount of quote token to be removed by a lender.
     *  @param  index_       The bucket index from which quote tokens will be removed.
     *  @return lpAmount_    The amount of LP used for removing quote tokens amount.
     */
    function removeQuoteToken(uint256 amount_, uint256 index_) external returns (uint256 lpAmount_);

    /**
     *  @notice Called by lenders to transfers their LP tokens to a different address.
     *  @dev    Used by PositionManager.memorializePositions().
     *  @param  owner_    The original owner address of the position.
     *  @param  newOwner_ The new owner address of the position.
     *  @param  indexes_  Array of price buckets index at which LP tokens were moved.
     */
    function transferLPTokens(address owner_, address newOwner_, uint256[] calldata indexes_) external;


    /*******************************/
    /*** Pool External Functions ***/
    /*******************************/

    /**
     *  @notice Called by actors to use quote token to arb higher-priced deposit off the book.
     *  @param  borrower_ Identifies the loan to liquidate.
     *  @param  amount_   Amount of bucket deposit to use to exchange for collateral.
     *  @param  index_    Index of a bucket, likely the HPB, in which collateral will be deposited.
     */
    function arbTake(address borrower_, uint256 amount_, uint256 index_) external;

    /**
     *  @notice Called by actors to settle an amount of debt in a completed liquidation.
     *  @param  borrower_ Identifies the loan under liquidation.
     *  @param  maxDepth_ Measured from HPB, maximum number of buckets deep to settle debt.
     *  @dev maxDepth_ is used to prevent unbounded iteration clearing large liquidations.
     */
    function clear(address borrower_, uint256 maxDepth_) external;

    /**
     *  @notice Called by actors to purchase collateral using quote token already on the book.
     *  @param  borrower_     Identifies the loan under liquidation.
     *  @param  amount_       Amount of bucket deposit to use to exchange for collateral.
     *  @param  index_        Index of the bucket which has amount_ quote token available.
     */
    function depositTake(address borrower_, uint256 amount_, uint256 index_) external;

    /**
     *  @notice Called by actors to initiate a liquidation.
     *  @param  borrower_ Identifies the loan to liquidate.
     */
    function kick(address borrower_) external;

    /**
     *  @notice Called by actor to start a Claimable Reserve Auction (CRA).
     */
    function startClaimableReserveAuction() external;

    /**
     *  @notice Purchases claimable reserves during a CRA using Ajna token.
     *  @param  maxAmount_   Maximum amount of quote token to purchase at the current auction price.
     *  @return amount_      Actual amount of reserves taken.
     */
    function takeReserves(uint256 maxAmount_) external returns (uint256 amount_);


    /**********************/
    /*** View Functions ***/
    /**********************/

    /**
     *  @notice Calculate the current collateralization ratio of the borrower at a specified price, based on borrower debt and collateralization.
     *  @param  debt_                      Borrower debt.
     *  @param  collateral_                Borrower collateral.
     *  @param  price_                     The price to calculate collateralization for.
     *  @return borrowerCollateralization_ Current borrower collateralization ratio.
     */
    function borrowerCollateralization(uint256 debt_, uint256 collateral_, uint256 price_) external view returns (uint256 borrowerCollateralization_);

    /**
     *  @notice Get a bucket struct for a given index.
     *  @param  index_          The index of the bucket to retrieve.
     *  @return quoteTokens_    Amount of quote token in bucket, deposit + interest (WAD)
     *  @return collateral_     Unencumbered collateral in bucket (WAD).
     *  @return lpAccumulator_  Outstanding LP balance in bucket (WAD)
     *  @return scale_          Lender interest multiplier (WAD).
     */
    function bucketAt(uint256 index_)
        external
        view
        returns (
            uint256 quoteTokens_,
            uint256 collateral_,
            uint256 lpAccumulator_,
            uint256 scale_
        );

    /**
     *  @notice Calculates the amount of reserves which can be claimed through a Claimable Reserve Auction.
     *  @return _claimableReserves Denominated in quote token, or 0 if no reserves can be auctioned.
     */
    function claimableReserves() external view returns (uint256 _claimableReserves);

    /**
     *  @notice Returns the address of the pool's collateral token
     */
    function collateralTokenAddress() external pure returns (address);

    /**
     *  @notice Get a bucket deposit for a given index.
     *  @param  index_   The index of the bucket to retrieve deposit for.
     *  @return deposit_ Quote tokens deposit at specified index (WAD).
     */
    function depositAt(uint256 index_) external view returns (uint256 deposit_);

    /**
     *  @notice Returns the total encumbered collateral resulting from a given amount of debt at a specified price.
     *  @param  debt_        Amount of debt for corresponding collateral encumbrance.
     *  @param  price_       Price to use for calculating the collateral encumbrance, in WAD units.
     *  @return encumbrance_ The current encumbrance of a given debt balance, in WAD units.
     */
    function encumberedCollateral(uint256 debt_, uint256 price_) external view returns (uint256 encumbrance_);

    /**
     *  @notice Returns exchange rate of the bucket.
     *  @param  index_        The index of the bucket to calculate exchange rate for.
     *  @return exchangeRate_ The exchange rate of the bucket, in RAY units.
     */
    function exchangeRate(uint256 index_) external view returns (uint256 exchangeRate_);

    /**
     *  @notice Returns the Highest Price Bucket (HPB).
     *  @return hpb_ The price value of the current HPB bucket, in WAD units.
     */
    function hpb() external view returns (uint256 hpb_);

    /**
     *  @notice Returns the Highest Threshold Price (HTP).
     *  @dev    If no loans in queue returns 0
     *  @dev    Value is scaled by current pool inflator snapshot
     *  @return htp_ The price value of the current HTP bucket, in WAD units.
     */
    function htp() external view returns (uint256 htp_);

    /**
     *  @notice Returns the bucket price of for a specific index.
     *  @param  index_ Bucket index
     *  @return price_ Bucket price, WAD units.
     */
    function indexToPrice(uint256 index_) external view returns (uint256 price_);

    /**
     *  @notice Returns the number of loans in pool
     */
    function loansCount() external view returns (uint256);

    /**
     *  @notice Calculate the amount of quote tokens for a given amount of LP Tokens.
     *  @param  deposit_     The amount of quote tokens available at this bucket index.
     *  @param  lpTokens_    The number of lpTokens to calculate amounts for.
     *  @param  index_       The price bucket index for which the value should be calculated.
     *  @return quoteAmount_ The exact amount of quote tokens that can be exchanged for the given LP Tokens, WAD units.
     */
    function lpsToQuoteTokens(uint256 deposit_, uint256 lpTokens_, uint256 index_) external view returns (uint256 quoteAmount_);

    /**
     *  @notice Returns the Lowest Utilized Price (LUP).
     *  @return lup_ The price value of the current LUP bucket, in WAD units.
     */
    function lup() external view returns (uint256 lup_);

    /**
     *  @notice Returns the Lowest Utilized Price (LUP) bucket index.
     *  @return lupIndex_ The index of the current LUP bucket.
     */
    function lupIndex() external view returns (uint256 lupIndex_);

    /**
     *  @notice Returns the address with the highest TP in pool.
     *  @return borrower_ The address with the highest TP in pool.
     */
    function maxBorrower() external view returns (address borrower_);

    /**
     *  @notice Calculates the pending inflator in pool.
     *  @return pendingInflator_ Pending inflator.
     */
    function pendingInflator() external view returns (uint256 pendingInflator_);

    /**
     *  @notice Gets the current utilization of the pool
     *  @dev    Will return 0 unless the pool has been borrowed from.
     *  @return poolActualUtilization_ The current pool actual utilization, in WAD units.
     */
    function poolActualUtilization() external view returns (uint256 poolActualUtilization_);

    /**
     *  @notice Calculate the current collateralization ratio of the pool, based on `totalDebt` and `totalCollateral`.
     *  @return poolCollateralization_ Current pool collateralization ratio.
     */
    function poolCollateralization() external view returns (uint256 poolCollateralization_);

    /**
     *  @notice Returns the total amount of quote token (depsoit + accumulated interest) in the pool,
     *          regardless of pool debt.
     */
    function poolSize() external view returns (uint256);

    /**
     *  @notice Gets the current target utilization of the pool
     *  @return poolTargetUtilization_ The current pool Target utilization, in WAD units.
     */
    function poolTargetUtilization() external view returns (uint256 poolTargetUtilization_);

    /**
     *  @notice Returns the bucket index of for a specific price.
     *  @param  price_ Bucket price, WAD units.
     *  @return index_ Bucket index
     */
    function priceToIndex(uint256 price_) external view returns (uint256 index_);

    /**
     *  @notice Returns the address of the pools quote token
     */
    function quoteTokenAddress() external pure returns (address);

    /**
     *  @notice Returns the state of the Claimaible Reserve Auction.
     *  @return claimableReservesRemaining_ Amount of claimable reserves which has not yet been taken.
     *  @return auctionPrice_               Current price at which 1 quote token may be purchased, denominated in Ajna.
     */
    function reserveAuction() external view returns (
        uint256 claimableReservesRemaining_,
        uint256 auctionPrice_
        // TODO: should I add a timeRemaining_ field?
    );
}
