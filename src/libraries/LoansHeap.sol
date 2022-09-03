// SPDX-License-Identifier: MIT
pragma solidity 0.8.14;

library LoansHeap {
    uint256 public constant ROOT_INDEX = 1;

    struct Data{
      Node[] nodes;
      mapping (address => uint) indices;
    }

    struct Node{
      address borrower;
      uint256 tp;
    }

    function init(Data storage self) internal{
        self.nodes.push(Node(address(0),0));
    }

    function insert(Data storage self, address borrower, uint256 tp) internal returns(Node memory) {
        require(tp != 0, "B:U:TP_EQ_0");

        _extract(self, self.indices[borrower]);

        Node memory n = Node(borrower, tp);
        _bubbleUp(self, n, self.nodes.length);
        return n;
    }

    function extractMax(Data storage self) internal returns(Node memory) {
        return _extract(self, ROOT_INDEX);
    }

    function extractByBorrower(Data storage self, address borrower) internal returns(Node memory){
        return _extract(self, self.indices[borrower]);
    }

    function dump(Data storage self) internal view returns(Node[] memory) {
        return self.nodes;
    }

    function getByBorrower(Data storage self, address borrower) internal view returns(Node memory) {
        return getByIndex(self, self.indices[borrower]);//test that all these return the emptyNode
    }

    function getByIndex(Data storage self, uint i) internal view returns(Node memory) {
        return self.nodes.length > i ? self.nodes[i] : Node(address(0),0);
    }

    function getMax(Data storage self) internal view returns(Node memory) {
        return getByIndex(self, ROOT_INDEX);
    }

    function size(Data storage self) internal view returns(uint) {
        return self.nodes.length > 0 ? self.nodes.length-1 : 0;
    }

    function isNode(Node memory n) internal pure returns(bool) {
        return n.borrower != address(0);
    }

    function _extract(Data storage self, uint i) private returns(Node memory) {
        if (self.nodes.length <= i || i <= 0) return Node(address(0),0);

        Node memory extractedNode = self.nodes[i];
        delete self.indices[extractedNode.borrower];
        delete self.nodes[i];

        Node memory tailNode = self.nodes[self.nodes.length-1];

        if(i < self.nodes.length) { // if extracted node was not tail
          _bubbleUp(self, tailNode, i);
          _bubbleDown(self, self.nodes[i], i); // then try bubbling down
        }
        return extractedNode;
    }

    function _bubbleUp(Data storage self, Node memory n, uint i) private {
        if(i== ROOT_INDEX || n.tp <= self.nodes[i/2].tp) {
          _insert(self, n, i);
        } else{
          _insert(self, self.nodes[i/2], i);
          _bubbleUp(self, n, i/2);
        }
    }

    function _bubbleDown(Data storage self, Node memory n, uint i) private {
      uint256 length = self.nodes.length;
      uint256 cIndex = i*2;

      if(length <= cIndex) {
          _insert(self, n, i);
      } else{
          Node memory largestChild = self.nodes[cIndex];

          if(length > cIndex+1 && self.nodes[cIndex+1].tp > largestChild.tp ) {
            largestChild = self.nodes[++cIndex];
          }

          if(largestChild.tp <= n.tp) {
            _insert(self, n, i);
          } else{ 
            _insert(self, largestChild, i);
            _bubbleDown(self, n, cIndex);
          }
      }
    }

    function _insert(Data storage self, Node memory n, uint i) private{//√
      if(i == self.nodes.length) self.nodes.push(n);
      else self.nodes[i] = n;

      self.indices[n.borrower] = i;
    }
}