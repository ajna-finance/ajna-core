// SPDX-License-Identifier: MIT
pragma solidity 0.8.14;

/**
 * @title ERC20 Pool Lender Actions
 */
interface IERC20PoolLenderActions {

    /**
     *  @notice Deposit unencumbered collateral into a specified bucket.
     *  @param  index  The bucket index to which collateral will be deposited.
     *  @param  amount Amount of collateral to deposit.
     */
    function addCollateral(
        uint256 index,
        uint256 amount
    ) external returns (uint256 lpbChange);

    /**
     *  @notice Called by lenders to move an amount of credit from a specified price bucket to another specified price bucket.
     *  @param  fromIndex     The bucket index from which collateral will be removed.
     *  @param  toIndex       The bucket index to which collateral will be added.
     *  @param  amount        The amount of collateral to be moved by a lender.
     *  @return lpbAmountFrom The amount of LPs moved out from bucket.
     *  @return lpbAmountTo   The amount of LPs moved to destination bucket.
     */
    function moveCollateral(
        uint256 fromIndex,
        uint256 toIndex,
        uint256 amount
    )
        external
        returns (
            uint256 lpbAmountFrom,
            uint256 lpbAmountTo
        );

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

    /**
     *  @notice Called by lenders to claim unencumbered collateral from a price bucket.
     *  @param  index    The bucket index from which unencumbered collateral will be removed.
     *  @param  amount   The amount of unencumbered collateral to claim.
     *  @return lpAmount The amount of LP used for removing collateral amount.
     */
    function removeCollateral(
        uint256 index,
        uint256 amount
    ) external returns (uint256 lpAmount);
}