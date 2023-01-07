// SPDX-License-Identifier: MIT

pragma solidity 0.8.14;

import { IRewardsManagerOwnerActions } from './rewards/IRewardsManagerOwnerActions.sol';
import { IRewardsManagerState }        from './rewards/IRewardsManagerState.sol';
import { IRewardsManagerDerivedState } from './rewards/IRewardsManagerDerivedState.sol';
import { IRewardsManagerEvents }       from './rewards/IRewardsManagerEvents.sol';
import { IRewardsManagerErrors }       from './rewards/IRewardsManagerErrors.sol';

interface IRewardsManager is
    IRewardsManagerOwnerActions,
    IRewardsManagerState,
    IRewardsManagerDerivedState,
    IRewardsManagerErrors,
    IRewardsManagerEvents
{

}
