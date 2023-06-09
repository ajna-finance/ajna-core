// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.18;

interface IPositionsAndRewardsHandler {

    function totalRewardPerEpoch(uint256) external view returns(uint256);

    function getBucketIndexesWithPosition() external view returns(uint256[] memory);
    function getTokenIdsByBucketIndex(uint256) external view returns(uint256[] memory);
    function getBucketIndexesByTokenId(uint256) external view returns(uint256[] memory);
    function getTokenIdsByActor() external view returns(uint256[] memory);
}