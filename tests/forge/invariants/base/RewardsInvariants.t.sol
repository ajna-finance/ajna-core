// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.14;

import '@std/console.sol';

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


    function invariant_call_summary() public virtual override useCurrentTimestamp {
        console.log("\nCall Summary\n");
        console.log("--Rewards--------");
        console.log("BRewardsHandler.stake               ",  IBaseHandler(_handler).numberOfCalls("BRewardsHandler.stake"));
        console.log("UBRewardsHandler.stake              ",  IBaseHandler(_handler).numberOfCalls("UBRewardsHandler.stake"));
        console.log("BRewardsHandler.unstake             ",  IBaseHandler(_handler).numberOfCalls("BRewardsHandler.unstake"));
        console.log("UBRewardsHandler.unstake            ",  IBaseHandler(_handler).numberOfCalls("UBRewardsHandler.unstake"));
        console.log("--Positions--------");
        console.log("UBPositionHandler.mint              ",  IBaseHandler(_handler).numberOfCalls("UBPositionHandler.mint"));
        console.log("BPositionHandler.mint               ",  IBaseHandler(_handler).numberOfCalls("BPositionHandler.mint"));
        console.log("UBPositionHandler.burn              ",  IBaseHandler(_handler).numberOfCalls("UBPositionHandler.burn"));
        console.log("BPositionHandler.burn               ",  IBaseHandler(_handler).numberOfCalls("BPositionHandler.burn"));
        console.log("UBPositionHandler.memorialize       ",  IBaseHandler(_handler).numberOfCalls("UBPositionHandler.memorialize"));
        console.log("BPositionHandler.memorialize        ",  IBaseHandler(_handler).numberOfCalls("BPositionHandler.memorialize"));
        console.log("UBPositionHandler.redeem            ",  IBaseHandler(_handler).numberOfCalls("UBPositionHandler.redeem"));
        console.log("BPositionHandler.redeem             ",  IBaseHandler(_handler).numberOfCalls("BPositionHandler.redeem"));
        console.log("UBPositionHandler.moveLiquidity     ",  IBaseHandler(_handler).numberOfCalls("UBPositionHandler.moveLiquidity"));
        console.log("BPositionHandler.moveLiquidity      ",  IBaseHandler(_handler).numberOfCalls("BPositionHandler.moveLiquidity"));
        console.log(
            "Sum",
            IBaseHandler(_handler).numberOfCalls("BRewardsHandler.stake") + 
            IBaseHandler(_handler).numberOfCalls("BRewardsHandler.unstake") + 
            IBaseHandler(_handler).numberOfCalls("BPositionHandler.mint") + 
            IBaseHandler(_handler).numberOfCalls("BPositionHandler.burn") +
            IBaseHandler(_handler).numberOfCalls("BPositionHandler.memorialize") +
            IBaseHandler(_handler).numberOfCalls("BPositionHandler.redeem") +
            IBaseHandler(_handler).numberOfCalls("BPositionHandler.moveLiquidity") 
        );
    }

}