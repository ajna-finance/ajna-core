
pragma solidity 0.8.14;

import { RewardsInvariants } from "../../invariants/PositionsAndRewards/RewardsInvariants.t.sol";

contract RegressionRewardsManager is RewardsInvariants {

    function setUp() public override { 
        super.setUp();
    }


    function test_regression_rewards_PM1_1() public {
        _rewardsHandler.unstake(156983341, 3, 1057, 627477641256361);
        _rewardsHandler.settleAuction(2108881198342615861856429474, 922394580216134598, 4169158839, 1000000019773478651);
        invariant_positions_PM1_PM2();
    }

    function test_regression_rewards_PM1_2() public {
        _rewardsHandler.addCollateral(378299828523348996450409252968204856717337200844620995950755116109442848, 115792089237316195423570985008687907853269984665640564039457584007913129639932, 52986329559447389847739820276326448003115507778858588690614563138365, 115792089237316195423570985008687907853269984665640564039457584007913129639932);
        _rewardsHandler.memorializePositions(2386297678015684371711534521507, 1, 2015255596877246640, 0);
        _rewardsHandler.moveLiquidity(999999999999999999999999999999999999999542348, 2634, 6160, 4579, 74058);
        invariant_positions_PM1_PM2();
    }

    function test_regression_rewards_PM1_3() public {
        _rewardsHandler.memorializePositions(1072697513541617411598352761547948569235246260453338, 49598781763341098132796575116941537, 115792089237316195423570985008687907853269984665640564039457584007913129639933, 59786055813720421827623480119157950185156928336);
        _rewardsHandler.drawDebt(71602122977707056985766204553433920464603022469065, 0, 3);
        _rewardsHandler.settleAuction(1533, 6028992255037431023, 999999999999998827363045226813101730497689206, 3712);
        _rewardsHandler.bucketTake(115792089237316195423570985008687907853269984665640564039457584007913129639935, 14721144691130718757631011689447950991492275176685060291564256, false, 136782600565674582447300799997512602488616407787063657498, 12104321153503350510632448265168933687786653851546540372949180052575211);
        _rewardsHandler.unstake(5219408520630054730985988951364206956803005171136246340104521696738150, 2, 0, 7051491938468651247212916289972038814809873);
        _rewardsHandler.settleAuction(0, 115792089237316195423570985008687907853269984665640564039457584007913129639935, 115792089237316195423570985008687907853269984665640564039457584007913129639933, 120615857050623137463512130550262626813346106);
        invariant_positions_PM1_PM2();
    }

    function test_regression_rewards_RW1() public {
        invariant_rewards_RW1();
    }
}