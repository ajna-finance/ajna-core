// SPDX-License-Identifier: MIT

pragma solidity 0.8.14;

/**
 * @title Rewards Manager Derived State
 */
interface IRewardsManagerDerivedState {

    /**
     *  @notice Calculate the amount of rewards that have been accumulated by a staked NFT.
     *  @param  tokenId    ID of the staked LP NFT.
     *  @param  startEpoch The burn epoch from which to start the calculations
     *  @return rewards_   The amount of rewards earned by the NFT.
     */
    function calculateRewards(
        uint256 tokenId,
        uint256 startEpoch
    ) external returns (uint256);

}
