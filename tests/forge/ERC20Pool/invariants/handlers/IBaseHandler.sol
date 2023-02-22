// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.14;

interface IBaseHandler {

    function getActorsCount() external view returns(uint256);

    function actors(uint256) external view returns(address);

    function numberOfCalls(bytes32) external view returns(uint256);

    function fenwickSumAtIndex(uint256) external view returns(uint256);

    function fenwickTreeSum() external view returns(uint256); 

    function shouldExchangeRateChange() external view returns(bool);

    function previousExchangeRate(uint256) external view returns(uint256);
    
    function currentExchangeRate(uint256) external view returns(uint256);

    function shouldReserveChange() external view returns(bool);

    function isKickerRewarded() external view returns(bool);

    function kickerBondChange() external view returns(uint256);

    function previousReserves() external view returns(uint256);
    
    function currentReserves() external view returns(uint256);

    function firstTake() external view returns(bool);

    function firstTakeIncreaseInReserve() external view returns(uint256);

    function loanKickIncreaseInReserve() external view returns(uint256);

    function drawDebtIncreaseInReserve() external view returns(uint256);
}