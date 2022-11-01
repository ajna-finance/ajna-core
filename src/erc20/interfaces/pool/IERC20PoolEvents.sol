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
}