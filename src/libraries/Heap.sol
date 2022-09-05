// SPDX-License-Identifier: MIT
pragma solidity 0.8.14;

library Heap {

    uint256 constant ROOT_INDEX = 1;

    struct Data {
        uint256 count;
        Node[] nodes;
        mapping (address => uint) indices; // unique id => node index
    }

    struct Node {
      address id;
      uint256 val;
    }

    function init(Data storage self) internal {
        require(self.count == 0, "H:ALREADY_INIT");
        self.nodes.push(Node(address(0),0));
        self.count++;
    }

    function upsert(Data storage self_, address id_, uint256 val_) internal returns(Node memory n_) {
        require(val_ != 0, "H:I:VAL_EQ_0");
        uint256 i = self_.indices[id_];
        if (i != 0) { // node exists, update in place
            Node memory currentNode = self_.nodes[i];
            if (currentNode.val > val_) {
                currentNode.val = val_;
                _bubbleDown(self_, currentNode, i);
            } else {
                currentNode.val = val_;
                _bubbleUp(self_, currentNode, i);
            }
        } else { // new node, insert it
            n_ = Node(id_, val_);
            _bubbleUp(self_, n_, self_.count);
            self_.count++;
        }
    }

    function removeMax(Data storage self_) internal returns(Node memory) {
        return _extract(self_, ROOT_INDEX);
    }

    function remove(Data storage self, address id_) internal returns(Node memory) {
        return _extract(self, self.indices[id_]);
    }

    function getById(Data storage self_, address id_) internal view returns(Node memory) {
        return getByIndex(self_, self_.indices[id_]);
    }

    function getByIndex(Data storage self_, uint i_) internal view returns(Node memory) {
        return self_.count > i_ ? self_.nodes[i_] : Node(address(0),0);
    }

    function getMax(Data storage self_) internal view returns(Node memory){
        return getByIndex(self_, ROOT_INDEX);
    }

    //private
    function _extract(Data storage self_, uint i_) private returns(Node memory extractedNode_) {
        if (self_.count <= i_ || i_ <= 0) return Node(address(0),0);

        extractedNode_ = self_.nodes[i_];
        delete self_.indices[extractedNode_.id];
        delete self_.nodes[i_];
        uint256 curCount = self_.count - 1;

        Node memory tailNode = self_.nodes[curCount];
        if (i_ < curCount){ // if extracted node was not tail
            _bubbleUp(self_, tailNode, i_);
            _bubbleDown(self_, self_.nodes[i_], i_); // then try bubbling down
        }
        self_.count = curCount;
    }

    function _bubbleUp(Data storage self_, Node memory n_, uint i_) private {
        if (i_ == ROOT_INDEX || n_.val <= self_.nodes[i_/2].val){
          _insert(self_, n_, i_);
        } else {
          _insert(self_, self_.nodes[i_/2], i_);
          _bubbleUp(self_, n_, i_/2);
        }
    }

    function _bubbleDown(Data storage self_, Node memory n_, uint i_) private {
        uint256 length = self_.count;
        uint cIndex = i_ * 2; // left child index

        if (length <= cIndex) {
            _insert(self_, n_, i_);
        } else {
            Node memory largestChild = self_.nodes[cIndex];

            if (length > cIndex+1 && self_.nodes[cIndex+1].val > largestChild.val) {
                largestChild = self_.nodes[++cIndex];
            }

            if (largestChild.val <= n_.val) {
              _insert(self_, n_, i_);
            } else {
              _insert(self_, largestChild, i_);
              _bubbleDown(self_, n_, cIndex);
            }
        }
    }

    function _insert(Data storage self_, Node memory n_, uint i_) private {
        if (i_ == self_.nodes.length) self_.nodes.push(n_);
        else self_.nodes[i_] = n_;

        self_.indices[n_.id] = i_;
    }
}