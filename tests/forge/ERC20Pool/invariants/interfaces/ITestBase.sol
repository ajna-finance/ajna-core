// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.14;

interface ITestBase {

    function currentTimestamp() external view returns (uint256 currentTimestamp);

    function setCurrentTimestamp(uint256 currentTimestamp) external;

}
