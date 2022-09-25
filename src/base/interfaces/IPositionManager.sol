// SPDX-License-Identifier: MIT

pragma solidity 0.8.14;

import './position/IPositionManagerOwnerActions.sol';
import './position/IPositionManagerDerivedState.sol';
import './position/IPositionManagerEvents.sol';
/**
 *  @title Ajna Position Manager
 */
interface IPositionManager is
    IPositionManagerOwnerActions,
    IPositionManagerDerivedState,
    IPositionManagerEvents
{

}
