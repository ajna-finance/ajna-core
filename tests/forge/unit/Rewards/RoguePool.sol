// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.18;

import 'src/interfaces/rewards/IRewardsManager.sol';
import '@openzeppelin/contracts/token/ERC20/ERC20.sol';

contract RoguePool {
    IRewardsManager immutable rewardsManager;
    ERC20 immutable ajnaToken;

    uint256 public burnEpoch;
    uint256 public prevBurnEpoch;

    constructor(IRewardsManager _rewardsManager, ERC20 _ajnaToken) {
        rewardsManager = _rewardsManager;
        ajnaToken = _ajnaToken;
    }

    function reset() external {
        prevBurnEpoch = 0;
        burnEpoch = 0;
    }

    function setBurnEpoch(uint256 newEpoch) external {
        prevBurnEpoch = burnEpoch;
        burnEpoch = newEpoch;
    }

    function currentBurnEpoch() external view returns(uint256) {
        return burnEpoch;
    }

    function burnInfo(uint256 epoch) external view returns (uint256 burnBlock_, uint256 totalInterest_, uint256 totalBurned_) {
        uint256 targetBalance = ajnaToken.balanceOf(address(rewardsManager));
        burnBlock_ = block.timestamp;
        if (epoch == burnEpoch - 1) {
            // overwhelm the reward cap check
            totalInterest_ = 1 * 1e18;
            totalBurned_ = targetBalance * 10;
        }
    }

    function bucketInfo(uint256) external pure returns(uint256, uint256, uint256, uint256, uint256) {
        return (0, 0, 0, 100000 * 1e18, 0);
    }

    function bucketExchangeRate(uint256) external view returns(uint256) {
        if (prevBurnEpoch == 0)
            return 1;
        else
            return 300000;
    }
}