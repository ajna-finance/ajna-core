// SPDX-License-Identifier: MIT

pragma solidity 0.8.14;

import 'src/base/interfaces/IPool.sol';

import 'src/erc20/interfaces/pool/IERC20PoolBorrowerActions.sol';
import 'src/erc20/interfaces/pool/IERC20PoolLenderActions.sol';
import 'src/erc20/interfaces/pool/IERC20PoolImmutables.sol';
import 'src/erc20/interfaces/pool/IERC20PoolEvents.sol';

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
