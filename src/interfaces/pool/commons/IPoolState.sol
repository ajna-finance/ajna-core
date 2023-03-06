// SPDX-License-Identifier: MIT

pragma solidity 0.8.14;

/**
 * @title Pool State
 */
interface IPoolState {

    /**
     *  @notice Returns details of an auction for a given borrower address.
     *  @param  borrower     Address of the borrower that is liquidated.
     *  @return kicker       Address of the kicker that is kicking the auction.
     *  @return bondFactor   The factor used for calculating bond size.
     *  @return bondSize     The bond amount in quote token terms.
     *  @return kickTime     Time the liquidation was initiated.
     *  @return kickPrice    Highest Price Bucket at time of liquidation.
     *  @return neutralPrice Neutral Price of auction.
     *  @return head         Address of the head auction.
     *  @return next         Address of the next auction in queue.
     *  @return prev         Address of the prev auction in queue.
     *  @return alreadyTaken True if take has been called on auction
     */
    function auctionInfo(address borrower)
        external
        view
        returns (
            address kicker,
            uint256 bondFactor,
            uint256 bondSize,
            uint256 kickTime,
            uint256 kickPrice,
            uint256 neutralPrice,
            address head,
            address next,
            address prev,
            bool alreadyTaken
        );

    /**
     *  @notice Returns pool related debt values.
     *  @return debt_            Current amount of debt owed by borrowers in pool.
     *  @return accruedDebt_     Debt owed by borrowers based on last inflator snapshot.
     *  @return debtInAuction_   Total amount of debt in auction.
     */
    function debtInfo() external view returns (uint256 debt_, uint256 accruedDebt_, uint256 debtInAuction_);

    /**
     *  @notice Mapping of borrower addresses to {Borrower} structs.
     *  @dev    NOTE: Cannot use appended underscore syntax for return params since struct is used.
     *  @param  borrower   Address of the borrower.
     *  @return t0Debt     Amount of debt borrower would have had if their loan was the first debt drawn from the pool
     *  @return collateral Amount of collateral that the borrower has deposited, in collateral token.
     *  @return t0Np       Np / borrowerInflatorSnapshot
     */
    function borrowerInfo(address borrower)
        external
        view
        returns (
            uint256 t0Debt,
            uint256 collateral,
            uint256 t0Np
        );

    /**
     *  @notice Mapping of buckets indexes to {Bucket} structs.
     *  @dev    NOTE: Cannot use appended underscore syntax for return params since struct is used.
     *  @param  index               Bucket index.
     *  @return lpAccumulator       Amount of LPs accumulated in current bucket.
     *  @return availableCollateral Amount of collateral available in current bucket.
     *  @return bankruptcyTime      Timestamp when bucket become insolvent, 0 if healthy.
     *  @return bucketDeposit       Amount of quote tokens in bucket.
     *  @return bucketScale         Bucket multiplier.
     */
    function bucketInfo(uint256 index)
        external
        view
        returns (
            uint256 lpAccumulator,
            uint256 availableCollateral,
            uint256 bankruptcyTime,
            uint256 bucketDeposit,
            uint256 bucketScale
        );

    /**
     *  @notice Mapping of burnEventEpoch to {BurnEvent} structs.
     *  @dev    Reserve auctions correspond to burn events.
     *  @param  burnEventEpoch_  Id of the current reserve auction.
     *  @return burnBlock        Block in which a reserve auction started.
     *  @return totalInterest    Total interest as of the reserve auction.
     *  @return totalBurned      Total ajna tokens burned as of the reserve auction.
     */
    function burnInfo(uint256 burnEventEpoch_) external view returns (uint256, uint256, uint256);

    /**
     *  @notice Returns the latest burnEventEpoch of reserve auctions.
     *  @dev    If a reserve auction is active, it refers to the current reserve auction. If no reserve auction is active, it refers to the last reserve auction.
     *  @return burnEventEpoch Current burnEventEpoch.
     */
    function currentBurnEpoch() external view returns (uint256);

    /**
     *  @notice Returns information about the pool EMA (Exponential Moving Average) variables.
     *  @return debtColEma   Debt squared to collateral Exponential, numerator to TU calculation
     *  @return lupt0DebtEma Exponential of LUP * t0 debt, denominator to TU calculation
     *  @return debtEma      Exponential debt moving average.
     *  @return depositEma   sample of meaningful deposit Exponential, denominator to MAU calculation.
     */
    function emasInfo()
        external
        view
        returns (
            uint256 debtColEma,
            uint256 lupt0DebtEma,
            uint256 debtEma,
            uint256 depositEma
    );

    /**
     *  @notice Returns information about pool inflator.
     *  @return inflatorSnapshot A snapshot of the last inflator value.
     *  @return lastUpdate       The timestamp of the last `inflatorSnapshot` update.
     */
    function inflatorInfo()
        external
        view
        returns (
            uint256 inflatorSnapshot,
            uint256 lastUpdate
    );

