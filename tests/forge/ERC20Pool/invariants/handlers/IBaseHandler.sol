// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.14;

// TODO: Complete this interface
interface IBaseHandler {

    function getActorsCount() external view returns(uint256);

    function _actors(uint256) external view returns(address);

    function numberOfCalls(bytes32) external view returns(uint256); 

    function shouldExchangeRateChange() external view returns(bool);

    function shouldReserveChange() external view returns(bool);
}