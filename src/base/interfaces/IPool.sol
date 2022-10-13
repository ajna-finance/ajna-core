// SPDX-License-Identifier: MIT

pragma solidity 0.8.14;

import './pool/IPoolLenderActions.sol';
import './pool/IPoolBorrowerActions.sol';
import './pool/IPoolLiquidationActions.sol';
import './pool/IPoolReserveAuctionActions.sol';
import './pool/IPoolImmutables.sol';
import './pool/IPoolState.sol';
import './pool/IPoolDerivedState.sol';
import './pool/IPoolEvents.sol';
import './pool/IPoolErrors.sol';

/**
 * @title Base Pool
 */
interface IPool is
    IPoolLenderActions,
    IPoolBorrowerActions,
    IPoolLiquidationActions,
    IPoolReserveAuctionActions,
    IPoolImmutables,
    IPoolState,
    IPoolDerivedState,
    IPoolEvents,
    IPoolErrors
{

    /**
     *  @notice Initializes a new pool, setting initial state variables.
     *  @param  rate             Initial interest rate of the pool.
     *  @param  ajnaTokenAddress Address of the Ajna token.
     */
    function initialize(
        uint256 rate,
        address ajnaTokenAddress
    ) external;

}
