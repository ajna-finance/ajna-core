// SPDX-License-Identifier: MIT

pragma solidity 0.8.14;

/**
 * @title Rewards Manager State
 */
interface IRewardsManagerState {

    /**
     *  @notice Track whether a depositor has claimed rewards for a given burn event epoch.
     *  @param  tokenId ID of the staked LP NFT.
     *  @param  epoch   The burn epoch to track if rewards were claimed.
     *  @return True if rewards were claimed for the given epoch, else false.
     */
    function isEpochClaimed(
        uint256 tokenId,
        uint256 epoch
    ) external view returns (bool);

    /**
     *  @notice Track the total amount of rewards that have been claimed for a given epoch.
     *  @param  epoch   The burn epoch to track if rewards were claimed.
     *  @return The amount of rewards claimed in given epoch.
     */
    function rewardsClaimed(
        uint256 epoch
    ) external view returns (uint256);

    /**
     *  @notice Track the total amount of rewards that have been claimed for a given burn event's bucket updates.
     *  @param  epoch   The burn epoch to track if rewards were claimed.
     *  @return The amount of update rewards claimed in given epoch.
     */
    function updateRewardsClaimed(
        uint256 epoch
    ) external view returns (uint256);

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

/*********************/
/*** State Structs ***/
/*********************/

struct StakeInfo {
    address ajnaPool;                         // address of the Ajna pool the NFT corresponds to
    uint96  lastInteractionBurnEpoch;         // last burn event the stake interacted with the rewards contract
    address owner;                            // owner of the LP NFT
    uint96  stakingEpoch;                     // epoch at staking time
    mapping(uint256 => BucketState) snapshot; // the LP NFT's balances and exchange rates in each bucket at the time of staking
}

struct BucketState {
    uint256 lpsAtStakeTime;  // [RAY] LP amount the NFT owner is entitled in current bucket at the time of staking
    uint256 rateAtStakeTime; // [RAY] current bucket exchange rate at the time of staking (RAY)
}
