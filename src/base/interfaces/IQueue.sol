// SPDX-License-Identifier: MIT
pragma solidity 0.8.14;


interface IQueue {

    /***************/
    /*** Structs ***/
    /***************/

    struct NodeInfo {
        uint256 val;
        address next;
        bool removed;
    }

    /**************************/
    /*** External Functions ***/
    /**************************/

    function head() external view returns (address head_);

    /**
     *  @notice Looks up the threshold price and next pointer for a borrower.
     *  @dev    Used by SDK for offchain iteration through the queue.
     *  @return thresholdPrice, next
     */
    function getAuction(address borrower_) external view returns (uint256, address, bool);
}