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
     *  @notice Emitted when auction is completed.
     *  @param  borrower   Address of borrower that exits auction.
     *  @param  collateral Borrower's remaining collateral when auction completed.
     */
    event AuctionSettle(
        address indexed borrower,
        uint256 collateral
    );

    /**
     *  @notice Emitted when borrower draws debt from the pool, or adds collateral to the pool.
     *  @param  borrower          The borrower to whom collateral was pledged, and/or debt was drawn for.
     *  @param  amountBorowed     Amount of quote tokens borrowed from the pool.
     *  @param  collateralPledged Amount of collateral locked in the pool.
     *  @param  lup               LUP after borrow.
     */
    event DrawDebt(
        address indexed borrower,
        uint256 amountBorowed,
        uint256 collateralPledged,
        uint256 lup
    );
}
