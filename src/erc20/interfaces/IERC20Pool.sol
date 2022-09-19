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
     *  @notice Emitted when borrower borrows quote tokens from pool.
     *  @param  borrower_ `msg.sender`.
     *  @param  lup_      LUP after borrow.
     *  @param  amount_   Amount of quote tokens borrowed from the pool.
     */
    event Borrow(address indexed borrower_, uint256 lup_, uint256 amount_);

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
     *  @notice Emitted when borrower repays quote tokens to the pool.
     *  @param  borrower_ `msg.sender`.
     *  @param  lup_      LUP after repay.
     *  @param  amount_   Amount of quote tokens repayed to the pool.
     */
    event Repay(address indexed borrower_, uint256 lup_, uint256 amount_);

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

    /**
     *  @notice Auction is not in the auction Queue.
     */
    error AuctionNotActive();

    /**
     *  @notice Auction is already in the auction Queue.
     */
    error AuctionIsActive();


    /*********************************/
    /*** ERC20Pool State Variables ***/
    /*********************************/

    /**
     *  @notice Mapping of borrower addresses to {Borrower} structs.
     *  @dev    NOTE: Cannot use appended underscore syntax for return params since struct is used.
     *  @param  borrower_  Address of the borrower.
     *  @return debt       Amount of debt that the borrower has, in quote token.
     *  @return collateral Amount of collateral that the borrower has deposited, in collateral token.
     *  @return mompFactor Momp / borrowerInflatorSnapshot factor used.
     *  @return inflator   Snapshot of inflator value used to track interest on loans.
     */
    function borrowers(address borrower_) external view returns (uint256 debt, uint256 collateral, uint256 mompFactor, uint256 inflator);

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
     *  @return bondFactor     BondFactor
     *  @return bondSize       Bond
     */
    // TODO: Instead of just returning the struct, should also calculate and include auction price.
    // TODO: Need to implement this for NFT pool.
    function liquidations(address borrower_) external view returns (
        uint128 kickTime,
        uint256 referencePrice,
        uint256 bondFactor,
        uint256 bondSize
    );

    /*************************/
    /*** ERC20Pool Structs ***/
    /*************************/

    /**
     *  @notice Struct holding borrower related info.
     *  @param  debt             Borrower debt, WAD units.
     *  @param  collateral       Collateral deposited by borrower, WAD units.
     *  @return mompFactor       Most Optimistic Matching Price (MOMP) / inflator, used in neutralPrice calc, WAD units.
     *  @param  inflatorSnapshot Current borrower inflator snapshot, WAD units.
     */
    struct Borrower {
        uint256 debt;             // [WAD]
        uint256 collateral;       // [WAD]
        uint256 mompFactor;       // [WAD]
        uint256 inflatorSnapshot; // [WAD]
    }

    /**
     *  @notice Maintains the state of a liquidation.
     *  @param  kickTime       Time the liquidation was initiated.
     *  @param  referencePrice Highest Price Bucket at time of liquidation.
     *  @param  bondFactor     Bond
     *  @param  bondSize       Bond
     */
    struct Liquidation {
        uint128 kickTime;       // [WAD]
        uint256 referencePrice; // [WAD]
        uint256 bondFactor;     // [WAD]
        uint256 bondSize;       // [WAD]
    }


    /*********************************************/
    /*** ERC20Pool Borrower External Functions ***/
    /*********************************************/

    /**
     *  @notice Called by a borrower to open or expand a position.
     *  @dev    Can only be called if quote tokens have already been added to the pool.
     *  @param  amount_     The amount of quote token to borrow.
     *  @param  limitIndex_ Lower bound of LUP change (if any) that the borrower will tolerate from a creating or modifying position.
     */
    function borrow(uint256 amount_, uint256 limitIndex_) external;

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

    /**
     *  @notice Called by a borrower to repay some amount of their borrowed quote tokens.
     *  @param  borrower_  The address of borrower to repay quote token amount for.
     *  @param  maxAmount_ WAD The maximum amount of quote token to repay.
     */
    function repay(address borrower_, uint256 maxAmount_) external;

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


    /**********************/
    /*** View Functions ***/
    /**********************/

    /**
     *  @notice Get a liquidation struct for a given address.
     *  @param  borrower_       The borrower address.
     *  @return kickTime_       accrued debt (WAD)
     *  @return referencePrice_ Borrower current debt, accrued and pending accrual (WAD)
     *  @return bondFactor_     Deposited collateral including encumbered (WAD)
     *  @return bondSize_       LUP / inflator, used in neutralPrice calc (WAD)
     */
    function liquidationInfo(address borrower_)
        external
        view
        returns (
            uint256 kickTime_,
            uint256 referencePrice_,
            uint256 bondFactor_,
            uint256 bondSize_
        );

    /**
     *  @notice Get a borrower info struct for a given address.
     *  @param  borrower_         The borrower address.
     *  @return debt_             Borrower accrued debt (WAD)
     *  @return pendingDebt_      Borrower current debt, accrued and pending accrual (WAD)
     *  @return collateral_       Deposited collateral including encumbered (WAD)
     *  @return mompFactor_        LUP / inflator, used in neutralPrice calc (WAD)
     *  @return inflatorSnapshot_ Inflator used to calculate pending interest (WAD)
     */
    function borrowerInfo(address borrower_)
        external
        view
        returns (
            uint256 debt_,
            uint256 pendingDebt_,
            uint256 collateral_,
            uint256 mompFactor_,
            uint256 inflatorSnapshot_
        );
}
