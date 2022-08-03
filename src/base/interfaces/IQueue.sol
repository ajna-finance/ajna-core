// SPDX-License-Identifier: MIT
pragma solidity 0.8.14;


interface IQueue {

    /***************/
    /*** Structs ***/
    /***************/

    struct LoanInfo {
        uint256 thresholdPrice;
        address next;
    }

    /**************************/
    /*** External Functions ***/
    /**************************/

    /**
     *  @notice Returns the thresholdPrice of loanQueueHead.
     *  @dev    If no loans in queue returns 0
     *  @return thresholdPrice         debt / collateralDeposited of loanQueueHead.
     */
    function getHighestThresholdPrice() external view returns (uint256 thresholdPrice);

    function loans(address borrower_) external view returns (uint256 thresholdprice, address next);

    function loanQueueHead() external view returns (address head_);

    /**
     *  @notice Looks up the threshold price and next pointer for a borrower.
     *  @dev    Used by SDK for offchain iteration through the queue.
     *  @return thresholdPrice, next
     */
    function loanInfo(address borrower_) external view returns (uint256, address);
}
