// SPDX-License-Identifier: MIT
pragma solidity 0.8.11;

/**
 * @title Ajna Pool
 * @dev   Used to manage lender and borrower positions of ERC-20 tokens.
 */
interface IPool {

    /**************/
    /*** Events ***/
    /**************/

    /**
     *  @notice Emitted when borrower locks collateral in the pool.
     *  @param  borrower_ `msg.sender`.
     *  @param  amount_   Amount of collateral locked in the pool.
     */
    event AddCollateral(address indexed borrower_, uint256 amount_);

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
     *  @notice Emitted when lender claims unencumbered collateral.
     *  @param  claimer_ Recipient that claimed collateral.
     *  @param  price_   Price at which unencumbered collateral was claimed.
     *  @param  amount_  TODO
     *  @param  lps_     TODO
     */
    event ClaimCollateral(address indexed claimer_, uint256 indexed price_, uint256 amount_, uint256 lps_);

    /**
     *  @notice Emitted when a borrower is liquidated.
     *  @param  borrower_   Borrower that was liquidated.
     *  @param  debt_       Debt recovered after borrower was liquidated.
     *  @param  collateral_ Collateral used to recover debt when user liquidated.
     */
    event Liquidate(address indexed borrower_, uint256 debt_, uint256 collateral_);

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
     *  @notice Emitted when collateral is exchanged for quote tokens.
     *  @param  bidder_     `msg.sender`.
     *  @param  price_      Price at which collateral was exchanged for quote tokens.
     *  @param  amount_     Amount of quote tokens purchased.
     *  @param  collateral_ Amount of collateral exchanged for quote tokens.
     */
    event Purchase(address indexed bidder_, uint256 indexed price_, uint256 amount_, uint256 collateral_);

    /**
     *  @notice Emitted when borrower removes collateral from the pool.
     *  @param  borrower_ `msg.sender`.
     *  @param  amount_   Amount of collateral removed from the pool.
     */
    event RemoveCollateral(address indexed borrower_, uint256 amount_);

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

    /***************/
    /*** Structs ***/
    /***************/

    /**
     *  @notice Struct holding borrower related info per price bucket.
     *  @param  debt                Borrower debt, WAD units.
     *  @param  collateralDeposited Collateral deposited by borrower, WAD units.
     *  @param  inflatorSnapshot    Current borrower inflator snapshot, RAY units.
     */
    struct BorrowerInfo {
        uint256 debt;
        uint256 collateralDeposited;
        uint256 inflatorSnapshot;
    }

    /***********************/
    /*** State Variables ***/
    /***********************/

    // TODO: Investigate `collateral()` and `quoteToken()` functions.

    /**
     *  @notice Returns the `collateralScale` state variable.
     *  @return collateralScale_ The precision of the collateral ERC-20 token based on decimals.
     */
    function collateralScale() external view returns (uint256 collateralScale_);

    /**
     *  @notice Returns the `quoteTokenScale` state variable.
     *  @return quoteTokenScale_ The precision of the quote ERC-20 token based on decimals.
     */
    function quoteTokenScale() external view returns (uint256 quoteTokenScale_);

    /**
     *  @notice Returns the `previousRateUpdate` state variable.
     *  @return previousRateUpdate_ The timestamp of the last rate update.
     */
    function previousRateUpdate() external view returns (uint256 previousRateUpdate_);

    /**
     *  @notice Returns the `totalCollateral` state variable.
     *  @return totalCollateral_ THe total amount of collateral in the system, in WAD units.
     */
    function totalCollateral() external view returns (uint256 totalCollateral_);

    /**
     *  @notice Returns the `totalQuoteToken` state variable.
     *  @return totalQuoteToken_ The total amount of quote token in the system, in WAD units.
     */
    function totalQuoteToken() external view returns (uint256 totalQuoteToken_);

    /*****************************/
    /*** Inititalize Functions ***/
    /*****************************/

