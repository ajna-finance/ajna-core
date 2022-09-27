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
        require(node.active == false, "Q:RH:AUCT_ALRDY_EXISTS");

        if (head != address(0)) {
            // other auctions in queue, node doesn't exist or overwriting.
            NodeInfo storage tailNode = queue[tail];

            node.next     = address(0);
            node.active   = true;
            node.prev     = tail;
            tailNode.next = borrower_;
        } else {
            // first auction in queue
            head          = borrower_;
            node.next     = address(0);
            node.prev     = address(0);
            node.active   = true;
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
    function _removeAuction(address borrower_) internal {
        NodeInfo memory node = queue[borrower_];
        NodeInfo storage nextNode = queue[node.next];
        NodeInfo storage prevNode = queue[node.prev];

        require(node.active == true, "Q:RH:AUCT_NOT_DEACT");

        if (head == borrower_ && tail == borrower_) {
            // node is the head and tail
            head = address(0);
            tail = address(0);

        } else if(head == borrower_) {
            // node is the head
            nextNode.prev = address(0);
            head = node.next;

        } else if(tail == borrower_) {
            // node is the tail
            prevNode.next = address(0);
            tail = node.prev;

        } else {
            // node is in the middle
            prevNode.next = node.next;
            nextNode.prev = node.prev;
        }

        node.active = false;
        queue[borrower_] = node;
    }


    /**************************/
    /*** External Functions ***/
    /**************************/

    function getAuction(address borrower_) public view returns (address, address, bool) {
        NodeInfo memory node = queue[borrower_];
        return (node.next, node.prev, node.active);
    }
}
