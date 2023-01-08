// SPDX-License-Identifier: MIT

pragma solidity 0.8.14;

import { IRewardsManagerOwnerActions } from './IRewardsManagerOwnerActions.sol';
import { IRewardsManagerState }        from './IRewardsManagerState.sol';
import { IRewardsManagerEvents }       from './IRewardsManagerEvents.sol';
import { IRewardsManagerErrors }       from './IRewardsManagerErrors.sol';

interface IRewardsManager is
    IRewardsManagerOwnerActions,
    IRewardsManagerState,
    IRewardsManagerErrors,
    IRewardsManagerEvents
{

}
