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

    /**
     *  @notice Emitted when a lender transfers their LP tokens to a different address.
     *  @dev    Used by PositionManager.memorializePositions().
     *  @param  owner_    The original owner address of the position.
     *  @param  newOwner_ The new owner address of the position.
     *  @param  prices_    Array of price buckets at which LP tokens were moved.
     *  @param  lpTokens_ Amount of LP tokens transferred.
     */
    event TransferLPTokens(address owner_, address newOwner_, uint256[] prices_, uint256 lpTokens_);

    /**
     *  @notice Emitted when pool interest rate is updated.
     *  @param  oldRate_ Old pool interest rate.
     *  @param  newRate_ New pool interest rate.
     */
    event UpdateInterestRate(uint256 oldRate_, uint256 newRate_);

    /***********************/
    /*** State Variables ***/
    /***********************/

    /**
     *  @notice Returns the `hpb` state variable.
     *  @return hpb_ The price value of the current Highest Price Bucket (HPB), in WAD units.
     */
    function hpb() external view returns (uint256 hpb_);

    /**
     *  @notice Returns the `inflatorSnapshot` state variable.
     *  @return inflatorSnapshot_ A snapshot of the last inflator value, in RAY units.
     */
    function inflatorSnapshot() external view returns (uint256 inflatorSnapshot_);

    /**
     *  @notice Returns the `interestRate` state variable.
     *  @return interestRate_ TODO
     */
    function interestRate() external view returns (uint256 interestRate_);

    /**
     *  @notice Returns the `interestRateUpdate` state variable.
     *  @return interestRateUpdate_ The timestamp of the last rate update.
     */
    function interestRateUpdate() external view returns (uint256 interestRateUpdate_);

    /**
     *  @notice Returns the `lastInflatorSnapshotUpdate` state variable.
     *  @return lastInflatorSnapshotUpdate_ The timestamp of the last `inflatorSnapshot` update.
     */
    function lastInflatorSnapshotUpdate() external view returns (uint256 lastInflatorSnapshotUpdate_);

    /**
     *  @notice Returns the `lup` state variable.
     *  @return lup_ The price value of the current Lowest Utilized Price (LUP) bucket, in WAD units.
     */
    function lup() external view returns (uint256 lup_);

    /**
     *  @notice Nested mapping of lender's LP token balance at different price buckets.
     *  @param  lp_          Address of the LP.
     *  @param  priceBucket_ Price of the bucket.
     *  @return balance_     LP token balance of the lender at the queried price bucket.
     */
    function lpBalance(address lp_, uint256 priceBucket_) external view returns (uint256 balance_);

    /**
     *  @notice Returns the `minFee` state variable.
     *  @return minFee_ TODO
     */
    function minFee() external view returns (uint256 minFee_);

    /**
     *  @notice Returns the `pdAccumulator` state variable.
     *  @return pdAccumulator_ The sum of all available deposits * price, in WAD units.
     */
    function pdAccumulator() external view returns (uint256 pdAccumulator_);

    /**
     *  @notice Returns the `quoteTokenScale` state variable.
     *  @return quoteTokenScale_ The precision of the quote ERC-20 token based on decimals.
     */
    function quoteTokenScale() external view returns (uint256 quoteTokenScale_);

    /**
     *  @notice Returns the `totalCollateral` state variable.
     *  @return totalCollateral_ THe total amount of collateral in the system, in WAD units.
     */
    function totalCollateral() external view returns (uint256 totalCollateral_);

    /**
     *  @notice Returns the `totalQuoteToken` state variable.
     *  @return totalQuoteToken_ The total amount of quote token in the system, in WAD units.
     */
    function totalQuoteToken() external view returns (uint256 totalQuoteToken_);

    /***************/
    /*** Structs ***/
    /***************/

    /**
     *  @notice struct tracking the owner of a given position
     *  @dev    Used to provide access control for the transferLPTokens method
     *  @param owner           Address of the current LP token owner
     *  @param allowedNewOwner Address of the newly allowed LP token owner
     */
    struct LpTokenOwnership {
        address owner;
        address allowedNewOwner;
    }

    /**
     *  @notice struct holding bucket info
     *  @param price            Current bucket price, WAD
     *  @param up               Upper utilizable bucket price, WAD
     *  @param down             Next utilizable bucket price, WAD
     *  @param onDeposit        Quote token on deposit in bucket, WAD
     *  @param debt             Accumulated bucket debt, WAD
     *  @param inflatorSnapshot Bucket inflator snapshot, RAY
     *  @param lpOutstanding    Outstanding Liquidity Provider LP tokens in a bucket, RAY
     *  @param collateral       Current collateral tokens deposited in the bucket, RAY
     */
    struct Bucket {
        uint256 price;
        uint256 up;
        uint256 down;
        uint256 onDeposit;
        uint256 debt;
        uint256 inflatorSnapshot;
        uint256 lpOutstanding;
        uint256 collateral;
    }

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
     *  @param  amount_    The amount of quote token to be added by a lender.
     *  @param  price_     The bucket to which the quote tokens will be added.
     *  @return lpTokens_  The amount of LP Tokens received for the added quote tokens.
     */
    function addQuoteToken(uint256 amount_, uint256 price_) external returns (uint256 lpTokens_);

    /**
     *  @notice Called by lenders to approve a new owner of their LP tokens.
     *  @dev    Intended for use by the PositionManager contract.
     *  @param  owner_           The existing owner of the LP tokens.
     *  @param  allowedNewOwner_ The new owner of the LP tokens.
     */
    function approveNewPositionOwner(address owner_, address allowedNewOwner_) external;

    /**
     *  @notice Called by lenders to move an amount of credit from a specified price bucket to another specified price bucket.
     *  @param  maxAmount_ The maximum amount of quote token to be moved by a lender.
     *  @param  fromPrice_ The bucket from which the quote tokens will be removed.
     *  @param  toPrice_   The bucket to which the quote tokens will be added.
     */
    function moveQuoteToken(uint256 maxAmount_, uint256 fromPrice_, uint256 toPrice_) external;

    /**
     *  @notice Called by lenders to remove an amount of credit at a specified price bucket.
     *  @param  price_     The bucket from which quote tokens will be removed.
     *  @param  lpTokens_  The amount of LP tokens to be removed by a lender.
     *  @return amount     The amount of quote tokens actually removed by the lender.
     *  @return lpTokens     The amount of quote LP tokens actually removed by the lender.
     */
    function removeQuoteToken(uint256 price_, uint256 lpTokens_) external returns (uint256 amount, uint256 lpTokens);

    /**
     *  @notice Called by lenders to transfers their LP tokens to a different address.
     *  @dev    Used by PositionManager.memorializePositions().
     *  @param  owner_    The original owner address of the position.
     *  @param  newOwner_ The new owner address of the position.
     *  @param  prices_   Array of price buckets at which LP tokens were moved.
     */
    function transferLPTokens(address owner_, address newOwner_, uint256[] calldata prices_) external;

    /*******************************/
    /*** Pool External Functions ***/
    /*******************************/

    /**
     *  @notice Liquidates a given borrower's position.
     *  @param  borrower_ The address of the borrower being liquidated.
     */
    function liquidate(address borrower_) external;

    /**********************/
    /*** View Functions ***/
    /**********************/

    /**
     *  @notice Get the BIP credit for a given price.
     *  @param  price_     The price of the bucket to retrieve BIP credit for.
     *  @return bipCredit_ BIP credit of the bucket.
     */
    function bipAt(uint256 price_) external view returns (uint256 bipCredit_);

    /**
     *  @notice Get a bucket struct for a given price.
     *  @param  price_            The price of the bucket to retrieve.
     *  @return bucketPrice_      The price of the bucket.
     *  @return up_               The price of the next higher priced utlized bucket.
     *  @return down_             The price of the next lower price utilized bucket.
     *  @return onDeposit_        The amount of quote token available as liquidity in the bucket.
     *  @return debt_             The amount of quote token debt in the bucket.
     *  @return bucketInflator_   The inflator snapshot value in the bucket.
     *  @return lpOutstanding_    The amount of outstanding LP tokens in the bucket.
     *  @return bucketCollateral_ The amount of collateral posted in the bucket.
     */
    function bucketAt(uint256 price_)
        external
        view
        returns (
            uint256 bucketPrice_,
            uint256 up_,
            uint256 down_,
            uint256 onDeposit_,
            uint256 debt_,
            uint256 bucketInflator_,
            uint256 lpOutstanding_,
            uint256 bucketCollateral_
        );

    /**
     *  @notice Returns the total encumbered collateral resulting from a given amount of debt.
     *  @dev    Used for both pool and borrower level debt.
     *  @param  debt_        Amount of debt for corresponding collateral encumbrance.
     *  @return encumbrance_ The current encumbrance of a given debt balance, in WAD units.
     */
    function getEncumberedCollateral(uint256 debt_) external view returns (uint256 encumbrance_);

    /**
     *  @notice Returns the current Highest Price Bucket (HPB).
     *  @dev    Starting at the current HPB, iterate through down pointers until a new HPB found.
     *  @dev    HPB should have at on deposit or debt different than 0.
     *  @return newHpb_ The current Highest Price Bucket (HPB).
     */
    function getHpb() external view returns (uint256 newHpb_);

    /**
     *  @notice Returns the current Highest Utilizable Price (HUP) bucket.
     *  @dev    Starting at the LUP, iterate through down pointers until no quote tokens are available.
     *  @dev    LUP should always be >= HUP.
     *  @return hup_ The current Highest Utilizable Price (HUP) bucket.
     */
    function getHup() external view returns (uint256 hup_);

    /**
     *  @notice Calculate the amount of collateral and quote tokens for a given amount of LP Tokens.
     *  @param  lpTokens_         The number of lpTokens to calculate amounts for.
     *  @param  price_            The price bucket for which the value should be calculated.
     *  @return collateralTokens_ The equivalent value of collateral tokens for the given LP Tokens, WAD units.
     *  @return quoteTokens_      The equivalent value of quote tokens for the given LP Tokens, WAD units.
     */
    function getLPTokenExchangeValue(uint256 lpTokens_, uint256 price_) external view returns (uint256 collateralTokens_, uint256 quoteTokens_);

    /**
     *  @notice Calculate the amount of lpTokens equivalent to a given amount of quote tokens.
     *  @param  quoteTokens_      The number of quote tokens to calculate LP tokens for, WAD units.
     *  @param  price_            The price bucket for which the value should be calculated.
     *  @param  owner_            The address which owns the LP tokens.
     *  @return lpTokens_         The equivalent value of LP tokens for the given quote Tokens, RAY units.
     */
    function getLpTokensFromQuoteTokens(uint256 quoteTokens_, uint256 price_, address owner_) external view returns (uint256 lpTokens_);

    /**
     *  @notice Returns the current minimum pool price.
     *  @return minPrice_ The current minimum pool price.
     */
    function getMinimumPoolPrice() external view returns (uint256 minPrice_);

    /**
     *  @notice Gets the current utilization of the pool
     *  @dev    Will return 0 unless the pool has been borrowed from.
     *  @return poolActualUtilization_ The current pool actual utilization, in WAD units.
     */
    function getPoolActualUtilization() external view returns (uint256 poolActualUtilization_);

    /**
     *  @notice Calculate the current collateralization ratio of the pool, based on `totalDebt` and `totalCollateral`.
     *  @return poolCollateralization_ Current pool collateralization ratio.
     */
    function getPoolCollateralization() external view returns (uint256 poolCollateralization_);

    /**
     *  @notice Gets the accepted minimum debt amount in the pool
     *  @return poolMinDebtAmount_ The accepted minimum debt amount, in WAD units.
     */
    function getPoolMinDebtAmount() external view returns (uint256 poolMinDebtAmount_);

    /**
     *  @notice Gets the current target utilization of the pool
     *  @return poolTargetUtilization_ The current pool Target utilization, in WAD units.
     */
    function getPoolTargetUtilization() external view returns (uint256 poolTargetUtilization_);

    /**
     *  @notice Returns the address of the pools quote token
     */
    function quoteTokenAddress() external pure returns (address);
}