    /**
     *  @notice Returns information about pool interest rate.
     *  @return interestRate       Current interest rate in pool.
     *  @return interestRateUpdate The timestamp of the last interest rate update.
     */
    function interestRateInfo()
        external
        view
        returns (
            uint256 interestRate,
            uint256 interestRateUpdate
        );


    /**
     *  @notice Returns details about kicker balances.
     *  @param  kicker    The address of the kicker to retrieved info for.
     *  @return claimable Amount of quote token kicker can claim / withdraw from pool at any time.
     *  @return locked    Amount of quote token kicker locked in auctions (as bonds).
     */
    function kickerInfo(address kicker)
        external
        view
        returns (
            uint256 claimable,
            uint256 locked
        );

    /**
     *  @notice Mapping of buckets indexes and owner addresses to {Lender} structs.
     *  @param  index            Bucket index.
     *  @param  lp               Address of the liquidity provider.
     *  @return lpBalance        Amount of LPs owner has in current bucket.
     *  @return lastQuoteDeposit Time the user last deposited quote token.
     */
    function lenderInfo(
        uint256 index,
        address lp
    )
        external
        view
        returns (
            uint256 lpBalance,
            uint256 lastQuoteDeposit
    );

    /**
     *  @notice Return the LPB allowance a LP owner provided to a spender.
     *  @param  index   Bucket index.
     *  @param  spender Address of the LPB spender.
     *  @param  owner   The initial owner of the LPs.
     *  @return allowance_ Amount of LPs spender can utilize.
     */
    function lpAllowance(
        uint256 index,
        address spender,
        address owner
    ) external view returns (uint256 allowance_);

    /**
     *  @notice Returns information about a loan in the pool.
     *  @param  loanId Loan's id within loan heap. Max loan is position 1.
     *  @return borrower       Borrower address at the given position.
     *  @return thresholdPrice Borrower threshold price in pool.
     */
    function loanInfo(
        uint256 loanId
    )
        external
        view
        returns (
            address borrower,
            uint256 thresholdPrice
    );

    /**
     *  @notice Returns information about pool loans.
     *  @return maxBorrower       Borrower address with highest threshold price.
     *  @return maxThresholdPrice Highest threshold price in pool.
     *  @return noOfLoans         Total number of loans.
     */
    function loansInfo()
        external
        view
        returns (
            address maxBorrower,
            uint256 maxThresholdPrice,
            uint256 noOfLoans
    );

    /**
     *  @notice Returns information about pool reserves.
     *  @return liquidationBondEscrowed Amount of liquidation bond across all liquidators.
     *  @return reserveAuctionUnclaimed Amount of claimable reserves which has not been taken in the Claimable Reserve Auction.
     *  @return reserveAuctionKicked    Time a Claimable Reserve Auction was last kicked.
     *  @return totalInterestEarned     Total interest earned by all lenders in the pool
     */
    function reservesInfo()
        external
        view
        returns (
            uint256 liquidationBondEscrowed,
            uint256 reserveAuctionUnclaimed,
            uint256 reserveAuctionKicked,
            uint256 totalInterestEarned
    );

    /**
     *  @notice Returns the `pledgedCollateral` state variable.
     *  @return The total pledged collateral in the system, in WAD units.
     */
    function pledgedCollateral() external view returns (uint256);

    /**
     *  @notice Returns the total number of active auctions in pool
     *  @return totalAuctions_ number of active auctions.
     */
    function totalAuctionsInPool() external view returns (uint256);

     /**
     *  @notice Returns the `t0Debt` state variable.
     *  @dev    This value should be multiplied by inflator in order to calculate current debt of the pool.
     *  @return The total t0Debt in the system, in WAD units.
     */
    function totalT0Debt() external view returns (uint256);

    /**
     *  @notice Returns the `t0DebtInAuction` state variable.
     *  @dev    This value should be multiplied by inflator in order to calculate current debt in auction of the pool.
     *  @return The total t0DebtInAuction in the system, in WAD units.
     */
    function totalT0DebtInAuction() external view returns (uint256);

    /**
     *  @notice Mapping of addresses that can transfer LPs to a given lender.
     *  @param  lender     Lender that receives LPs.
     *  @param  transferor Transferor that transfers LPs.
     *  @return True if the transferor is approved by lender.
     */
    function approvedTransferors(
        address lender,
        address transferor
    ) external view returns (bool);

}

/*********************/
/*** State Structs ***/
/*********************/

/*** Pool State ***/

struct InflatorState {
    uint208 inflator;       // [WAD] pool's inflator
    uint48  inflatorUpdate; // [SEC] last time pool's inflator was updated
}

struct InterestState {
    uint208 interestRate;        // [WAD] pool's interest rate
    uint48  interestRateUpdate;  // [SEC] last time pool's interest rate was updated (not before 12 hours passed)
    uint256 debt;                // [WAD] previous update's debt
    uint256 meaningfulDeposit;   // [WAD] previous update's meaningfulDeposit
    uint256 t0Debt2ToCollateral; // [WAD] utilization weight accumulator, tracks debt and collateral relationship accross borrowers 
    uint256 debtCol;             // [WAD] previous debt squared to collateral
    uint256 lupt0Debt;           // [WAD] previous LUP * t0 debt
}

