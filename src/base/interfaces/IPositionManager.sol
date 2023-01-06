// SPDX-License-Identifier: MIT

pragma solidity 0.8.14;

import './position/IPositionManagerOwnerActions.sol';
import './position/IPositionManagerState.sol';
import './position/IPositionManagerDerivedState.sol';
import './position/IPositionManagerErrors.sol';
import './position/IPositionManagerEvents.sol';
/**
 *  @title Position Manager Interface
 */
interface IPositionManager is
    IPositionManagerOwnerActions,
    IPositionManagerState,
    IPositionManagerDerivedState,
    IPositionManagerErrors,
    IPositionManagerEvents
{

}
