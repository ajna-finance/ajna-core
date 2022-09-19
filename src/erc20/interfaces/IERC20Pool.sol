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
     *  @notice Emitted when actor adds unencumbered collateral to a bucket.
     *  @param  actor_  Recipient that added collateral.
     *  @param  price_  Price at which collateral were added.
     *  @param  amount_ Amount of collateral added to the pool.
     */
    event AddCollateral(address indexed actor_, uint256 indexed price_, uint256 amount_);

    /**
     *  @notice Emitted when an actor settles debt in a completed liquidation
     *  @param  borrower_           Identifies the loan under liquidation.
     *  @param  hpbIndex_           The index of the Highest Price Bucket where debt was cleared.
     *  @param  amount_             Amount of debt cleared from the HPB in this transaction.
     *  @param  collateralReturned_ Amount of collateral returned to the borrower in this transaction.
     *  @param  amountRemaining_    Amount of debt which still needs to be cleared.
     *  @dev    When amountRemaining_ == 0, the auction has been completed cleared and removed from the queue.
     */
    event Clear(
        address indexed borrower_,
        uint256 hpbIndex_,
        uint256 amount_,
        uint256 collateralReturned_,
        uint256 amountRemaining_);

    /**
     *  @notice Emitted when borrower locks collateral in the pool.
     *  @param  borrower_ `msg.sender`.
     *  @param  amount_   Amount of collateral locked in the pool.
     */
    event PledgeCollateral(address indexed borrower_, uint256 amount_);

    /**
     *  @notice Emitted when borrower removes pledged collateral from the pool.
     *  @param  borrower_ `msg.sender`.
     *  @param  amount_   Amount of collateral removed from the pool.
     */
    event PullCollateral(address indexed borrower_, uint256 amount_);

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
     *  @notice Emitted when an actor uses quote token outside of the book to purchase collateral under liquidation.
     *  @param  borrower_   Identifies the loan being liquidated.
     *  @param  amount_     Amount of quote token used to purchase collateral.
     *  @param  collateral_ Amount of collateral purchased with quote token.
     *  @param  bondChange_ Impact of this take to the liquidation bond.
     *  @dev    amount_ / collateral_ implies the auction price.
     */
    event Take(address indexed borrower_, uint256 amount_, uint256 collateral_, int256 bondChange_);


    /*********************/
    /*** Custom Errors ***/
    /*********************/

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
     *  @notice Returns the `collateralScale` state variable.
     *  @return collateralScale_ The precision of the collateral ERC-20 token based on decimals.
     */
    function collateralScale() external view returns (uint256 collateralScale_);

    /**
     *  @notice Mapping of borrower under liquidation to {LiquidationInfo} structs.
     *  @param  borrower_  Address of the borrower.
     *  @return kickTime            Time the liquidation was initiated.
     *  @return referencePrice      Highest Price Bucket at time of liquidation.
     *  @return remainingCollateral Amount of collateral which has not yet been taken.
     *  @return remainingDebt       Amount of debt which has not been covered by the liquidation.
     */
    // TODO: Instead of just returning the struct, should also calculate and include auction price.
    // TODO: Need to implement this for NFT pool.
    function liquidations(address borrower_) external view returns (
        uint128 kickTime,
        uint128 referencePrice,
        uint256 remainingCollateral,
        uint256 remainingDebt
    );


    /*************************/
    /*** ERC20Pool Structs ***/
    /*************************/

    /**
     *  @notice Maintains the state of a liquidation.
     *  @param  kickTime            Time the liquidation was initiated.
     *  @param  referencePrice      Highest Price Bucket at time of liquidation.
     *  @param  remainingCollateral Amount of collateral which has not yet been taken.
     *  @param  remainingDebt       Amount of debt which has not been covered by the liquidation.
     */
    struct LiquidationInfo {
        uint128 kickTime;
        uint128 referencePrice;
        uint256 remainingCollateral;
        uint256 remainingDebt;
    }


    /*********************************************/
    /*** ERC20Pool Borrower External Functions ***/
    /*********************************************/

    /**
     *  @notice Called by borrowers to add collateral to the pool.
     *  @param  borrower_ The address of borrower to pledge collateral for.
     *  @param  amount_   The amount of collateral in deposit tokens to be added to the pool.
     */
    function pledgeCollateral(address borrower_, uint256 amount_) external;

    /**
     *  @notice Called by borrowers to remove an amount of collateral.
     *  @param  amount_ The amount of collateral in deposit tokens to be removed from a position.
     */
    function pullCollateral(uint256 amount_) external;

    /*****************************/
    /*** Initialize Functions ***/
    /*****************************/

    /**
     *  @notice Initializes a new pool, setting initial state variables.
     *  @param  interestRate_     Default interest rate of the pool.
     *  @param  ajnaTokenAddress_ Address of the Ajna token.
     */
    function initialize(uint256 interestRate_, address ajnaTokenAddress_) external;

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


    /*******************************/
    /*** Pool External Functions ***/
    /*******************************/

    /**
     *  @notice Called by actors to purchase collateral using quote token they provide themselves.
     *  @param  borrower_     Identifies the loan under liquidation.
     *  @param  amount_       Amount of quote token which will be used to purchase collateral at the auction price.
     *  @param  swapCalldata_ If provided, delegate call will be invoked after sending collateral to msg.sender,
     *                        such that sender will have a sufficient quote token balance prior to payment.
     */
    function take(address borrower_, uint256 amount_, bytes memory swapCalldata_) external;

}
