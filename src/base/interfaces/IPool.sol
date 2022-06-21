// SPDX-License-Identifier: MIT
pragma solidity 0.8.14;

/**
 * @title Ajna Pool
 * @dev   Used to manage lender and borrower positions.
 */
interface IPool {

    /**************/
    /*** Events ***/
    /**************/

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

    /***********************/
    /*** State Variables ***/
    /***********************/

    /**
     *  @notice Returns the `quoteTokenScale` state variable.
     *  @return quoteTokenScale_ The precision of the quote ERC-20 token based on decimals.
     */
    function quoteTokenScale() external view returns (uint256 quoteTokenScale_);

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
     *  @param  limitPrice_ Lower bound of LUP change (if any) that the borrower will tolerate from a creating or modifying position.
     */
    function borrow(uint256 amount_, uint256 limitPrice_) external;

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
     *  @notice Called by lenders to move an amount of credit from a specified price bucket to another specified price bucket.
     *  @param  recipient_ The recipient moving quote tokens.
     *  @param  maxAmount_ The maximum amount of quote token to be moved by a lender.
     *  @param  fromPrice_ The bucket from which the quote tokens will be removed.
     *  @param  toPrice_   The bucket to which the quote tokens will be added.
     */
    function moveQuoteToken(address recipient_, uint256 maxAmount_, uint256 fromPrice_, uint256 toPrice_) external;

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
     *  @notice Liquidates a given borrower's position.
     *  @param  borrower_ The address of the borrower being liquidated.
     */
    function liquidate(address borrower_) external;

}