    /**
     *  @notice Initializes a new pool, setting initial state variables.
     */
    function initialize() external;

    /***********************************/
    /*** Borrower External Functions ***/
    /***********************************/

    /**
     *  @notice Called by borrowers to add collateral to the pool.
     *  @param  amount_ The amount of collateral in deposit tokens to be added to the pool.
     */
    function addCollateral(uint256 amount_) external;

    /**
     *  @notice Called by a borrower to open or expand a position.
     *  @dev    Can only be called if quote tokens have already been added to the pool.
     *  @param  amount_     The amount of quote token to borrow.
     *  @param  limitPrice_ Lower bound of LUP change (if any) that the borrower will tolerate from a creating or modifying position.
     */
    function borrow(uint256 amount_, uint256 limitPrice_) external;

    /**
     *  @notice Called by borrowers to remove an amount of collateral.
     *  @param  amount_ The amount of collateral in deposit tokens to be removed from a position.
     */
    function removeCollateral(uint256 amount_) external;

    /**
     *  @notice Called by a borrower to repay some amount of their borrowed quote tokens.
     *  @param  maxAmount_ WAD The maximum amount of quote token to repay.
     */
    function repay(uint256 maxAmount_) external;

    /*********************************/
    /*** Lender External Functions ***/
    /*********************************/

    /**
     *  @notice Called by lenders to add an amount of credit at a specified price bucket.
     *  @param  recipient_ The recipient adding quote tokens.
     *  @param  amount_    The amount of quote token to be added by a lender.
     *  @param  price_     The bucket to which the quote tokens will be added.
     *  @return lpTokens_  The amount of LP Tokens received for the added quote tokens.
     */
    function addQuoteToken(address recipient_, uint256 amount_, uint256 price_) external returns (uint256 lpTokens_);

    /**
     *  @notice Called by lenders to claim unencumbered collateral from a price bucket.
     *  @param  recipient_ The recipient claiming collateral.
     *  @param  amount_    The amount of unencumbered collateral to claim.
     *  @param  price_     The bucket from which unencumbered collateral will be claimed.
     */
    function claimCollateral(address recipient_, uint256 amount_, uint256 price_) external;

    /**
     *  @notice Called by lenders to move an amount of credit from a specified price bucket to another specified price bucket.
     *  @param  recipient_ The recipient moving quote tokens.
     *  @param  amount_    The amount of quote token to be moved by a lender.
     *  @param  fromPrice_ The bucket from which the quote tokens will be removed.
     *  @param  toPrice_   The bucket to which the quote tokens will be added.
     */
    function moveQuoteToken(address recipient_, uint256 amount_, uint256 fromPrice_, uint256 toPrice_) external;

    /**
     *  @notice Called by lenders to remove an amount of credit at a specified price bucket.
     *  @param  recipient_ The recipient removing quote tokens.
     *  @param  maxAmount_ The maximum amount of quote token to be removed by a lender.
     *  @param  price_     The bucket from which quote tokens will be removed.
     */
    function removeQuoteToken(address recipient_, uint256 maxAmount_, uint256 price_) external;

    /*******************************/
    /*** Pool External Functions ***/
    /*******************************/

    /**
     *  @notice Exchanges collateral for quote token.
     *  @param  amount_ WAD The amount of quote token to purchase.
     *  @param  price_  The purchasing price of quote token.
     */
    function purchaseBid(uint256 amount_, uint256 price_) external;

    /**
     *  @notice Liquidates a given borrower's position.
     *  @param  borrower_ The address of the borrower being liquidated.
     */
    function liquidate(address borrower_) external;

    /**
     *  @notice Called to update the pool interest rate when actual > target utilization.
     */
    function updateInterestRate() external;

    /*******************************/
    /*** Borrower View Functions ***/
    /*******************************/

