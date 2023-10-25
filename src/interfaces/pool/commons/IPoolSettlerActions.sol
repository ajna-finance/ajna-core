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
     *  @return debtSettled_       Amount of debt settled.
     *  @return collateralSettled_ Amount of collateral settled.
     *  @dev    `maxDepth_` is used to prevent unbounded iteration clearing large liquidations.
     */
    function settle(
        address borrowerAddress_,
        uint256 maxDepth_
    ) external returns (uint256 debtSettled_, uint256 collateralSettled_);

}