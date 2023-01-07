// SPDX-License-Identifier: MIT

pragma solidity 0.8.14;

import { IPositionManagerOwnerActions } from 'src/base/interfaces/position/IPositionManagerOwnerActions.sol';
import { IPositionManagerState }        from 'src/base/interfaces/position/IPositionManagerState.sol';
import { IPositionManagerDerivedState } from 'src/base/interfaces/position/IPositionManagerDerivedState.sol';
import { IPositionManagerErrors }       from 'src/base/interfaces/position/IPositionManagerErrors.sol';
import { IPositionManagerEvents }       from 'src/base/interfaces/position/IPositionManagerEvents.sol';

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
