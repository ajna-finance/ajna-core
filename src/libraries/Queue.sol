// SPDX-License-Identifier: MIT
pragma solidity 0.8.14;


library Queue {

    struct Data {
        address head;
        address tail;
        mapping(address => Node) nodes;
    }

    struct Node {
        address prev;
        address next;
        bool active;
    }



    /************************/
    /***  Queue functions ***/
    /************************/

    /**
     *  @notice Called by borrower methods to update loan position.
     *  @param  borrower_        Borrower whose loan is being placed
     */
    function add(Data storage self_, address borrower_) internal {

        Node memory node = self_.nodes[borrower_];
        require(node.active == false, "Q:A:AUCT_ALRDY_EXISTS");

        if (self_.head != address(0)) {
            // other auctions in queue, node doesn't exist or overwriting.
            Node storage tailNode = self_.nodes[self_.tail];

            node.next     = address(0);
            node.active   = true;
            node.prev     = self_.tail;
            tailNode.next = borrower_;
        } else {
            // first auction in queue
            self_.head          = borrower_;
            node.next     = address(0);
            node.prev     = address(0);
            node.active   = true;
        }

        // update loan with the new ordering
        self_.tail = borrower_;
        self_.nodes[borrower_] = node;
    }

    /**
     *  @notice Removes a borrower from the loan queue and repairs the queue order.
     *  @dev    Called by _updateLoanQueue if borrower.debt == 0.
     *  @param  borrower_        Borrower whose loan is being placed in queue.
     */
    function remove(Data storage self_, address borrower_) internal {
        Node memory  node     = self_.nodes[borrower_];
        Node storage nextNode = self_.nodes[node.next];
        Node storage prevNode = self_.nodes[node.prev];

        require(node.active == true, "Q:R:AUCT_NOT_DEACT");

        if (self_.head == borrower_ && self_.tail == borrower_) {
            // node is the head and tail
            self_.head = address(0);
            self_.tail = address(0);

        } else if(self_.head == borrower_) {
            // node is the head
            nextNode.prev = address(0);
            self_.head = node.next;

        } else if(self_.tail == borrower_) {
            // node is the tail
            prevNode.next = address(0);
            self_.tail = node.prev;

        } else {
            // node is in the middle
            prevNode.next = node.next;
            nextNode.prev = node.prev;
        }

        node.active = false;
        self_.nodes[borrower_] = node;
    }


    /**************************/
    /*** External Functions ***/
    /**************************/

    function getHead(Data storage self_) public view returns (address) {
        return self_.head;
    }

    function isActive(Data storage self_, address borrower_) public view returns (bool) {
        Node memory node = self_.nodes[borrower_];
        return node.active;
    }

    function get(Data storage self_, address borrower_) public view returns (address, address, bool) {
        Node memory node = self_.nodes[borrower_];
        return (node.next, node.prev, node.active);
    }
}
