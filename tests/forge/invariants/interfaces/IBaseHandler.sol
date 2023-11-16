// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.18;

interface IBaseHandler {

    function LENDER_MIN_BUCKET_INDEX() external view returns(uint256);
    function LENDER_MAX_BUCKET_INDEX() external view returns(uint256);

    function getActorsCount() external view returns(uint256);
    function actors(uint256) external view returns(address);

    function numberOfCalls(bytes memory) external view returns(uint256);
    function numberOfActions(bytes memory) external view returns(uint256);

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
 
    function borrowerPenalty() external view returns(uint256);
    function kickerReward() external view returns(uint256);

    function previousTotalBonds() external view returns(uint256);
    function increaseInBonds() external view returns(uint256);
    function decreaseInBonds() external view returns(uint256);
    
    function lenderDepositTime(address lender, uint256 bucketIndex) external view returns(uint256);

    function getBuckets() external view returns(uint256[] memory);
}