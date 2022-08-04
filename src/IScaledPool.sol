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
     *  @notice Emitted when borrower borrows quote tokens from pool.
     *  @param  borrower_ `msg.sender`.
     *  @param  lup_      LUP after borrow.
     *  @param  amount_   Amount of quote tokens borrowed from the pool.
     */
    event Borrow(address indexed borrower_, uint256 lup_, uint256 amount_);

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
     *  @notice Emitted when borrower repays quote tokens to the pool.
     *  @param  borrower_ `msg.sender`.
     *  @param  lup_      LUP after repay.
     *  @param  amount_   Amount of quote tokens repayed to the pool.
     */
    event Repay(address indexed borrower_, uint256 lup_, uint256 amount_);

    /**
     *  @notice Emitted when pool interest rate is updated.
     *  @param  oldRate_ Old pool interest rate.
     *  @param  newRate_ New pool interest rate.
     */
    event UpdateInterestRate(uint256 oldRate_, uint256 newRate_);

    /********************/
    /*** ERC20 Events ***/
    /********************/

    /**
     *  @notice Emitted when borrower locks collateral in the pool.
     *  @param  borrower_ `msg.sender`.
     *  @param  amount_   Amount of collateral locked in the pool.
     */
    event PledgeCollateral(address indexed borrower_, uint256 amount_);

    /**
     *  @notice Emitted when lender claims unencumbered collateral.
     *  @param  claimer_ Recipient that claimed collateral.
     *  @param  price_   Price at which unencumbered collateral was claimed.
     *  @param  amount_  The amount of Quote tokens transferred to the claimer.
     *  @param  lps_     The amount of LP tokens burned in the claim.
     */
    event ClaimCollateral(address indexed claimer_, uint256 indexed price_, uint256 amount_, uint256 lps_);

    /**
     *  @notice Emitted when borrower removes collateral from the pool.
     *  @param  borrower_ `msg.sender`.
     *  @param  amount_   Amount of collateral removed from the pool.
     */
    event RemoveCollateral(address indexed borrower_, uint256 amount_);

    /***********************/
    /*** State Variables ***/
    /***********************/

    /**
     *  @notice Mapping of buckets indexes to {Borrower} structs.
     *  @dev    NOTE: Cannot use appended underscore syntax for return params since struct is used.
     *  @param  index_        Bucket index.
     *  @return lpAccumulator       Amount of LPs accumulated in current bucket.
     *  @return availableCollateral Amount of collateral available in current bucket.
     */
    function buckets(uint256 index_) external view returns (uint256 lpAccumulator, uint256 availableCollateral);

    /**
     *  @notice Returns the `borrowerDebt` state variable.
     *  @return borrowerDebt_ Total amount of borrower debt in pool.
     */
    function borrowerDebt() external view returns (uint256 borrowerDebt_);

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
     *  @notice Returns the `lenderDebt` state variable.
     *  @return lenderDebt_ Total amount of lender debt in pool.
     */
    function lenderDebt() external view returns (uint256 lenderDebt_);

    /**
     *  @notice Returns the `lupColEma` state variable.
     *  @return lupColEma_ Exponential LUP * pledged collateral moving average.
     */
    function lupColEma() external view returns (uint256 lupColEma_);

    /**
     *  @notice Nested mapping of lender's LP token balance at different price buckets.
     *  @param  depositIndex_ Index of the deposit / bucket.
     *  @param  lp_           Address of the LP.
     *  @return balance_      LP token balance of the lender at the queried deposit index.
     */
    function lpBalance(uint256 depositIndex_, address lp_) external view returns (uint256 balance_);

    /**
     *  @notice Returns the `minFee` state variable.
     *  @return minFee_ TODO
     */
    function minFee() external view returns (uint256 minFee_);

    /**
     *  @notice Returns the `quoteTokenScale` state variable.
     *  @return quoteTokenScale_ The precision of the quote ERC-20 token based on decimals.
     */
    function quoteTokenScale() external view returns (uint256 quoteTokenScale_);

    /**
     *  @notice Returns the `pledgedCollateral` state variable.
     *  @return pledgedCollateral_ The total pledged collateral in the system, in WAD units.
     */
    function pledgedCollateral() external view returns (uint256 pledgedCollateral_);

    /**
     *  @notice Returns the `totalBorrowers` state variable.
     *  @return totalBorrowers_ The total number of borrowers in pool.
     */
    function totalBorrowers() external view returns (uint256 totalBorrowers_);

    /*****************************/
    /*** ERC20 State Variables ***/
    /*****************************/

    /**
     *  @notice Mapping of borrower addresses to {Borrower} structs.
     *  @dev    NOTE: Cannot use appended underscore syntax for return params since struct is used.
     *  @param  borrower_        Address of the borrower.
     *  @return debt             Amount of debt that the borrower has, in quote token.
     *  @return collateral       Amount of collateral that the borrower has deposited, in collateral token.
     *  @return inflatorSnapshot Snapshot of inflator value used to track interest on loans.
     */
    function borrowers(address borrower_) external view returns (uint256 debt, uint256 collateral, uint256 inflatorSnapshot);

    /**
     *  @notice Returns the `collateralScale` state variable.
     *  @return collateralScale_ The precision of the collateral ERC-20 token based on decimals.
     */
    function collateralScale() external view returns (uint256 collateralScale_);

    /***************/
    /*** Structs ***/
    /***************/

    /**
     *  @notice Struct holding borrower related info.
     *  @param  debt             Borrower debt, WAD units.
     *  @param  collateral       Collateral deposited by borrower, WAD units.
     *  @param  inflatorSnapshot Current borrower inflator snapshot, WAD units.
     */
    struct Borrower {
        uint256 debt;                // [WAD]
        uint256 collateral;          // [WAD]
        uint256 inflatorSnapshot;    // [WAD]
    }

    /**
     *  @notice struct holding bucket info
     *  @param lpAccumulator       Bucket LP accumulator, RAY
     *  @param availableCollateral Available collateral tokens deposited in the bucket, WAD
     */
    struct Bucket {
        uint256 lpAccumulator;       // [RAY]
        uint256 availableCollateral; // [WAD]
    }

    /*****************************/
    /*** Inititalize Functions ***/
    /*****************************/

    /**
     *  @notice Initializes a new pool, setting initial state variables.
     *  @param  interestRate_ Default interest rate of the pool.
     */
    function initialize(uint256 interestRate_) external;

    /***********************************/
    /*** Borrower External Functions ***/
    /***********************************/

    /**
     *  @notice Called by a borrower to open or expand a position.
     *  @dev    Can only be called if quote tokens have already been added to the pool.
     *  @param  amount_     The amount of quote token to borrow.
     *  @param  limitIndex_ Lower bound of LUP change (if any) that the borrower will tolerate from a creating or modifying position.
     *  @param  oldPrev_    Previous borrower that came before placed loan (old)
     *  @param  newPrev_    Previous borrower that now comes before placed loan (new)
     */
    function borrow(uint256 amount_, uint256 limitIndex_, address oldPrev_, address newPrev_) external;

    /**
     *  @notice Called by a borrower to repay some amount of their borrowed quote tokens.
     *  @param  maxAmount_ WAD The maximum amount of quote token to repay.
     *  @param  oldPrev_   Previous borrower that came before placed loan (old)
     *  @param  newPrev_   Previous borrower that now comes before placed loan (new)
     */
    function repay(uint256 maxAmount_, address oldPrev_, address newPrev_) external;

    /*****************************************/
    /*** ERC20 Borrower External Functions ***/
    /*****************************************/

    /**
     *  @notice Called by borrowers to add collateral to the pool.
     *  @param  amount_  The amount of collateral in deposit tokens to be added to the pool.
     *  @param  oldPrev_ Previous borrower that came before placed loan (old)
     *  @param  newPrev_ Previous borrower that now comes before placed loan (new)
     */
    function pledgeCollateral(uint256 amount_, address oldPrev_, address newPrev_) external;

    /**
     *  @notice Called by borrowers to remove an amount of collateral.
     *  @param  amount_ The amount of collateral in deposit tokens to be removed from a position.
     *  @param  oldPrev_ Previous borrower that came before placed loan (old)
     *  @param  newPrev_ Previous borrower that now comes before placed loan (new)
     */
    function removeCollateral(uint256 amount_, address oldPrev_, address newPrev_) external;

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
     *  @notice Called by lenders to move an amount of credit from a specified price bucket to another specified price bucket.
     *  @param  lpbAmount_ The maximum amount of quote token to be moved by a lender.
     *  @param  fromIndex_ The bucket index from which the quote tokens will be removed.
     *  @param  toIndex_   The bucket index to which the quote tokens will be added.
     */
    function moveQuoteToken(uint256 lpbAmount_, uint256 fromIndex_, uint256 toIndex_) external;

    /**
     *  @notice Called by lenders to remove an amount of credit at a specified price bucket.
     *  @param  lpbAmount_  The amount of LP tokens to be removed by a lender.
     *  @param  index_      The bucket index from which quote tokens will be removed.
     */
    function removeQuoteToken(uint256 lpbAmount_, uint256 index_) external;

    /***************************************/
    /*** ERC20 Lender External Functions ***/
    /***************************************/

    /**
     *  @notice Deposit unencumbered collateral into a specified bucket.
     *  @param  amount_ Amount of collateral to deposit.
     *  @param  index_  The bucket index to which collateral will be deposited.
     */
    function addCollateral(uint256 amount_, uint256 index_) external returns (uint256 lpbChange_);

    /**
     *  @notice Called by lenders to claim unencumbered collateral from a price bucket.
     *  @param  amount_ The amount of unencumbered collateral to claim.
     *  @param  index_  The index of the bucket from which unencumbered collateral will be claimed.
     */
    function claimCollateral(uint256 amount_, uint256 index_) external;

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
     *  @notice Returns exchange rate of the bucket.
     *  @param  index_        The index of the bucket to calculate exchange rate for.
     *  @return exchangeRate_ The exchange rate of the bucket, in WAD units.
     */
    function exchangeRate(uint256 index_) external view returns (uint256 exchangeRate_);

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
     *  @notice Returns the Highest Threshold Price (HTP).
     *  @return htp_ The price value of the current HTP bucket, in WAD units.
     */
    function htp() external view returns (uint256 htp_);

    /**
     *  @notice Returns the bucket index of for a specific price.
     *  @param  price_ Bucket price, WAD units.
     *  @return index_ Bucket index
     */
    function priceToIndex(uint256 price_) external view returns (uint256 index_);

    /**
     *  @notice Returns the bucket price of for a specific index.
     *  @param  index_ Bucket index
     *  @return price_ Bucket price, WAD units.
     */
    function indexToPrice(uint256 index_) external view returns (uint256 price_);

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
     *  @notice Get a borrower info struct for a given address.
     *  @param  borrower_         The borrower address.
     *  @return debt_             Borrower accrued debt (WAD)
     *  @return pendingDebt_      Borrower current debt, accrued and pending accrual (WAD)
     *  @return collateral_       Deposited collateral including encumbered (WAD)
     *  @return inflatorSnapshot_ Inflator used to calculate pending interest (WAD)
     */
    function borrowerInfo(address borrower_)
        external
        view
        returns (
            uint256 debt_,
            uint256 pendingDebt_,
            uint256 collateral_,
            uint256 inflatorSnapshot_
        );

    /**
     *  @notice Returns the total encumbered collateral resulting from a given amount of debt at a specified price.
     *  @param  debt_        Amount of debt for corresponding collateral encumbrance.
     *  @param  price_       Price to use for calculating the collateral encumbrance, in WAD units.
     *  @return encumbrance_ The current encumbrance of a given debt balance, in WAD units.
     */
    function encumberedCollateral(uint256 debt_, uint256 price_) external view returns (uint256 encumbrance_);

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
     *  @notice Gets the current target utilization of the pool
     *  @return poolTargetUtilization_ The current pool Target utilization, in WAD units.
     */
    function poolTargetUtilization() external view returns (uint256 poolTargetUtilization_);
}