struct EmaState {
    uint256 debtEma;             // [WAD] sample of debt EMA, numerator to MAU calculation
    uint256 depositEma;          // [WAD] sample of meaningful deposit EMA, denominator to MAU calculation
    uint256 debtColEma;          // [WAD] debt squared to collateral EMA, numerator to TU calculation
    uint256 lupt0DebtEma;        // [WAD] EMA of LUP * t0 debt, denominator to TU calculation
    uint256 emaUpdate;           // [SEC] last time pool's EMAs were updated
}

struct PoolBalancesState {
    uint256 pledgedCollateral; // [WAD] total collateral pledged in pool
    uint256 t0DebtInAuction;   // [WAD] Total debt in auction used to restrict LPB holder from withdrawing
    uint256 t0Debt;            // [WAD] Pool debt as if the whole amount was incurred upon the first loan
}

struct PoolState {
    uint8   poolType;             // pool type, can be ERC20 or ERC721
    uint256 t0Debt;               // [WAD] t0 debt in pool
    uint256 debt;                 // [WAD] total debt in pool, accrued in current block
    uint256 collateral;           // [WAD] total collateral pledged in pool
    uint256 inflator;             // [WAD] current pool inflator
    bool    isNewInterestAccrued; // true if new interest already accrued in current block
    uint256 rate;                 // [WAD] pool's current interest rate
    uint256 quoteDustLimit;       // [WAD] quote token dust limit of the pool
}

/*** Buckets State ***/

struct Lender {
    uint256 lps;         // [WAD] Lender LP accumulator
    uint256 depositTime; // timestamp of last deposit
}

struct Bucket {
    uint256 lps;                        // [WAD] Bucket LP accumulator
    uint256 collateral;                 // [WAD] Available collateral tokens deposited in the bucket
    uint256 bankruptcyTime;             // Timestamp when bucket become insolvent, 0 if healthy
    mapping(address => Lender) lenders; // lender address to Lender struct mapping
}

/*** Deposits State ***/

struct DepositsState {
    uint256[8193] values;  // Array of values in the FenwickTree.
    uint256[8193] scaling; // Array of values which scale (multiply) the FenwickTree accross indexes.
}

/*** Loans State ***/

struct LoansState {
    Loan[] loans;
    mapping (address => uint)     indices;   // borrower address => loan index mapping
    mapping (address => Borrower) borrowers; // borrower address => Borrower struct mapping
}

struct Loan {
    address borrower;       // borrower address
    uint96  thresholdPrice; // [WAD] Loan's threshold price.
}

struct Borrower {
    uint256 t0Debt;     // [WAD] Borrower debt time-adjusted as if it was incurred upon first loan of pool.
    uint256 collateral; // [WAD] Collateral deposited by borrower.
    uint256 t0Np;       // [WAD] Neutral Price time-adjusted as if it was incurred upon first loan of pool.
}

/*** Auctions State ***/

struct AuctionsState {
    uint96  noOfAuctions;                         // total number of auctions in pool
    address head;                                 // first address in auction queue
    address tail;                                 // last address in auction queue
    uint256 totalBondEscrowed;                    // [WAD] total amount of quote token posted as auction kick bonds
    mapping(address => Liquidation) liquidations; // mapping of borrower address and auction details
    mapping(address => Kicker)      kickers;      // mapping of kicker address and kicker balances
}

struct Liquidation {
    address kicker;       // address that initiated liquidation
    uint96  bondFactor;   // [WAD] bond factor used to start liquidation
    uint96  kickTime;     // timestamp when liquidation was started
    address prev;         // previous liquidated borrower in auctions queue
    uint96  kickMomp;     // [WAD] Momp when liquidation was started
    address next;         // next liquidated borrower in auctions queue
    uint160 bondSize;     // [WAD] liquidation bond size
    uint96  neutralPrice; // [WAD] Neutral Price when liquidation was started
    bool    alreadyTaken; // true if take has been called on auction
}

struct Kicker {
    uint256 claimable; // [WAD] kicker's claimable balance
    uint256 locked;    // [WAD] kicker's balance of tokens locked in auction bonds
}

/*** Reserve Auction State ***/

struct ReserveAuctionState {
    uint256 kicked;                            // Time a Claimable Reserve Auction was last kicked.
    uint256 unclaimed;                         // [WAD] Amount of claimable reserves which has not been taken in the Claimable Reserve Auction.
    uint256 latestBurnEventEpoch;              // Latest burn event epoch.
    uint256 totalAjnaBurned;                   // [WAD] Total ajna burned in the pool.
    uint256 totalInterestEarned;               // [WAD] Total interest earned by all lenders in the pool.
    mapping (uint256 => BurnEvent) burnEvents; // Mapping burnEventEpoch => BurnEvent.
}

struct BurnEvent {
    uint256 timestamp;     // time at which the burn event occured
    uint256 totalInterest; // [WAD] current pool interest accumulator `PoolCommons.accrueInterest().newInterest`
    uint256 totalBurned;   // [WAD] burn amount accumulator
}