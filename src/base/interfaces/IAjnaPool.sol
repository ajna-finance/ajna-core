// SPDX-License-Identifier: MIT

pragma solidity 0.8.14;

import './pool/IAjnaPoolLenderActions.sol';
import './pool/IAjnaPoolBorrowerActions.sol';
import './pool/IAjnaPoolLiquidationsActions.sol';
import './pool/IAjnaPoolBuybackActions.sol';
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
    IAjnaPoolLiquidationsActions,
    IAjnaPoolBuybackActions,
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
