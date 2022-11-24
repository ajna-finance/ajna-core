// SPDX-License-Identifier: MIT
pragma solidity 0.8.14;

/**
 * @title ERC20 Pool Lender Actions
 */
interface IERC20PoolLenderActions {

    /**
     *  @notice Deposit unencumbered collateral into a specified bucket.
     *  @param  amount Amount of collateral to deposit.
     *  @param  index  The bucket index to which collateral will be deposited.
     */
    function addCollateral(
        uint256 amount,
        uint256 index
    ) external returns (uint256 lpbChange);

    /**
     *  @notice Called by lenders to redeem the maximum amount of LP for unencumbered collateral.
     *  @param  index    The bucket index from which unencumbered collateral will be removed.
     *  @return amount   The amount of collateral removed.
     *  @return lpAmount The amount of LP used for removing collateral.
     */
    function removeAllCollateral(uint256 index)
        external
        returns (
            uint256 amount,
            uint256 lpAmount
        );
}