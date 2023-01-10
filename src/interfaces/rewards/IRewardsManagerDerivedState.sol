// SPDX-License-Identifier: MIT

pragma solidity 0.8.14;

/**
 * @title Rewards Manager Derived State
 */
interface IRewardsManagerDerivedState {

    /**
     *  @notice Calculate the amount of rewards that have been accumulated by a staked NFT.
     *  @param  tokenId    ID of the staked LP NFT.
     *  @param  claimEpoch The end burn epoch to calculate rewards for (rewards calculation starts from the last claimed epoch).
     *  @return rewards_   The amount of rewards earned by the NFT.
     */
    function calculateRewards(
        uint256 tokenId,
        uint256 claimEpoch
    ) external view returns (uint256);

}
