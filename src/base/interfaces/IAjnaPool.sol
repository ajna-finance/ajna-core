// SPDX-License-Identifier: MIT

pragma solidity 0.8.14;

import './pool/IAjnaPoolLenderActions.sol';
import './pool/IAjnaPoolBorrowerActions.sol';
import './pool/IAjnaPoolLiquidationActions.sol';
import './pool/IAjnaPoolReserveAuctionActions.sol';
import './pool/IAjnaPoolImmutables.sol';
import './pool/IAjnaPoolState.sol';
import './pool/IAjnaPoolDerivedState.sol';
import './pool/IAjnaPoolEvents.sol';
import './pool/IAjnaPoolErrors.sol';

/**
 * @title Ajna Pool
 */
interface IAjnaPool is
    IAjnaPoolLenderActions,
    IAjnaPoolBorrowerActions,
    IAjnaPoolLiquidationActions,
    IAjnaPoolReserveAuctionActions,
    IAjnaPoolImmutables,
    IAjnaPoolState,
    IAjnaPoolDerivedState,
    IAjnaPoolEvents,
    IAjnaPoolErrors
{

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
