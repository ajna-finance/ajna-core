// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.14;

import { _getPoolAccumulators } from 'src/RewardsManager.sol';

import { Maths } from 'src/libraries/internal/Maths.sol';
import { IBaseHandler }          from '../interfaces/IBaseHandler.sol';
import { PositionsInvariants } from './PositionsInvariants.t.sol';

abstract contract RewardsInvariants is PositionsInvariants {

    function invariant_rewards_RW1() public useCurrentTimestamp {

        uint256 curEpoch = _pool.currentBurnEpoch();

        // get rewards that have been claimed
        uint256 claimedRewards  = IBaseHandler(_handler).totalRewardPerEpoch(curEpoch);

        // total ajna burned by the pool over the epoch
        (, uint256 totalBurnedInPeriod,) = _getPoolAccumulators(address(_pool), curEpoch + 1, curEpoch);

        uint256 rewardsCap = Maths.wmul(totalBurnedInPeriod, 0.1 * 1e18);

        // check claimed rewards < rewards cap
        assertLt(claimedRewards, rewardsCap, "Rewards invariant RW1");
    }



}