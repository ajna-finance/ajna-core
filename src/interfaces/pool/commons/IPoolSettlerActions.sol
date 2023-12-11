// SPDX-License-Identifier: MIT

pragma solidity 0.8.18;

/**
 * @title Pool Settler Actions
 */
interface IPoolSettlerActions {

    /**
     *  @notice Called by actors to settle an amount of debt in a completed liquidation.
     *  @param  borrowerAddress_   Address of the auctioned borrower.
     *  @param  maxDepth_          Measured from `HPB`, maximum number of buckets deep to settle debt.
     *  @return collateralSettled_ Amount of collateral settled.
     *  @return isBorrowerSettled_ If all borrower's debt is settled.
     *  @dev    `maxDepth_` is used to prevent unbounded iteration clearing large liquidations.
     */
    function settle(
        address borrowerAddress_,
        uint256 maxDepth_
    ) external returns (uint256 collateralSettled_, bool isBorrowerSettled_);

}