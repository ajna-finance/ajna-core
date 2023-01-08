// SPDX-License-Identifier: MIT

pragma solidity 0.8.14;

import { IPositionManagerOwnerActions } from './position/IPositionManagerOwnerActions.sol';
import { IPositionManagerState }        from './position/IPositionManagerState.sol';
import { IPositionManagerDerivedState } from './position/IPositionManagerDerivedState.sol';
import { IPositionManagerErrors }       from './position/IPositionManagerErrors.sol';
import { IPositionManagerEvents }       from './position/IPositionManagerEvents.sol';

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
