// SPDX-License-Identifier: MIT

pragma solidity 0.8.14;

import { IRewardsManagerOwnerActions } from 'src/base/interfaces/rewards/IRewardsManagerOwnerActions.sol';
import { IRewardsManagerState }        from 'src/base/interfaces/rewards/IRewardsManagerState.sol';
import { IRewardsManagerDerivedState } from 'src/base/interfaces/rewards/IRewardsManagerDerivedState.sol';
import { IRewardsManagerEvents }       from 'src/base/interfaces/rewards/IRewardsManagerEvents.sol';
import { IRewardsManagerErrors }       from 'src/base/interfaces/rewards/IRewardsManagerErrors.sol';

interface IRewardsManager is
    IRewardsManagerOwnerActions,
    IRewardsManagerState,
    IRewardsManagerDerivedState,
    IRewardsManagerErrors,
    IRewardsManagerEvents
{

}
