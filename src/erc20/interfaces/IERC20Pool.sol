// SPDX-License-Identifier: MIT
pragma solidity 0.8.14;

import { IScaledPool } from "../../base/interfaces/IScaledPool.sol";

/**
 * @title Ajna ERC20 Pool
 */
interface IERC20Pool is IScaledPool {

    /************************/
    /*** ERC20Pool Events ***/
    /************************/

    /**
     *  @notice Emitted when borrower locks collateral in the pool.
     *  @param  borrower_ `msg.sender`.
     *  @param  amount_   Amount of collateral locked in the pool.
     */
    event AddCollateral(address indexed borrower_, uint256 amount_);

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
     *  @param  amount_  The amount of Quote tokens transferred to the claimer.
     *  @param  lps_     The amount of LP tokens burned in the claim.
     */
    event ClaimCollateral(address indexed claimer_, uint256 indexed price_, uint256 amount_, uint256 lps_);

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
     *  @notice Emitted when borrower repays quote tokens to the pool.
     *  @param  borrower_ `msg.sender`.
     *  @param  lup_      LUP after repay.
     *  @param  amount_   Amount of quote tokens repayed to the pool.
     */
    event Repay(address indexed borrower_, uint256 lup_, uint256 amount_);

    /*********************************/
    /*** ERC20Pool State Variables ***/
    /*********************************/

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

    /*********************************************/
    /*** ERC20Pool Borrower External Functions ***/
    /*********************************************/

    /**
     *  @notice Called by borrowers to add collateral to the pool.
     *  @param  amount_  The amount of collateral in deposit tokens to be added to the pool.
     *  @param  oldPrev_ Previous borrower that came before placed loan (old)
     *  @param  newPrev_ Previous borrower that now comes before placed loan (new)
     */
    function addCollateral(uint256 amount_, address oldPrev_, address newPrev_) external;

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
     *  @notice Called by borrowers to remove an amount of collateral.
     *  @param  amount_ The amount of collateral in deposit tokens to be removed from a position.
     *  @param  oldPrev_ Previous borrower that came before placed loan (old)
     *  @param  newPrev_ Previous borrower that now comes before placed loan (new)
     */
    function removeCollateral(uint256 amount_, address oldPrev_, address newPrev_) external;

    /**
     *  @notice Called by a borrower to repay some amount of their borrowed quote tokens.
     *  @param  maxAmount_ WAD The maximum amount of quote token to repay.
     *  @param  oldPrev_   Previous borrower that came before placed loan (old)
     *  @param  newPrev_   Previous borrower that now comes before placed loan (new)
     */
    function repay(uint256 maxAmount_, address oldPrev_, address newPrev_) external;

    /*****************************/
    /*** Initialize Functions ***/
    /*****************************/

    /**
     *  @notice Initializes a new pool, setting initial state variables.
     *  @param  interestRate_ Default interest rate of the pool.
     */
    function initialize(uint256 interestRate_) external;

    /*******************************************/
    /*** ERC20Pool Lender External Functions ***/
    /*******************************************/

    /**
     *  @notice Called by lenders to claim unencumbered collateral from a price bucket.
     *  @param  amount_ The amount of unencumbered collateral to claim.
     *  @param  index_  The index of the bucket from which unencumbered collateral will be claimed.
     */
    function claimCollateral(uint256 amount_, uint256 index_) external;

    /************************************/
    /*** ERC20Pool External Functions ***/
    /************************************/

    /**
     *  @notice Purchase amount of quote token from specified bucket price.
     *  @param  amount_ Amount of quote tokens to purchase.
     *  @param  index_  The bucket index from which quote tokens will be purchased.
     */
    function purchaseQuote(uint256 amount_, uint256 index_) external;

    /**********************/
    /*** View Functions ***/
    /**********************/

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
}
