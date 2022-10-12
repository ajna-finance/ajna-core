// SPDX-License-Identifier: MIT
pragma solidity 0.8.14;

library Heap {

    uint256 constant ROOT_INDEX = 1;

    struct Data {
        Node[] nodes;
        mapping (address => uint) indices; // unique id => node index
    }

    struct Node {
        address id;
        uint256 val;
    }

    /**
     *  @notice Initializes Max Heap.
     *  @dev    Organizes loans so Highest Threshold Price can be retreived easily.
     *  @param self_ Holds tree node data.
     */
    function init(Data storage self_) internal {
        require(self_.nodes.length == 0, "H:ALREADY_INIT");
        self_.nodes.push(Node(address(0),0));
    }

    /**
     *  @notice Performs an insert or an update dependent on borrowers existance.
     *  @param self_ Holds tree node data.
     *  @param id_   Id address that is being updated or inserted.
     *  @param val_  Value that is updated or inserted.
     */
    function upsert(Data storage self_, address id_, uint256 val_) internal {
        require(val_ != 0, "H:I:VAL_EQ_0");
        uint256 i = self_.indices[id_];

        // Node exists, update in place.
        if (i != 0) {
            Node memory currentNode = self_.nodes[i];
            if (currentNode.val > val_) {
                currentNode.val = val_;
                _bubbleDown(self_, currentNode, i);
            } else {
                currentNode.val = val_;
                _bubbleUp(self_, currentNode, i);
            }

        // New node, insert it
        } else { 
            _bubbleUp(self_, Node(id_, val_), self_.nodes.length);
        }
    }

    /**
     *  @notice Retreives Node by Id address.
     *  @param self_ Holds tree node data.
     *  @param id_   Id address that is being updated or inserted.
     *  @return Node Id's freshly updated or inserted Node.
     */
    function getById(Data storage self_, address id_) internal view returns(Node memory) {
        return getByIndex(self_, self_.indices[id_]);
    }

    /**
     *  @notice Retreives Node by index, i_.
     *  @param self_ Holds tree node data.
     *  @param i_    Index to retreive Node.
     *  @return Node Node revreived by index.
     */
    function getByIndex(Data storage self_, uint256 i_) internal view returns(Node memory) {
        return self_.nodes.length > i_ ? self_.nodes[i_] : Node(address(0),0);
    }

    /**
     *  @notice Retreives Node with the highest value, val in the Heap.
     *  @param self_ Holds tree node data.
     *  @return Node Max Node in the Heap.
     */
    function getMax(Data storage self_) internal view returns(Node memory) {
        return getByIndex(self_, ROOT_INDEX);
    }

    /**
     *  @notice Removes node at Id's index, id_, from Heap.
     *  @param self_ Holds tree node data.
     *  @param id_   Id's address whose Node is being updated or inserted.
     */
    function remove(Data storage self_, address id_) internal {
        uint256 i_ = self_.indices[id_];
        require(i_ != 0, "H:R:NO_ID");

        delete self_.indices[id_];
        uint256 tailIndex = self_.nodes.length - 1;
        if (i_ == tailIndex) self_.nodes.pop(); // we're removing the tail, pop without sorting
        else {
            Node memory tail = self_.nodes[tailIndex];
            self_.nodes.pop();            // remove tail node
            _bubbleUp(self_, tail, i_);
            _bubbleDown(self_, self_.nodes[i_], i_);
        }
    }

    /**
     *  @notice Moves a Node up the tree.
     *  @param self_ Holds tree node data.
     *  @param n_    Node to be moved.
     *  @param i_    index for Node to be moved to.
     */
    function _bubbleUp(Data storage self_, Node memory n_, uint i_) private {
        uint256 count = self_.nodes.length;
        if (i_ == ROOT_INDEX || n_.val <= self_.nodes[i_ / 2].val){
          _insert(self_, n_, i_, count);
        } else {
          _insert(self_, self_.nodes[i_ / 2], i_, count);
          _bubbleUp(self_, n_, i_ / 2);
        }
    }

    /**
     *  @notice Moves a Node down the tree.
     *  @param self_ Holds tree node data.
     *  @param n_    Node to be moved.
     *  @param i_    index for Node to be moved to.
     */
    function _bubbleDown(Data storage self_, Node memory n_, uint i_) private {
        // Left child index.
        uint cIndex = i_ * 2; 

        uint256 count = self_.nodes.length;
        if (count <= cIndex) {
            _insert(self_, n_, i_, count);
        } else {
            Node memory largestChild = self_.nodes[cIndex];

            if (count > cIndex + 1 && self_.nodes[cIndex + 1].val > largestChild.val) {
                largestChild = self_.nodes[++cIndex];
            }

            if (largestChild.val <= n_.val) {
              _insert(self_, n_, i_, count);
            } else {
              _insert(self_, largestChild, i_, count);
              _bubbleDown(self_, n_, cIndex);
            }
        }
    }

    /**
     *  @notice Inserts a Node in the tree.
     *  @param self_ Holds tree node data.
     *  @param n_    Node to be inserted.
     *  @param i_    index for Node to be inserted at.
     */
    function _insert(Data storage self_, Node memory n_, uint i_, uint256 count_) private {
        if (i_ == count_) self_.nodes.push(n_);
        else self_.nodes[i_] = n_;

        self_.indices[n_.id] = i_;
    }
}