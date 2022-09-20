// SPDX-License-Identifier: MIT
pragma solidity 0.8.14;

import { IQueue } from "./interfaces/IQueue.sol";

abstract contract Queue is IQueue {

    address public override head;
    address internal tail;

    mapping(address => NodeInfo) internal queue;

    /************************/
    /***  Queue functions ***/
    /************************/

    /**
     *  @notice Called by borrower methods to update loan position.
     *  @param  borrower_        Borrower whose loan is being placed
     */
    function _addAuction(address borrower_) internal {

        NodeInfo memory node = queue[borrower_];

        if (head != address(0)) {
            // other auctions in queue, node doesn't exist or overwriting.
            NodeInfo storage tailNode = queue[tail];

            node.next     = address(0);
            node.active   = true;
            tailNode.next = borrower_;
        } else {
            // first auction in queue
            head        = borrower_;
            node.next   = address(0);
            node.active = true;
        }

        // update loan with the new ordering
        tail = borrower_;
        queue[borrower_] = node;
    }

    /**
     *  @notice Removes a borrower from the loan queue and repairs the queue order.
     *  @dev    Called by _updateLoanQueue if borrower.debt == 0.
     *  @param  borrower_        Borrower whose loan is being placed in queue.
     */
    function _deactivateAuction(address borrower_) internal {
        queue[borrower_].active = false;
    }

    /**
     *  @notice Removes a borrower from the loan queue and repairs the queue order.
     *  @dev    Called by _updateLoanQueue if borrower.debt == 0.
     */
    function _removeAuctionHead() internal {
        NodeInfo memory headNode = queue[head];
        require(headNode.active == false, "Q:RH:AUCT_NOT_DEACT");
        address oldHead = head;
        head = headNode.next;
        delete queue[oldHead];
    }

    /**************************/
    /*** External Functions ***/
    /**************************/

    function getAuction(address borrower_) public view returns (address, bool) {
        NodeInfo memory node = queue[borrower_];
        return (node.next, node.active);
    }
}
