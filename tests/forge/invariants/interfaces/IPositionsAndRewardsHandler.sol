// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.18;

interface IPositionsAndRewardsHandler {
    // positionManager & rewardsManager
    function getBucketIndexesWithPosition() external view returns(uint256[] memory);
    function getBucketIndexesByTokenId(uint256) external view returns(uint256[] memory);

    // positionManager
    function getTokenIdsByActor() external view returns(uint256[] memory);
    function getTokenIdsByBucketIndex(uint256) external view returns(uint256[] memory);

    // rewardsManager
    function rewardsClaimedPerEpoch(uint256) external view returns(uint256);
    function updateRewardsClaimedPerEpoch(uint256) external view returns(uint256);
    function getStakedTokenIdsByActor() external view returns(uint256[] memory);
}