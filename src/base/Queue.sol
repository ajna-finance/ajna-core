// SPDX-License-Identifier: MIT
pragma solidity 0.8.14;

import { IQueue } from "./interfaces/IQueue.sol";

abstract contract Queue is IQueue {

    address public override head;

    mapping(address => NodeInfo) internal queue;

    /************************/
    /***  Queue functions ***/
    /************************/

    /**
     *  @notice Called by borrower methods to update loan position.
     *  @param  borrower_        Borrower whose loan is being placed
     *  @param  val_  debt / collateralDeposited
     *  @param  newPrev_         Previous borrower that now comes before placed loan (new)
     */
    function _addAuction(address borrower_, uint256 val_, address newPrev_) internal {

        require(newPrev_ != borrower_, "Q:A:PNT_SELF_REF");
        require(val_ != 0, "Q:A:NV_EQ_0");
        require(queue[newPrev_].next == address(0), "Q:A:NPREV_NXT_NEQ_0");

        address curHead = head;
        NodeInfo memory node = queue[borrower_];

        if (curHead != address(0)) {
            // auction doesn't exist yet, other auctions in queue
            require(newPrev_          != address(0), "Q:A:WRG_PREV");
            NodeInfo storage tailNode = queue[newPrev_];
            require(tailNode.next     == address(0), "Q:A:WRG_PREV");

            node.val      = val_;
            node.active = true;
            tailNode.next = borrower_;
        } else {
            // first auction in queue
            require(newPrev_ == address(0), "Q:A:PREV_SHD_B_ZRO");

            head     = borrower_;
            node.val = val_;
            node.active = true;
        }

        // update loan with the new ordering
        queue[borrower_] = node;
    }

    /**
     *  @notice Removes a borrower from the loan queue and repairs the queue order.
     *  @dev    Called by _updateLoanQueue if borrower.debt == 0.
     *  @param  borrower_        Borrower whose loan is being placed in queue.
     */
    function _removeAuction(address borrower_) internal {
        queue[borrower_].active = false;
    }

    /**
     *  @notice Removes a borrower from the loan queue and repairs the queue order.
     *  @dev    Called by _updateLoanQueue if borrower.debt == 0.
     */
    function _removeAuctionHead() internal {
        NodeInfo memory headNode = queue[head];
        require(headNode.active == false, "Q:RH:AUCT_NOT_REM");
        address oldHead = head;
        head = headNode.next;
        delete queue[oldHead];
    }

    /**************************/
    /*** External Functions ***/
    /**************************/

    function getAuction(address borrower_) public view returns (uint256, address, bool) {
        NodeInfo memory node = queue[borrower_];
        return (node.val, node.next, node.active);
    }
}
