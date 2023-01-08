// SPDX-License-Identifier: MIT

pragma solidity 0.8.14;

/**
 * @title Pool Events
 */
interface IPoolEvents {
    /**
     *  @notice Emitted when lender adds quote token to the pool.
     *  @param  lender    Recipient that added quote tokens.
     *  @param  price     Price at which quote tokens were added.
     *  @param  amount    Amount of quote tokens added to the pool.
     *  @param  lpAwarded Amount of LP awarded for the deposit. 
     *  @param  lup       LUP calculated after deposit.
     */
    event AddQuoteToken(
        address indexed lender,
        uint256 indexed price,
        uint256 amount,
        uint256 lpAwarded,
        uint256 lup
    );

    /**
     *  @notice Emitted when auction is completed.
     *  @param  borrower   Address of borrower that exits auction.
     *  @param  collateral Borrower's remaining collateral when auction completed.
     */
    event AuctionSettle(
        address indexed borrower,
        uint256 collateral
    );

    /**
     *  @notice Emitted when NFT auction is completed.
     *  @param  borrower   Address of borrower that exits auction.
     *  @param  collateral Borrower's remaining collateral when auction completed.
     *  @param  lps        Amount of LPs given to the borrower to compensate fractional collateral (if any).
     *  @param  index      Index of the bucket with LPs to compensate fractional collateral.
     */
    event AuctionNFTSettle(
        address indexed borrower,
        uint256 collateral,
        uint256 lps,
        uint256 index
    );

    /**
     *  @notice Emitted when LPs are forfeited as a result of the bucket losing all assets.
     *  @param  index       The index of the bucket.
     *  @param  lpForfeited Amount of LP forfeited by lenders.
     */
    event BucketBankruptcy(
        uint256 indexed index,
        uint256 lpForfeited
    );

    /**
     *  @notice Emitted when an actor uses quote token to arb higher-priced deposit off the book.
     *  @param  borrower    Identifies the loan being liquidated.
     *  @param  index       The index of the Highest Price Bucket used for this take.
     *  @param  amount      Amount of quote token used to purchase collateral.
     *  @param  collateral  Amount of collateral purchased with quote token.
     *  @param  bondChange  Impact of this take to the liquidation bond.
     *  @param  isReward    True if kicker was rewarded with `bondChange` amount, false if kicker was penalized.
     *  @dev    amount / collateral implies the auction price.
     */
    event BucketTake(
        address indexed borrower,
        uint256 index,
        uint256 amount,
        uint256 collateral,
        uint256 bondChange,
        bool    isReward
    );

    /**
     *  @notice Emitted when LPs are awarded to a taker or kicker in a bucket take.
     *  @param  taker           Actor who invoked the bucket take.
     *  @param  kicker          Actor who started the auction.
     *  @param  lpAwardedTaker  Amount of LP awarded to the taker.
     *  @param  lpAwardedKicker Amount of LP awarded to the actor who started the auction.
     */
    event BucketTakeLPAwarded(
        address indexed taker,
        address indexed kicker,
        uint256 lpAwardedTaker,
        uint256 lpAwardedKicker
    );

    /**
     *  @notice Emitted when an actor settles debt in a completed liquidation
     *  @param  borrower   Identifies the loan under liquidation.
     *  @param  settledDebt Amount of pool debt settled in this transaction.
     *  @dev    When amountRemaining_ == 0, the auction has been completed cleared and removed from the queue.
     */
    event Settle(
        address indexed borrower,
        uint256 settledDebt
    );

    /**
     *  @notice Emitted when a liquidation is initiated.
     *  @param  borrower   Identifies the loan being liquidated.
     *  @param  debt       Debt the liquidation will attempt to cover.
     *  @param  collateral Amount of collateral up for liquidation.
     *  @param  bond       Bond amount locked by kicker
     */
    event Kick(
        address indexed borrower,
        uint256 debt,
        uint256 collateral,
        uint256 bond
    );

    /**
     *  @notice Emitted when lender moves quote token from a bucket price to another.
     *  @param  lender         Recipient that moved quote tokens.
     *  @param  from           Price bucket from which quote tokens were moved.
     *  @param  to             Price bucket where quote tokens were moved.
     *  @param  amount         Amount of quote tokens moved.
     *  @param  lpRedeemedFrom Amount of LP removed from the `from` bucket.
     *  @param  lpAwardedTo    Amount of LP credited to the `to` bucket.
     *  @param  lup            LUP calculated after removal.
     */
    event MoveQuoteToken(
        address indexed lender,
        uint256 indexed from,
        uint256 indexed to,
        uint256 amount,
        uint256 lpRedeemedFrom,
        uint256 lpAwardedTo,
        uint256 lup
    );

    /**
     *  @notice Emitted when lender claims collateral from a bucket.
     *  @param  claimer    Recipient that claimed collateral.
     *  @param  price      Price at which collateral was claimed.
     *  @param  amount     The amount of collateral (or number of NFT tokens) transferred to the claimer.
     *  @param  lpRedeemed Amount of LP exchanged for quote token.
     */
    event RemoveCollateral(
        address indexed claimer,
        uint256 indexed price,
        uint256 amount,
        uint256 lpRedeemed
    );

    /**
     *  @notice Emitted when lender removes quote token from the pool.
     *  @param  lender     Recipient that removed quote tokens.
     *  @param  price      Price at which quote tokens were removed.
     *  @param  amount     Amount of quote tokens removed from the pool.
     *  @param  lpRedeemed Amount of LP exchanged for quote token.
     *  @param  lup        LUP calculated after removal.
     */
    event RemoveQuoteToken(
        address indexed lender,
        uint256 indexed price,
        uint256 amount,
        uint256 lpRedeemed,
        uint256 lup
    );

    /**
     *  @notice Emitted when borrower repays quote tokens to the pool, and/or pulls collateral from the pool.
     *  @param  borrower         `msg.sender` or on behalf of sender.
     *  @param  quoteRepaid      Amount of quote tokens repaid to the pool.
     *  @param  collateralPulled The amount of collateral (or number of NFT tokens) transferred to the claimer.
     *  @param  lup              LUP after repay.
     */
    event RepayDebt(
        address indexed borrower,
        uint256 quoteRepaid,
        uint256 collateralPulled,
        uint256 lup
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