// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.14;

import "@std/console.sol";

import { Maths } from 'src/libraries/internal/Maths.sol';
import { IBaseHandler }          from '../interfaces/IBaseHandler.sol';
import { LiquidationInvariants } from './LiquidationInvariants.t.sol';

abstract contract ReserveInvariants is LiquidationInvariants {

    function invariant_rewards_RW1() public useCurrentTimestamp {

        uint256 curEpoch = _pool.currentBurnEpoch();

        // get rewards that have been claimed
        uint256 claimedRewards  = IBaseHandler(_handler).totalRewardPerEpoch(curEpoch);

        // calculate cap
        (
            ,
            // total interest accumulated by the pool over the claim period
            uint256 totalBurnedInPeriod,
            // total tokens burned over the claim period
            uint256 totalInterestEarnedInPeriod
        ) = _rewards._getPoolAccumulators(_pool, curEpoch + 1, curEpoch);

        uint256 rewardsCap = Maths.wmul(totalBurnedInPeriod, 0.9 * 1e18);

        // check claimed rewards < rewards cap
        assertLt(claimedRewards, rewardsCap, "Rewards invariant RW1");
    }
}