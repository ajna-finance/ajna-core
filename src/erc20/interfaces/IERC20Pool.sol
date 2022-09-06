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
    event PledgeCollateral(address indexed borrower_, uint256 amount_);

    /**
     *  @notice Emitted when borrower borrows quote tokens from pool.
     *  @param  borrower_ `msg.sender`.
     *  @param  lup_      LUP after borrow.
     *  @param  amount_   Amount of quote tokens borrowed from the pool.
     */
    event Borrow(address indexed borrower_, uint256 lup_, uint256 amount_);

    /**
     *  @notice Emitted when actor adds unencumbered collateral to a bucket.
     *  @param  actor_  Recipient that added collateral.
     *  @param  price_  Price at which collateral were added.
     *  @param  amount_ Amount of collateral added to the pool.
     */
    event AddCollateral(address indexed actor_, uint256 indexed price_, uint256 amount_);

    /**
     *  @notice Emitted when lender moves collateral from a bucket price to another.
     *  @param  lender_ Recipient that moved collateral.
     *  @param  from_   Price bucket from which collateral was moved.
     *  @param  to_     Price bucket where collateral was moved.
     *  @param  amount_ Amount of collateral moved.
     */
    event MoveCollateral(address indexed lender_, uint256 indexed from_, uint256 indexed to_, uint256 amount_);

    /**
     *  @notice Emitted when lender claims unencumbered collateral.
     *  @param  claimer_ Recipient that claimed collateral.
     *  @param  price_   Price at which unencumbered collateral was claimed.
     *  @param  amount_  The amount of collateral transferred to the claimer.
     */
    event RemoveCollateral(address indexed claimer_, uint256 indexed price_, uint256 amount_);

    /**
     *  @notice Emitted when borrower removes pledged collateral from the pool.
     *  @param  borrower_ `msg.sender`.
     *  @param  amount_   Amount of collateral removed from the pool.
     */
    event PullCollateral(address indexed borrower_, uint256 amount_);

    /**
     *  @notice Emitted when borrower repays quote tokens to the pool.
     *  @param  borrower_ `msg.sender`.
     *  @param  lup_      LUP after repay.
     *  @param  amount_   Amount of quote tokens repayed to the pool.
     */
    event Repay(address indexed borrower_, uint256 lup_, uint256 amount_);

    /*********************/
    /*** Custom Errors ***/
    /*********************/

    /**
     *  @notice Borrower has no debt to liquidate.
     */
    error LiquidateNoDebt();

    /**
     *  @notice Borrower has a healthy over-collateralized position.
     */
    error LiquidateBorrowerOk();

    /**
     *  @notice Liquidation must result in LUP below the borrowers threshold price.
     */
    error LiquidateLUPGreaterThanTP();

    /**
     *  @notice Lender is attempting to remove collateral when they have no claim to collateral in the bucket.
     */
    error RemoveCollateralNoClaim();

    /**
     *  @notice Take was called before 1 hour had passed from kick time.
     */
    error TakeNotPastCooldown();


    /*********************************/
    /*** ERC20Pool State Variables ***/
    /*********************************/

    /**
     *  @notice Mapping of borrower addresses to {Borrower} structs.
     *  @dev    NOTE: Cannot use appended underscore syntax for return params since struct is used.
     *  @param  borrower_  Address of the borrower.
     *  @return debt       Amount of debt that the borrower has, in quote token.
     *  @return collateral Amount of collateral that the borrower has deposited, in collateral token.
     *  @return inflator   Snapshot of inflator value used to track interest on loans.
     */
    function borrowers(address borrower_) external view returns (uint256 debt, uint256 collateral, uint256 inflator);

    /**
     *  @notice Returns the `collateralScale` state variable.
     *  @return collateralScale_ The precision of the collateral ERC-20 token based on decimals.
     */
    function collateralScale() external view returns (uint256 collateralScale_);

    /*************************/
    /*** ERC20Pool Structs ***/
    /*************************/

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

    /*********************************************/
    /*** ERC20Pool Borrower External Functions ***/
    /*********************************************/

    /**
     *  @notice Called by borrowers to add collateral to the pool.
     *  @param  borrower_ The address of borrower to pledge collateral for.
     *  @param  amount_   The amount of collateral in deposit tokens to be added to the pool.
     *  @param  oldPrev_  Previous borrower that came before placed loan (old)
     *  @param  newPrev_  Previous borrower that now comes before placed loan (new)
     */
    function pledgeCollateral(address borrower_, uint256 amount_, address oldPrev_, address newPrev_) external;

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
    function pullCollateral(uint256 amount_, address oldPrev_, address newPrev_) external;

    /**
     *  @notice Called by a borrower to repay some amount of their borrowed quote tokens.
     *  @param  borrower_  The address of borrower to repay quote token amount for.
     *  @param  maxAmount_ WAD The maximum amount of quote token to repay.
     *  @param  oldPrev_   Previous borrower that came before placed loan (old)
     *  @param  newPrev_   Previous borrower that now comes before placed loan (new)
     */
    function repay(address borrower_, uint256 maxAmount_, address oldPrev_, address newPrev_) external;

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
     *  @notice Deposit unencumbered collateral into a specified bucket.
     *  @param  amount_ Amount of collateral to deposit.
     *  @param  index_  The bucket index to which collateral will be deposited.
     */
    function addCollateral(uint256 amount_, uint256 index_) external returns (uint256 lpbChange_);

    /**
     *  @notice Called by lenders to move an amount of credit from a specified price bucket to another specified price bucket.
     *  @param  amount_        The amount of collateral to be moved by a lender.
     *  @param  fromIndex_     The bucket index from which collateral will be removed.
     *  @param  toIndex_       The bucket index to which collateral will be added.
     *  @return lpbAmountFrom_ The amount of LPs moved out from bucket.
     *  @return lpbAmountTo_   The amount of LPs moved to destination bucket.
     */
    function moveCollateral(uint256 amount_, uint256 fromIndex_, uint256 toIndex_) external returns (uint256 lpbAmountFrom_, uint256 lpbAmountTo_);

    /**
     *  @notice Called by lenders to redeem the maximum amount of LP for unencumbered collateral.
     *  @param  index_    The bucket index from which unencumbered collateral will be removed.
     *  @return amount_   The amount of collateral removed.
     *  @return lpAmount_ The amount of LP used for removing collateral.
     */
    function removeAllCollateral(uint256 index_) external returns (uint256 amount_, uint256 lpAmount_);

    /**
     *  @notice Called by lenders to claim unencumbered collateral from a price bucket.
     *  @param  amount_   The amount of unencumbered collateral to claim.
     *  @param  index_    The bucket index from which unencumbered collateral will be removed.
     *  @return lpAmount_ The amount of LP used for removing collateral amount.
     */
    function removeCollateral(uint256 amount_, uint256 index_) external returns (uint256 lpAmount_);

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
