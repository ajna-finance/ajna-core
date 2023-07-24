// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.18;

import "@std/console.sol";

import { Pool }                          from 'src/base/Pool.sol';
import { Maths }                         from 'src/libraries/internal/Maths.sol';
import { RewardsManager, _getEpochInfo } from 'src/RewardsManager.sol';

import { IBaseHandler }                from '../interfaces/IBaseHandler.sol';
import { IPositionsAndRewardsHandler } from '../interfaces/IPositionsAndRewardsHandler.sol';
import { PositionsInvariants }         from './PositionsInvariants.sol';

abstract contract RewardsInvariants is PositionsInvariants {

    RewardsManager   internal _rewardsManager;

    function invariant_rewards_RW1_RW2() public useCurrentTimestamp {

        for (uint256 poolIndex = 0; poolIndex < _pools.length; poolIndex++) {
            address pool = _pools[poolIndex];
            uint256 epoch; // incremented every `kickReserve()` call

            while (epoch <= Pool(pool).currentBurnEpoch()) {
                // get staking rewards that have been claimed
                uint256 rewardsClaimed = IPositionsAndRewardsHandler(_handler).rewardsClaimedPerEpoch(pool, epoch);

                // get updating rewards that have been claimed 
                uint256 updateRewardsClaimed = IPositionsAndRewardsHandler(_handler).updateRewardsClaimedPerEpoch(pool, epoch);

                // total ajna burned by the pool over the epoch
                (, uint256 totalBurnedInPeriod,) = _getEpochInfo(pool, epoch);

                // stake rewards cap is 80% of total burned
                uint256 stakeRewardsCap = Maths.wmul(totalBurnedInPeriod, 0.8 * 1e18);

                // update rewards cap is 10% of total burned
                uint256 updateRewardsCap = Maths.wmul(totalBurnedInPeriod, 0.1 * 1e18);

                // check claimed rewards <= rewards cap
                if (stakeRewardsCap != 0) require(rewardsClaimed <= stakeRewardsCap, "Rewards invariant RW1");

                // check update rewards <= rewards cap
                if (updateRewardsCap != 0) require(updateRewardsClaimed <= updateRewardsCap, "Rewards invariant RW2");

                epoch++;
            }
        }
    }

    function invariant_call_summary() public virtual override useCurrentTimestamp {
        console.log("\nCall Summary\n");
        console.log("--Rewards--------");
        console.log("UBRewardsHandler.unstake            ",  IBaseHandler(_handler).numberOfCalls("UBRewardsHandler.unstake"));
        console.log("BRewardsHandler.unstake             ",  IBaseHandler(_handler).numberOfCalls("BRewardsHandler.unstake"));
        console.log("UBRewardsHandler.emergencyUnstake   ",  IBaseHandler(_handler).numberOfCalls("UBRewardsHandler.emergencyUnstake"));
        console.log("BRewardsHandler.emergencyUnstake    ",  IBaseHandler(_handler).numberOfCalls("BRewardsHandler.emergencyUnstake"));
        console.log("UBRewardsHandler.stake              ",  IBaseHandler(_handler).numberOfCalls("UBRewardsHandler.stake"));
        console.log("BRewardsHandler.stake               ",  IBaseHandler(_handler).numberOfCalls("BRewardsHandler.stake"));
        console.log("UBRewardsHandler.updateExchangeRate ",  IBaseHandler(_handler).numberOfCalls("UBRewardsHandler.updateExchangeRate"));
        console.log("BRewardsHandler.updateExchangeRate  ",  IBaseHandler(_handler).numberOfCalls("BRewardsHandler.updateExchangeRate"));
        console.log("UBRewardsHandler.claimRewards       ",  IBaseHandler(_handler).numberOfCalls("UBRewardsHandler.claimRewards"));
        console.log("BRewardsHandler.claimRewards        ",  IBaseHandler(_handler).numberOfCalls("BRewardsHandler.claimRewards"));
        console.log(
            "Sum",
            IBaseHandler(_handler).numberOfCalls("BRewardsHandler.unstake") +
            IBaseHandler(_handler).numberOfCalls("BRewardsHandler.stake") +
            IBaseHandler(_handler).numberOfCalls("BRewardsHandler.updateExchangeRate") +
            IBaseHandler(_handler).numberOfCalls("BRewardsHandler.claimRewards") +
            IBaseHandler(_handler).numberOfCalls("BRewardsHandler.emergencyUnstake")
        );
    }
}
