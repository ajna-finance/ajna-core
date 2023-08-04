// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.18;

import { BucketBankruptcyERC20PoolRewardsInvariants } from "../../invariants/PositionsAndRewards/BucketBankruptcyERC20PoolRewardsInvariants.t.sol";

contract RegressionTestBankBankruptcyERC20PoolRewards is BucketBankruptcyERC20PoolRewardsInvariants { 

    function setUp() public override { 
        super.setUp();
    }

    // Test was failing because token needs to be reapproved for stake after unstaking
    // Fixed with approving token before stake
    function test_regression_position_evm_revert_1() external {
        _bucketBankruptcyerc20poolrewardsHandler.moveStakedLiquidity(3, 1, 4456004777645809093369137635038884732841, 115792089237316195423570985008687907853269984665640564039457584007913129639933, 40687908950166026711192);
    }

    // Test was failing because of unbounded bucket used for `fromBucketIndex`
    // Fixed with bounding `fromBucketIndex`
    function test_regression_max_less_than_min() external {
        _bucketBankruptcyerc20poolrewardsHandler.takeOrSettleAuction(115792089237316195423570985008687907853269984665640564039457584007913129639934, 47501406159061048326781, 110986208267306903569458210414739750843311008184499947884172946209775740554);
        _bucketBankruptcyerc20poolrewardsHandler.takeOrSettleAuction(1881514382560036936235, 3, 14814387297039010985037823532);
        _bucketBankruptcyerc20poolrewardsHandler.moveQuoteTokenToLowerBucket(797766346153846154214, 41446531673892822322, 11701, 27835018298679073652989722292632508325056543016077421626954570959368347669749);
    }

    // Test was failing because of incorrect borrower index from borrowers array
    // Fixed with bounding index to use from 0 to `length - 1` instead of `length`
    function test_regression_index_out_of_bounds() external {
        _bucketBankruptcyerc20poolrewardsHandler.moveQuoteTokenToLowerBucket(8350, 38563772714580316601477528168172448197192851223481495804140163882250050756970, 2631419556349366366777984756718, 1211945352);
        _bucketBankruptcyerc20poolrewardsHandler.takeOrSettleAuction(211495175470613993028534000000, 278145600165504025408587, 27529661686764881266950946609980959649419024772429123428587103668572353435463);
        _bucketBankruptcyerc20poolrewardsHandler.lenderKickAuction(115792089237316195423570985008687907853269984665640564039457584007913129639932, 6893553321768, 0);
        _bucketBankruptcyerc20poolrewardsHandler.lenderKickAuction(999993651401512530, 102781931937447242982, 270951946802940031780297034197);
        _bucketBankruptcyerc20poolrewardsHandler.moveQuoteTokenToLowerBucket(142908941962660588271918613275457408417799350540, 2, 7499, 21259944100462201457856802765711375950508);
        _bucketBankruptcyerc20poolrewardsHandler.takeOrSettleAuction(10312411154, 11741, 808194882698130156430790172156918);

        invariant_positions_PM1_PM2_PM3();
    }
    
}
