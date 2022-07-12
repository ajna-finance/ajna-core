
// SPDX-License-Identifier: MIT
pragma solidity 0.8.14;


interface IQueue {

    struct LoanInfo {
        uint256 thresholdPrice;
        address next;
    }

    function loans(address borrower_) external view returns (uint256 thresholdprice, address next);

    function head() external view returns (address head_);

    /***********************************/
    /*** Queue Functions ***/
    /***********************************/

    function getHighestThresholdPrice() external view returns (uint256 thresholdPrice);
 
}