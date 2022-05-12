// SPDX-License-Identifier: MIT
pragma solidity 0.8.11;

interface IPool {

    /**
     * @notice struct holding borrower related info per price bucket
     * @param debt                 borrower debt, WAD
     * @param collateralDeposited  collateral deposited by borrower, WAD
     * @param inflatorSnapshot     current borrower inflator snapshot, RAY
    */
    struct BorrowerInfo {
        uint256 debt;
        uint256 collateralDeposited;
        uint256 inflatorSnapshot;
    }

    /**
     * @notice Emitted when lender adds quote token to the pool
     * @param lender recipient that added quote tokens
     * @param price  price at which quote tokens were added
     * @param amount amount of quote tokens added to the pool
     * @param lup    LUP calculated after deposit
    */
    event AddQuoteToken(address indexed lender, uint256 indexed price, uint256 amount, uint256 lup);

    /**
     * @notice Emitted when lender removes quote token from the pool
     * @param lender recipient that removed quote tokens
     * @param price  price at which quote tokens were removed
     * @param amount amount of quote tokens removed from the pool
     * @param lup    LUP calculated after removal
    */
    event RemoveQuoteToken(
        address indexed lender,
        uint256 indexed price,
        uint256 amount,
        uint256 lup
    );

    /**
     * @notice Emitted when borrower locks collateral in the pool
     * @param borrower msg.sender
     * @param amount   amount of collateral locked in the pool
    */
    event AddCollateral(address indexed borrower, uint256 amount);

    /**
     * @notice Emitted when borrower removes collateral from the pool
     * @param borrower msg.sender
     * @param amount   amount of collateral removed from the pool
    */
    event RemoveCollateral(address indexed borrower, uint256 amount);

    /**
     * @notice Emitted when lender claims unencumbered collateral
     * @param claimer recipient that claimed collateral
     * @param price   price at which unencumbered collateral was claimed
    */
    event ClaimCollateral(
        address indexed claimer,
        uint256 indexed price,
        uint256 amount,
        uint256 lps
    );

    /**
     * @notice Emitted when borrower borrows quote tokens from pool
     * @param borrower msg.sender
     * @param lup      LUP after borrow
     * @param amount   amount of quote tokens borrowed from the pool
    */
    event Borrow(address indexed borrower, uint256 lup, uint256 amount);

    /**
     * @notice Emitted when borrower repays quote tokens to the pool
     * @param borrower msg.sender
     * @param lup      LUP after repay
     * @param amount   amount of quote tokens repayed to the pool
    */
    event Repay(address indexed borrower, uint256 lup, uint256 amount);

    /**
     * @notice Emitted when pool interest rate is updated
     * @param oldRate Old pool interest rate
     * @param newRate New pool interest rate
    */
    event UpdateInterestRate(uint256 oldRate, uint256 newRate);

    /**
     * @notice Emitted when collateral is exchanged for quote tokens
     * @param bidder     msg.sender
     * @param price      price at which collateral was exchanged for quote tokens
     * @param amount     amount of quote tokens purchased
     * @param collateral amount of collateral exchanged for quote tokens
    */
    event Purchase(
        address indexed bidder,
        uint256 indexed price,
        uint256 amount,
        uint256 collateral
    );

    /**
     * @notice Emitted when a borrower is liquidated
     * @param borrower   borrower that was liquidated
     * @param debt       debt recovered after borrower was liquidated
     * @param collateral collateral used to recover debt when user liquidated
    */
    event Liquidate(address indexed borrower, uint256 debt, uint256 collateral);

    error AlreadyInitialized();
    error InvalidPrice();
    error NoClaimToBucket();
    error NoDebtToRepay();
    error NoDebtToLiquidate();
    error InsufficientBalanceForRepay();
    error InsufficientCollateralBalance();
    error InsufficientCollateralForBorrow();
    error InsufficientLiquidity(uint256 amountAvailable);
    error PoolUndercollateralized(uint256 collateralization);
    error BorrowerIsCollateralized(uint256 collateralization);
    error AmountExceedsTotalClaimableQuoteToken(uint256 totalClaimable);
    error AmountExceedsAvailableCollateral(uint256 availableCollateral);

    /**
     * @notice Called by lenders to add an amount of credit at a specified price bucket
     * @param  recipient_ The recipient adding quote tokens
     * @param  amount_ The amount of quote token to be added by a lender
     * @param  price_ The bucket to which the quote tokens will be added
     * @return lpTokens_ The amount of LP Tokens received for the added quote tokens
    */
    function addQuoteToken(address recipient_, uint256 amount_, uint256 price_) external returns (uint256 lpTokens_);

    /**
     * @notice Called by lenders to remove an amount of credit at a specified price bucket
     * @param recipient_ The recipient removing quote tokens
     * @param maxAmount_ The maximum amount of quote token to be removed by a lender
     * @param price_ The bucket from which quote tokens will be removed
    */
    function removeQuoteToken(address recipient_, uint256 maxAmount_, uint256 price_) external;

    /**
     * @notice Called by borrowers to add collateral to the pool
     * @param amount_ The amount of collateral in deposit tokens to be added to the pool
    */
    function addCollateral(uint256 amount_) external;

    /**
     * @notice Called by borrowers to remove an amount of collateral
     * @param amount_ The amount of collateral in deposit tokens to be removed from a position
    */
    function removeCollateral(uint256 amount_) external;

    /**
     * @notice Called by lenders to claim unencumbered collateral from a price bucket
     * @param recipient_ The recipient claiming collateral
     * @param amount_ The amount of unencumbered collateral to claim
     * @param price_ The bucket from which unencumbered collateral will be claimed
    */
    function claimCollateral(address recipient_, uint256 amount_, uint256 price_) external;

    /**
     * @notice Called by a borrower to open or expand a position
     * @dev Can only be called if quote tokens have already been added to the pool
     * @param amount_ The amount of quote token to borrow
     * @param limitPrice_ Lower bound of LUP change (if any) that the borrower will tolerate from a creating or modifying position
    */
    function borrow(uint256 amount_, uint256 limitPrice_) external;

    /**
     * @notice Called by a borrower to repay some amount of their borrowed quote tokens
     * @param maxAmount_ WAD The maximum amount of quote token to repay
    */
    function repay(uint256 maxAmount_) external;

    /**
     * @notice Exchanges collateral for quote token
     * @param amount_ WAD The amount of quote token to purchase
     * @param price_ The purchasing price of quote token
    */
    function purchaseBid(uint256 amount_, uint256 price_) external;

    /**
     * @notice Liquidates a given borrower's position
     * @param borrower_ The address of the borrower being liquidated
    */
    function liquidate(address borrower_) external;

    /**
     * @notice Returns a given lender's LP tokens in a given price bucket
     * @param owner_ The EOA to check token balance for
     * @param price_ The price bucket for which the value should be calculated, WAD
     * @return lpTokens_ - The EOA's lp token balance in the bucket, RAY
    */
    function getLPTokenBalance(address owner_, uint256 price_) external view returns (uint256 lpTokens_);

    /**
     * @notice Calculate the amount of collateral and quote tokens for a given amount of LP Tokens
     * @param lpTokens_ The number of lpTokens to calculate amounts for
     * @param price_ The price bucket for which the value should be calculated
    * @return collateralTokens_ - The equivalent value of collateral tokens for the given LP Tokens, WAD
     * @return quoteTokens_ - The equivalent value of quote tokens for the given LP Tokens, WAD
    */
    function getLPTokenExchangeValue(uint256 lpTokens_, uint256 price_) external view returns (uint256 collateralTokens_, uint256 quoteTokens_);

}
