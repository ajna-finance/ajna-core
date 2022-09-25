// SPDX-License-Identifier: MIT
pragma solidity 0.8.14;

import '../../base/interfaces/IAjnaPool.sol';

import './pool/IERC20PoolBorrowerActions.sol';
import './pool/IERC20PoolLenderActions.sol';
import './pool/IERC20PoolLiquidationsActions.sol';
import './pool/IERC20PoolState.sol';
import './pool/IERC20PoolEvents.sol';
import './pool/IERC20PoolErrors.sol';

/**
 * @title Ajna ERC20 Pool
 */
interface IERC20Pool is
    IAjnaPool,
    IERC20PoolLenderActions,
    IERC20PoolBorrowerActions,
    IERC20PoolLiquidationsActions,
    IERC20PoolState,
    IERC20PoolEvents,
    IERC20PoolErrors
{

    /*****************************/
    /*** Initialize Functions ***/
    /*****************************/

    /**
     *  @notice Initializes a new pool, setting initial state variables.
     *  @param  interestRate     Default interest rate of the pool.
     *  @param  ajnaTokenAddress Address of the Ajna token.
     */
    function initialize(
        uint256 interestRate,
        address ajnaTokenAddress
    ) external;

}
