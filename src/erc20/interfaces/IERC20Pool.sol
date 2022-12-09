// SPDX-License-Identifier: MIT

pragma solidity 0.8.14;

import '../../base/interfaces/IPool.sol';

import './pool/IERC20PoolBorrowerActions.sol';
import './pool/IERC20PoolLenderActions.sol';
import './pool/IERC20PoolImmutables.sol';
import './pool/IERC20PoolEvents.sol';

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

}
