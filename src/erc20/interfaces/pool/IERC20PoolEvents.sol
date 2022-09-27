// SPDX-License-Identifier: MIT
pragma solidity 0.8.14;

/**
 * @title ERC20 Pool Events
 */
interface IERC20PoolEvents {

    /**
     *  @notice Emitted when actor adds unencumbered collateral to a bucket.
     *  @param  actor  Recipient that added collateral.
     *  @param  price  Price at which collateral were added.
     *  @param  amount Amount of collateral added to the pool.
     */
    event AddCollateral(
        address indexed actor,
        uint256 indexed price,
        uint256 amount
    );

    /**
     *  @notice Emitted when an actor settles debt in a completed liquidation
     *  @param  borrower           Identifies the loan under liquidation.
     *  @param  hpbIndex           The index of the Highest Price Bucket where debt was cleared.
     *  @param  amount             Amount of debt cleared from the HPB in this transaction.
     *  @param  collateralReturned Amount of collateral returned to the borrower in this transaction.
     *  @param  amountRemaining    Amount of debt which still needs to be cleared.
     *  @dev    When amountRemaining_ == 0, the auction has been completed cleared and removed from the queue.
     */
    event Clear(
        address indexed borrower,
        uint256 hpbIndex,
        uint256 amount,
        uint256 collateralReturned,
        uint256 amountRemaining);

    /**
     *  @notice Emitted when lender moves collateral from a bucket price to another.
     *  @param  lender Recipient that moved collateral.
     *  @param  from   Price bucket from which collateral was moved.
     *  @param  to     Price bucket where collateral was moved.
     *  @param  amount Amount of collateral moved.
     */
    event MoveCollateral(
        address indexed lender,
        uint256 indexed from,
        uint256 indexed to,
        uint256 amount
    );

    /**
     *  @notice Emitted when borrower locks collateral in the pool.
     *  @param  borrower `msg.sender`.
     *  @param  amount   Amount of collateral locked in the pool.
     */
    event PledgeCollateral(
        address indexed borrower,
        uint256 amount
    );

    /**
     *  @notice Emitted when borrower removes pledged collateral from the pool.
     *  @param  borrower `msg.sender`.
     *  @param  amount   Amount of collateral removed from the pool.
     */
    event PullCollateral(
        address indexed borrower,
        uint256 amount
    );

    /**
     *  @notice Emitted when lender claims unencumbered collateral.
     *  @param  claimer Recipient that claimed collateral.
     *  @param  price   Price at which unencumbered collateral was claimed.
     *  @param  amount  The amount of collateral transferred to the claimer.
     */
    event RemoveCollateral(
        address indexed claimer,
        uint256 indexed price,
        uint256 amount
    );

    /**
     *  @notice Emitted when an actor uses quote token outside of the book to purchase collateral under liquidation.
     *  @param  borrower   Identifies the loan being liquidated.
     *  @param  amount     Amount of quote token used to purchase collateral.
     *  @param  collateral Amount of collateral purchased with quote token.
     *  @param  bondChange Impact of this take to the liquidation bond.
     *  @dev    amount / collateral implies the auction price.
     */
    event Take(
        address indexed borrower,
        uint256 amount,
        uint256 collateral,
        int256 bondChange
    );
}