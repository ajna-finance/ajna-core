// SPDX-License-Identifier: MIT

pragma solidity 0.8.14;

import '../../base/interfaces/IPool.sol';

import './pool/IERC20PoolBorrowerActions.sol';
import './pool/IERC20PoolLenderActions.sol';
import './pool/IERC20PoolLiquidationActions.sol';
import './pool/IERC20PoolState.sol';
import './pool/IERC20PoolEvents.sol';
import './pool/IERC20PoolErrors.sol';

/**
 * @title ERC20 Pool
 */
interface IERC20Pool is
    IPool,
    IERC20PoolLenderActions,
    IERC20PoolBorrowerActions,
    IERC20PoolLiquidationActions,
    IERC20PoolState,
    IERC20PoolEvents,
    IERC20PoolErrors
{

}
