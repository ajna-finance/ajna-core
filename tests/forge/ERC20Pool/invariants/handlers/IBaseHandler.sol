// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.14;

interface IBaseHandler {

    function getActorsCount() external view returns(uint256);

    function actors(uint256) external view returns(address);

    function numberOfCalls(bytes32) external view returns(uint256); 

    function shouldExchangeRateChange() external view returns(bool);

    function shouldReserveChange() external view returns(bool);

    function firstTake() external view returns(bool);

    function firstTakeIncreaseInReserve() external view returns(uint256);

    function loanKickIncreaseInReserve() external view returns(uint256);
}