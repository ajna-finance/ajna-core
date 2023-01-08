// SPDX-License-Identifier: MIT

pragma solidity 0.8.14;

import { IPool }                     from '../IPool.sol';
import { IERC20PoolBorrowerActions } from './IERC20PoolBorrowerActions.sol';
import { IERC20PoolLenderActions }   from './IERC20PoolLenderActions.sol';
import { IERC20PoolImmutables }      from './IERC20PoolImmutables.sol';
import { IERC20PoolEvents }          from './IERC20PoolEvents.sol';

/**
 * @title ERC20 Pool
 */
interface IERC20Pool is
    IPool,
    IERC20PoolLenderActions,
    IERC20PoolBorrowerActions,
    IERC20PoolImmutables,
    IERC20PoolEvents
{

    /**
     *  @notice Initializes a new pool, setting initial state variables.
     *  @param  rate Initial interest rate of the pool.
     */
    function initialize(uint256 rate) external;

    /**
     *  @notice Returns the minimum amount of collateral an actor may have in a bucket.
     *  @param  bucketIndex The bucket index for which the dust limit is desired, or 0 for pledged collateral.
     *  @return The dust limit for `bucketIndex`.
     */
    function bucketCollateralDust(
        uint256 bucketIndex
    ) external pure returns (uint256);

}
