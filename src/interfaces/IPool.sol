// SPDX-License-Identifier: MIT
pragma solidity 0.8.11;

interface IPool {

    struct BorrowerInfo {
        uint256 debt; // RAD
        uint256 collateralDeposited; // RAY
        uint256 inflatorSnapshot; // RAY, the inflator rate of the given borrower's last state change
    }

    event AddQuoteToken(address indexed lender, uint256 indexed price, uint256 amount, uint256 lup);
    event RemoveQuoteToken(
        address indexed lender,
        uint256 indexed price,
        uint256 amount,
        uint256 lup
    );
    event AddCollateral(address indexed borrower, uint256 amount);
    event RemoveCollateral(address indexed borrower, uint256 amount);
    event ClaimCollateral(
        address indexed claimer,
        uint256 indexed price,
        uint256 amount,
        uint256 lps
    );
    event Borrow(address indexed borrower, uint256 lup, uint256 amount);
    event Repay(address indexed borrower, uint256 lup, uint256 amount);
    event UpdateInterestRate(uint256 oldRate, uint256 newRate);
    event Purchase(
        address indexed bidder,
        uint256 indexed price,
        uint256 amount,
        uint256 collateral
    );
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

    function addQuoteToken(
        address _recipient,
        uint256 _amount,
        uint256 _price
    ) external returns (uint256 lpTokens);

    function removeQuoteToken(
        address _recipient,
        uint256 _amount,
        uint256 _price
    ) external;

    function addCollateral(uint256 _amount) external;

    function removeCollateral(uint256 _amount) external;

    function claimCollateral(
        address _recipient,
        uint256 _amount,
        uint256 _price
    ) external;

    function borrow(uint256 _amount, uint256 _stopPrice) external;

    function repay(uint256 _amount) external;

    function purchaseBid(uint256 _amount, uint256 _price) external;

    function getLPTokenBalance(address _owner, uint256 _price)
        external
        view
        returns (uint256 lpTokens);

    function getLPTokenExchangeValue(uint256 _lpTokens, uint256 _price)
        external
        view
        returns (uint256 _collateralTokens, uint256 _quoteTokens);

    function liquidate(address _borrower) external;
}
