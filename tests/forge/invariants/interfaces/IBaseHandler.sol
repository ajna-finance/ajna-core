// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.14;

interface IBaseHandler {

    function LENDER_MIN_BUCKET_INDEX() external view returns(uint256);
    function LENDER_MAX_BUCKET_INDEX() external view returns(uint256);

    function getActorsCount() external view returns(uint256);
    function actors(uint256) external view returns(address);

    function numberOfCalls(bytes32) external view returns(uint256);

    function fenwickSumAtIndex(uint256) external view returns(uint256);
    function fenwickTreeSum() external view returns(uint256); 
    function fenwickSumTillIndex(uint256) external view returns(uint256);

    function exchangeRateShouldNotChange(uint256) external view returns(bool);
    function previousExchangeRate(uint256) external view returns(uint256);
    function previousBankruptcy(uint256) external view returns(uint256);

    function isKickerRewarded() external view returns(bool);
    function kickerBondChange() external view returns(uint256);

    function previousReserves() external view returns(uint256);
    function increaseInReserves() external view returns(uint256);
    function decreaseInReserves() external view returns(uint256);

    function firstTake() external view returns(bool);
    function alreadyTaken(address) external view returns(bool);

    function lenderDepositTime(address lender, uint256 bucketIndex) external view returns(uint256);

    function getCollateralBuckets() external view returns(uint256[] memory);
}