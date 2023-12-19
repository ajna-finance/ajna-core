// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.18;

interface IPositionsHandler {
    function getBucketIndexesWithPosition(address) external view returns(uint256[] memory);
    function getBucketIndexesByTokenId(uint256) external view returns(uint256[] memory);

    function getTokenIdsByActor() external view returns(uint256[] memory);
    function getTokenIdsByBucketIndex(address, uint256) external view returns(uint256[] memory);
}