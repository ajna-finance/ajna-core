
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

    function updateLoanQueue(address borrower_, uint256 thresholdPrice_, address oldPrev_, address newPrev_, uint256 radius_) external;

    function removeLoanQueue(address borrower_, address oldPrev_) external;
    
}