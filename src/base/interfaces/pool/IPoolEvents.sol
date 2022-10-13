// SPDX-License-Identifier: MIT

pragma solidity 0.8.14;

/**
 * @title Pool Events
 */
interface IPoolEvents {
    /**
     *  @notice Emitted when lender adds quote token to the pool.
     *  @param  lender Recipient that added quote tokens.
     *  @param  price  Price at which quote tokens were added.
     *  @param  amount Amount of quote tokens added to the pool.
     *  @param  lup    LUP calculated after deposit.
     */
    event AddQuoteToken(
        address indexed lender,
        uint256 indexed price,
        uint256 amount,
        uint256 lup
    );

    /**
     *  @notice Emitted when an actor uses quote token to arb higher-priced deposit off the book.
     *  @param  borrower   Identifies the loan being liquidated.
     *  @param  index      The index of the Highest Price Bucket used for this take.
     *  @param  amount     Amount of quote token used to purchase collateral.
     *  @param  collateral Amount of collateral purchased with quote token.
     *  @param  bondChange Impact of this take to the liquidation bond.
     *  @dev    amount / collateral implies the auction price.
     */
    event ArbTake(
        address indexed borrower,
        uint256 index,
        uint256 amount,
        uint256 collateral,
        int256 bondChange
    );

    /**
     *  @notice Emitted when borrower borrows quote tokens from pool.
     *  @param  borrower `msg.sender`.
     *  @param  lup      LUP after borrow.
     *  @param  amount   Amount of quote tokens borrowed from the pool.
     */
    event Borrow(
        address indexed borrower,
        uint256 lup,
        uint256 amount
    );

    /**
     *  @notice Emitted when an actor uses quote token outside of the book to purchase collateral under liquidation.
     *  @param  borrower   Identifies the loan being liquidated.
     *  @param  index      Index of the price bucket from which quote token was exchanged for collateral.
     *  @param  amount     Amount of quote token taken from the bucket to purchase collateral.
     *  @param  collateral Amount of collateral purchased with quote token.
     *  @param  bondChange Impact of this take to the liquidation bond.
     *  @dev    amount / collateral implies the auction price.
     */
    event DepositTake(
        address indexed borrower,
        uint256 index,
        uint256 amount,
        uint256 collateral,
        int256 bondChange
    );

    /**
     *  @notice Emitted when a liquidation is initiated.
     *  @param  borrower   Identifies the loan being liquidated.
     *  @param  debt       Debt the liquidation will attempt to cover.
     *  @param  collateral Amount of collateral up for liquidation.
     */
    event Kick(
        address indexed borrower,
        uint256 debt,
        uint256 collateral
    );

    /**
     *  @notice Emitted when lender moves quote token from a bucket price to another.
     *  @param  lender Recipient that moved quote tokens.
     *  @param  from   Price bucket from which quote tokens were moved.
     *  @param  to     Price bucket where quote tokens were moved.
     *  @param  amount Amount of quote tokens moved.
     *  @param  lup    LUP calculated after removal.
     */
    event MoveQuoteToken(
        address indexed lender,
        uint256 indexed from,
        uint256 indexed to,
        uint256 amount,
        uint256 lup
    );

    /**
     *  @notice Emitted when lender removes quote token from the pool.
     *  @param  lender Recipient that removed quote tokens.
     *  @param  price  Price at which quote tokens were removed.
     *  @param  amount Amount of quote tokens removed from the pool.
     *  @param  lup    LUP calculated after removal.
     */
    event RemoveQuoteToken(
        address indexed lender,
        uint256 indexed price,
        uint256 amount,
        uint256 lup
    );

    /**
     *  @notice Emitted when borrower repays quote tokens to the pool.
     *  @param  borrower `msg.sender` or on behalf of sender.
     *  @param  lup      LUP after repay.
     *  @param  amount   Amount of quote tokens repayed to the pool.
     */
    event Repay(
        address indexed borrower,
        uint256 lup,
        uint256 amount
    );

    /**
     *  @notice Emitted when a Claimaible Reserve Auction is started or taken.
     *  @return claimableReservesRemaining Amount of claimable reserves which has not yet been taken.
     *  @return auctionPrice               Current price at which 1 quote token may be purchased, denominated in Ajna.
     */
    event ReserveAuction(
        uint256 claimableReservesRemaining,
        uint256 auctionPrice
    );

    /**
     *  @notice Emitted when an actor uses quote token outside of the book to purchase collateral under liquidation.
     *  @param  borrower   Identifies the loan being liquidated.
     *  @param  amount     Amount of quote token used to purchase collateral.
     *  @param  collateral Amount of collateral purchased with quote token (ERC20 pool) or number of NFTs purchased (ERC721 pool).
     *  @param  bondChange Impact of this take to the liquidation bond.
     *  @param  isReward   True if kicker was rewarded with `bondChange` amount, false if kicker was penalized.
     *  @dev    amount / collateral implies the auction price.
     */
    event Take(
        address indexed borrower,
        uint256 amount,
        uint256 collateral,
        uint256 bondChange,
        bool    isReward
    );

    /**
     *  @notice Emitted when a lender transfers their LP tokens to a different address.
     *  @dev    Used by PositionManager.memorializePositions().
     *  @param  owner    The original owner address of the position.
     *  @param  newOwner The new owner address of the position.
     *  @param  indexes  Array of price bucket indexes at which LP tokens were transferred.
     *  @param  lpTokens Amount of LP tokens transferred.
     */
    event TransferLPTokens(
        address owner,
        address newOwner,
        uint256[] indexes,
        uint256 lpTokens
    );

    /**
     *  @notice Emitted when pool interest rate is updated.
     *  @param  oldRate Old pool interest rate.
     *  @param  newRate New pool interest rate.
     */
    event UpdateInterestRate(
        uint256 oldRate,
        uint256 newRate
    );
}