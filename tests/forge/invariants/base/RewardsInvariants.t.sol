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

        // total ajna burned by the pool over the epoch
        (, uint256 totalBurnedInPeriod,) = _getPoolAccumulatorsUtil(curEpoch + 1, curEpoch);

        uint256 rewardsCap = Maths.wmul(totalBurnedInPeriod, 0.1 * 1e18);

        // check claimed rewards < rewards cap
        assertLt(claimedRewards, rewardsCap, "Rewards invariant RW1");
    }

    function _getPoolAccumulatorsUtil(
        uint256 currentBurnEventEpoch_,
        uint256 lastBurnEventEpoch_
    ) internal view returns (uint256, uint256, uint256) {
        (
            uint256 currentBurnTime,
            uint256 totalInterestLatest,
            uint256 totalBurnedLatest
        ) = _pool.burnInfo(currentBurnEventEpoch_);

        (
            ,
            uint256 totalInterestAtBlock,
            uint256 totalBurnedAtBlock
        ) = _pool.burnInfo(lastBurnEventEpoch_);

        uint256 totalBurned   = totalBurnedLatest   != 0 ? totalBurnedLatest   - totalBurnedAtBlock   : totalBurnedAtBlock;
        uint256 totalInterest = totalInterestLatest != 0 ? totalInterestLatest - totalInterestAtBlock : totalInterestAtBlock;

        return (
            currentBurnTime,
            totalBurned,
            totalInterest
        );
    }
}