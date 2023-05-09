
pragma solidity 0.8.14;

import { RewardsInvariants } from "../../invariants/PositionsAndRewards/RewardsInvariants.t.sol";

contract RegressionRewardsManager is RewardsInvariants {

    function setUp() public override { 
        super.setUp();
    }


    function test_regression_rewards_PM1() public {
        _rewardsHandler.unstake(156983341, 3, 1057, 627477641256361);
        _rewardsHandler.settleAuction(2108881198342615861856429474, 922394580216134598, 4169158839, 1000000019773478651);
        invariant_positions_PM1_PM2();
    }

}