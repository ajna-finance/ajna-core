// SPDX-License-Identifier: MIT
pragma solidity 0.8.11;

/**
 * @title Ajna Pool
 * @dev   Used to manage lender and borrower positions of ERC-20 tokens.
 */
interface IPool {

    /***************/
    /*** Structs ***/
    /***************/

    /**
     *  @notice Struct holding borrower related info per price bucket
     *  @param  debt                Borrower debt, WAD
     *  @param  collateralDeposited Collateral deposited by borrower, WAD
     *  @param  inflatorSnapshot    Current borrower inflator snapshot, RAY
     */
    struct BorrowerInfo {
        uint256 debt;
        uint256 collateralDeposited;
        uint256 inflatorSnapshot;
    }

    /**************/
    /*** Events ***/
    /**************/

    /**
     *  @notice Emitted when lender adds quote token to the pool
     *  @param  lender_ Recipient that added quote tokens
     *  @param  price_  Price at which quote tokens were added
     *  @param  amount_ Amount of quote tokens added to the pool
     *  @param  lup_    LUP calculated after deposit
     */
    event AddQuoteToken(address indexed lender_, uint256 indexed price_, uint256 amount_, uint256 lup_);

    /**
     *  @notice Emitted when lender removes quote token from the pool
     *  @param  lender_ Recipient that removed quote tokens
     *  @param  price_  Price at which quote tokens were removed
     *  @param  amount_ Amount of quote tokens removed from the pool
     *  @param  lup_    LUP calculated after removal
     */
    event RemoveQuoteToken(address indexed lender_, uint256 indexed price_, uint256 amount_, uint256 lup_);

    /**
     *  @notice Emitted when borrower locks collateral in the pool
     *  @param  borrower_ `msg.sender`
     *  @param  amount_   Amount of collateral locked in the pool
     */
    event AddCollateral(address indexed borrower_, uint256 amount_);

    /**
     *  @notice Emitted when borrower removes collateral from the pool
     *  @param  borrower_ `msg.sender`
     *  @param  amount_   Amount of collateral removed from the pool
     */
    event RemoveCollateral(address indexed borrower_, uint256 amount_);

    /**
     *  @notice Emitted when lender claims unencumbered collateral
     *  @param  claimer_ Recipient that claimed collateral
     *  @param  price_   Price at which unencumbered collateral was claimed
     *  @param  amount_  TODO
     *  @param  lps_     TODO
     */
    event ClaimCollateral(address indexed claimer_, uint256 indexed price_, uint256 amount_, uint256 lps_);

    /**
     *  @notice Emitted when borrower borrows quote tokens from pool
     *  @param  borrower_ `msg.sender`
     *  @param  lup_      LUP after borrow
     *  @param  amount_   Amount of quote tokens borrowed from the pool
     */
    event Borrow(address indexed borrower_, uint256 lup_, uint256 amount_);

    /**
     *  @notice Emitted when borrower repays quote tokens to the pool
     *  @param  borrower_ `msg.sender`
     *  @param  lup_      LUP after repay
     *  @param  amount_   Amount of quote tokens repayed to the pool
     */
    event Repay(address indexed borrower_, uint256 lup_, uint256 amount_);

    /**
     *  @notice Emitted when pool interest rate is updated
     *  @param  oldRate_ Old pool interest rate
     *  @param  newRate_ New pool interest rate
     */
    event UpdateInterestRate(uint256 oldRate_, uint256 newRate_);

    /**
     *  @notice Emitted when collateral is exchanged for quote tokens
     *  @param  bidder_     `msg.sender`
     *  @param  price_      Price at which collateral was exchanged for quote tokens
     *  @param  amount_     Amount of quote tokens purchased
     *  @param  collateral_ Amount of collateral exchanged for quote tokens
     */
    event Purchase(address indexed bidder_, uint256 indexed price_, uint256 amount_, uint256 collateral_);

    /**
     *  @notice Emitted when a borrower is liquidated
     *  @param  borrower_   Borrower that was liquidated
     *  @param  debt_       Debt recovered after borrower was liquidated
     *  @param  collateral_ Collateral used to recover debt when user liquidated
     */
    event Liquidate(address indexed borrower_, uint256 debt_, uint256 collateral_);

    /*********************/
    /*** Custom Errors ***/
    /*********************/

    /**
     *  @notice Pool already initialized
     */
    error AlreadyInitialized();

    /**
     *  @notice Invalid price bucket provided
     */
    error InvalidPrice();

    /**
     *  @notice Recipient doesn't have any collateral to claim
     */
    error NoClaimToBucket();

    /**
     *  @notice No debt to be repaid by borrower
     */
    error NoDebtToRepay();

    /**
     *  @notice No debt to be liquidated for borrower
     */
    error NoDebtToLiquidate();

    /**
     *  @notice Borrower doesn't have enough tokens to repay desired amount
     */
    error InsufficientBalanceForRepay();

