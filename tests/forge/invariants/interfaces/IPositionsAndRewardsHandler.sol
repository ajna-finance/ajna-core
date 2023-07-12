// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.18;

interface IPositionsAndRewardsHandler {
    // positionManager & rewardsManager
    function getBucketIndexesWithPosition(address) external view returns(uint256[] memory);
    function getBucketIndexesByTokenId(uint256) external view returns(uint256[] memory);

    // positionManager
    function getTokenIdsByActor() external view returns(uint256[] memory);
    function getTokenIdsByBucketIndex(address, uint256) external view returns(uint256[] memory);

    // rewardsManager
    function rewardsClaimedPerEpoch(address, uint256) external view returns(uint256);
    function updateRewardsClaimedPerEpoch(address, uint256) external view returns(uint256);
    function getStakedTokenIdsByActor() external view returns(uint256[] memory);
}