    /**
     *  @notice Mapping of borrower addresses to {BorrowerInfo} structs.
     *  @dev    NOTE: Cannot use appended underscore syntax for return params since struct is used.
     *  @param  borrower_           Address of the borrower.
     *  @return debt                Amount of debt that the borrower has, in quote token.
     *  @return collateralDeposited Amount of collateral that the borrower has deposited, in collateral token.
     *  @return inflatorSnapshot    Snapshot of inflator value used to track interest on loans.
     */
    function borrowers(address borrower_) external view returns (uint256 debt, uint256 collateralDeposited, uint256 inflatorSnapshot);

    /**
     *  @notice Returns the collateralization based on given collateral deposited and debt.
     *  @dev    Supports passage of collateralDeposited and debt to enable calculation of potential borrower collateralization states, not just current.
     *  @param  collateralDeposited_       Collateral amount to calculate a collateralization ratio for, in RAY units.
     *  @param  debt_                      Debt position to calculate encumbered quotient, in RAY units.
     *  @return borrowerCollateralization_ The current collateralization of the borrowers given totalCollateral and totalDebt
     */
    function getBorrowerCollateralization(uint256 collateralDeposited_, uint256 debt_) external view returns (uint256 borrowerCollateralization_);

    /**
     *  @notice Returns a tuple of information about a given borrower.
     *  @param  borrower_                 Address of the borrower.
     *  @return debt_                     Amount of debt that the borrower has, in quote token.
     *  @return pendingDebt_              Amount of unaccrued debt that the borrower has, in quote token.
     *  @return collateralDeposited_      Amount of collateral that tne borrower has deposited, in collateral token.
     *  @return collateralEncumbered_     Amount of collateral that the borrower has encumbered, in collateral token.
     *  @return collateralization_        Collateral ratio of the borrower's pool position.
     *  @return borrowerInflatorSnapshot_ Snapshot of the borrower's inflator value.
     *  @return inflatorSnapshot_         Snapshot of the pool's inflator value.
     */
    function getBorrowerInfo(address borrower_) external view returns (
        uint256 debt_,
        uint256 pendingDebt_,
        uint256 collateralDeposited_,
        uint256 collateralEncumbered_,
        uint256 collateralization_,
        uint256 borrowerInflatorSnapshot_,
        uint256 inflatorSnapshot_
    );

    /***************************/
    /*** Pool View Functions ***/
    /***************************/

    /**
     *  @notice Estimate the price for which a loan can be taken.
     *  @param  amount_  Amount of debt to draw.
     *  @return price_   Price of the loan.
     */
    function estimatePriceForLoan(uint256 amount_) external view returns (uint256 price_);

    /**
     *  @notice Returns the total encumbered collateral resulting from a given amount of debt.
     *  @dev    Used for both pool and borrower level debt.
     *  @param  debt_        Amount of debt for corresponding collateral encumbrance.
     *  @return encumbrance_ The current encumbrance of a given debt balance, in WAD units.
     */
    function getEncumberedCollateral(uint256 debt_) external view returns (uint256 encumbrance_);

    /**
     *  @notice Returns the current minimum pool price.
     *  @return minPrice_ The current minimum pool price.
     */
    function getMinimumPoolPrice() external view returns (uint256 minPrice_);

    /**
     *  @notice Gets the current utilization of the pool
     *  @dev    Will return 0 unless the pool has been borrowed from.
     *  @return poolActualUtilization_ The current pool actual utilization, in WAD units.
     */
    function getPoolActualUtilization() external view returns (uint256 poolActualUtilization_);

    /**
     *  @notice Calculate the current collateralization ratio of the pool, based on `totalDebt` and `totalCollateral`.
     *  @return poolCollateralization_ Current pool collateralization ratio.
     */
    function getPoolCollateralization() external view returns (uint256 poolCollateralization_);

    /**
     *  @notice Gets the current target utilization of the pool
     *  @return poolTargetUtilization_ The current pool Target utilization, in WAD units.
     */
    function getPoolTargetUtilization() external view returns (uint256 poolTargetUtilization_);

}