    /**
     *  @notice Not enough collateral to purchase bid
     */
    error InsufficientCollateralBalance();

    /**
     *  @notice Borrower doesn't have enough collateral to borrow desired amount
     */
    error InsufficientCollateralForBorrow();

    /**
     *  @notice Not enough liquidity in pool to borrow desired amount
     *  @param  amountAvailable_ Amount of quote tokens available in pool
     */
    error InsufficientLiquidity(uint256 amountAvailable_);

    /**
     *  @notice Pool is undercollateralized after remove quote token, borrow or purchase bid actions
     *  @param  collateralization_ Collateralization of the pool
     */
    error PoolUndercollateralized(uint256 collateralization_);

    /**
     *  @notice Borrower is not eligible for liquidation
     *  @param  collateralization_ Borrower collateralization
     */
    error BorrowerIsCollateralized(uint256 collateralization_);

    /**
     *  @notice Borrower doesn't have enough collateral to remove from pool
     *  @param  availableCollateral_ Available collateral in pool that can be removed by borrower
     */
    error AmountExceedsAvailableCollateral(uint256 availableCollateral_);

    /**************************/
    /*** External Functions ***/
    /**************************/

    /**
     *  @notice Called by lenders to add an amount of credit at a specified price bucket
     *  @param  recipient_ The recipient adding quote tokens
     *  @param  amount_    The amount of quote token to be added by a lender
     *  @param  price_     The bucket to which the quote tokens will be added
     *  @return lpTokens_  The amount of LP Tokens received for the added quote tokens
     */
    function addQuoteToken(address recipient_, uint256 amount_, uint256 price_) external returns (uint256 lpTokens_);

    /**
     *  @notice Called by lenders to remove an amount of credit at a specified price bucket
     *  @param  recipient_ The recipient removing quote tokens
     *  @param  maxAmount_ The maximum amount of quote token to be removed by a lender
     *  @param  price_     The bucket from which quote tokens will be removed
     */
    function removeQuoteToken(address recipient_, uint256 maxAmount_, uint256 price_) external;

    /**
     *  @notice Called by borrowers to add collateral to the pool
     *  @param  amount_ The amount of collateral in deposit tokens to be added to the pool
     */
    function addCollateral(uint256 amount_) external;

    /**
     *  @notice Called by borrowers to remove an amount of collateral
     *  @param  amount_ The amount of collateral in deposit tokens to be removed from a position
     */
    function removeCollateral(uint256 amount_) external;

    /**
     *  @notice Called by lenders to claim unencumbered collateral from a price bucket
     *  @param  recipient_ The recipient claiming collateral
     *  @param  amount_    The amount of unencumbered collateral to claim
     *  @param  price_     The bucket from which unencumbered collateral will be claimed
     */
    function claimCollateral(address recipient_, uint256 amount_, uint256 price_) external;

    /**
     *  @notice Called by a borrower to open or expand a position
     *  @dev    Can only be called if quote tokens have already been added to the pool
     *  @param  amount_     The amount of quote token to borrow
     *  @param  limitPrice_ Lower bound of LUP change (if any) that the borrower will tolerate from a creating or modifying position
     */
    function borrow(uint256 amount_, uint256 limitPrice_) external;

    /**
     *  @notice Called by a borrower to repay some amount of their borrowed quote tokens
     *  @param  maxAmount_ WAD The maximum amount of quote token to repay
     */
    function repay(uint256 maxAmount_) external;

    /**
     *  @notice Exchanges collateral for quote token
     *  @param  amount_ WAD The amount of quote token to purchase
     *  @param  price_  The purchasing price of quote token
     */
    function purchaseBid(uint256 amount_, uint256 price_) external;

    /**
     *  @notice Liquidates a given borrower's position
     *  @param  borrower_ The address of the borrower being liquidated
     */
    function liquidate(address borrower_) external;

    /**********************/
    /*** View Functions ***/
    /**********************/

    /**
     *  @notice Returns a given lender's LP tokens in a given price bucket
     *  @param  owner_    The EOA to check token balance for
     *  @param  price_    The price bucket for which the value should be calculated, WAD
     *  @return lpTokens_ The EOA's lp token balance in the bucket, RAY
     */
    function getLPTokenBalance(address owner_, uint256 price_) external view returns (uint256 lpTokens_);

    /**
     *  @notice Calculate the amount of collateral and quote tokens for a given amount of LP Tokens
     *  @param  lpTokens_         The number of lpTokens to calculate amounts for
     *  @param  price_            The price bucket for which the value should be calculated
     *  @return collateralTokens_ The equivalent value of collateral tokens for the given LP Tokens, WAD
     *  @return quoteTokens_      The equivalent value of quote tokens for the given LP Tokens, WAD
     */
    function getLPTokenExchangeValue(uint256 lpTokens_, uint256 price_) external view returns (uint256 collateralTokens_, uint256 quoteTokens_);

}
