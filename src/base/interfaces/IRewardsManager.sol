// SPDX-License-Identifier: MIT

pragma solidity 0.8.14;

import './rewards/IRewardsManagerOwnerActions.sol';
import './rewards/IRewardsManagerState.sol';
import './rewards/IRewardsManagerDerivedState.sol';
import './rewards/IRewardsManagerEvents.sol';
import './rewards/IRewardsManagerErrors.sol';

interface IRewardsManager is
    IRewardsManagerOwnerActions,
    IRewardsManagerState,
    IRewardsManagerDerivedState,
    IRewardsManagerErrors,
    IRewardsManagerEvents
{

}
