// SPDX-License-Identifier: MIT

pragma solidity 0.8.14;

/**
 * @title ERC20 Pool Immutables
 */
interface IERC20PoolImmutables {

    /**
     *  @notice Returns the `collateralScale` immutable.
     *  @return The precision of the collateral ERC-20 token based on decimals.
     */
    function collateralScale() external view returns (uint256);

    /**
     *  @notice Returns the minimum amount of collateral an actor may have in a bucket.
     *  @param  bucketIndex The bucket index for which the dust limit is desired, or 0 for pledged collateral.
     *  @return The dust limit for `bucketIndex`.
     */
    function collateralDust(uint256 bucketIndex) external view returns (uint256);
}