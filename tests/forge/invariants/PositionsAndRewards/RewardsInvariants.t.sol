// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.14;

import "@std/console.sol";
import { Maths }                from 'src/libraries/internal/Maths.sol';
import { RewardsManager }       from 'src/RewardsManager.sol';
import { _getPoolAccumulators } from 'src/RewardsManager.sol';

import { IBaseHandler }        from '../interfaces/IBaseHandler.sol';
import { RewardsHandler }      from './handlers/RewardsHandler.sol';
import { PositionsInvariants } from './PositionsInvariants.t.sol';

contract RewardsInvariants is PositionsInvariants {

    RewardsManager   internal _rewards;
    RewardsHandler   internal _rewardsHandler;

    function setUp() public override virtual {

        super.setUp();

        _rewards = new RewardsManager(address(_ajna), _position);

        excludeContract(address(_positionHandler));
        excludeContract(address(_rewards));

        _rewardsHandler = new RewardsHandler(
            address(_rewards),
            address(_position),
            address(_erc20pool),
            address(_ajna),
            address(_quote),
            address(_collateral),
            address(_poolInfo),
            NUM_ACTORS,
            address(this)
        );

        _handler = address(_rewardsHandler);
    }



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
        console.log("--Positions--------");
        console.log("UBRewardsHandler.unstake            ",  IBaseHandler(_handler).numberOfCalls("UBRewardsHandler.unstake"));
        console.log("BRewardsHandler.unstake             ",  IBaseHandler(_handler).numberOfCalls("BRewardsHandler.unstake"));
        console.log("UBRewardsHandler.stake              ",  IBaseHandler(_handler).numberOfCalls("UBRewardsHandler.stake"));
        console.log("BRewardsHandler.stake               ",  IBaseHandler(_handler).numberOfCalls("BRewardsHandler.stake"));
        console.log(
            "Sum",
            IBaseHandler(_handler).numberOfCalls("BRewardsHandler.unstake") +
            IBaseHandler(_handler).numberOfCalls("BRewardsHandler.stake")
        );
    }

}