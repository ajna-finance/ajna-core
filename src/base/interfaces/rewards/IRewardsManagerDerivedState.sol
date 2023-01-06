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

    /**
     *  @notice Retrieve information about a given stake.
     *  @param  tokenId  ID of the NFT staked in the rewards contract to retrieve information about.
     *  @return The owner of a given NFT stake.
     *  @return The Pool the NFT represents positions in.
     *  @return The last burn epoch in which the owner of the NFT interacted with the rewards contract.
     */
    function getStakeInfo(
        uint256 tokenId
    ) external view returns (address, address, uint256);

}
