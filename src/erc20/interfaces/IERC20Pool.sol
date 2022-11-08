// SPDX-License-Identifier: MIT

pragma solidity 0.8.14;

import '../../base/interfaces/IPool.sol';

import './pool/IERC20PoolBorrowerActions.sol';
import './pool/IERC20PoolLenderActions.sol';
import './pool/IERC20PoolState.sol';
import './pool/IERC20PoolEvents.sol';

/**
 * @title ERC20 Pool
 */
interface IERC20Pool is
    IPool,
    IERC20PoolLenderActions,
    IERC20PoolBorrowerActions,
    IERC20PoolState,
    IERC20PoolEvents
{

    /**
     *  @notice Initializes a new pool, setting initial state variables.
     *  @param  collateralScale Collateral scale. The precision of the collateral ERC-20 token based on decimals.
     *  @param  rate            Initial interest rate of the pool.
     */
    function initialize(
        uint256 collateralScale,
        uint256 rate
    ) external;

}
