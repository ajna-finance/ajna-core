// SPDX-License-Identifier: MIT
pragma solidity 0.8.14;

/**
 * @title Fenwick Tree
 * @dev   Used to efficiently track and retrieve lender and borrower positions in a pool.
 * @dev   Nodes in the tree are equivalent to price buckets.
 */
interface IFenwickTree {

    /***********************/
    /*** State Variables ***/
    /***********************/

    /**
     *  @notice Returns the `SIZE` constant, equivalent to the maximum number of price indices in the pool.
     *  @return The maximum price constant.
     */
    function SIZE() external view returns (uint256);

    /**********************/
    /*** View Functions ***/
    /**********************/

    /**
     *  @notice Calculate the number of indices that need to be traversed to return a given sum.
     *  @dev    This will return SIZE if there is insufficient value in the tree.
     *  @param  x_  The sum to query for.
     *  @return m_  The index in the tree which contains the desired value. 
     */    
    function findSum(uint256 x_) external view returns (uint256 m_);

    /**
     *  @notice Returns the value of a given node.
     *  @param  i_ The index of the node to calculate the sum of.
     *  @return m_ The node value. 
     */
    function get(uint256 i_) external view returns (uint256 m_);

    /**
     *  @notice Returns the least significant bit (LSB) of a price index.
     *  @dev    Can be used to calculate the index of a given node's parent.
     *  @param i_   The index to calculate the LSB of.
     *  @return     The least significant bit. 
     */
    function lsb(uint256 i_) external view returns (uint256);

    /**
     *  @notice Returns the accumulated sum of a sequence of nodes up to a given node.
     *  @dev Starts at the tree root and decremnts through nodes until the given index, i_, is reached.
     *  @param  i_  The final index in the sequence.
     *  @return s_  The sum of the sequence. 
     */
    function prefixSum(uint256 i_) external view returns (uint256 s_);

    /**
     *  @notice Returns the scaled sum of a sequence of nodes from a given index to the max index.
     *  @dev    Starts at the given index, and ends at 8192.
     *  @param  i_  The starting index in the sequence. 
     *  @return a_  The scaled sum of the sequence. 
     */
    function scale(uint256 i_) external view returns (uint256 a_);

    /**
     *  @notice Returns the sum of all nodes in a tree.
     */
    function treeSum() external view returns (uint256);

}
