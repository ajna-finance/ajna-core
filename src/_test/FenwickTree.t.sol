// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.14;

import { FenwickTree } from "../base/FenwickTree.sol";
import { DSTestPlus }  from "./utils/DSTestPlus.sol";

import { Maths } from "../libraries/Maths.sol";

contract FenwickTreeInstance is FenwickTree {

    function add(uint256 i_, uint256 x_) public {
        _add(i_, x_);
    }

    function remove(uint256 i_, uint256 x_) public {
        _remove(i_, x_);
    }

    function mult(uint256 i_, uint256 f_) public {
        _mult(i_, f_);
    }

    function treeSum() external view returns (uint256) {
        return _treeSum();
    }

    function get(uint256 i_) external view returns (uint256 m_) {
        return _rangeSum(i_, i_);
    }

    function scale(uint256 i_) external view returns (uint256 a_) {
        return _scale(i_);
    }

    function findSum(uint256 x_) external view returns (uint256 m_) {
        return _findSum(x_);
    }

    function prefixSum(uint256 i_) external view returns (uint256 s_) {
        return _prefixSum(i_);
    }
}

contract FenwickTreeTest is DSTestPlus {

    function testFenwickUnscaled() external {
        FenwickTreeInstance tree = new FenwickTreeInstance();
        tree.add(11, 300 * 1e18);
        tree.add(9,  200 * 1e18);
        assertEq(tree.get(8),  0);
        assertEq(tree.get(9),  200 * 1e18);
        assertEq(tree.get(11), 300 * 1e18);
        assertEq(tree.get(12), 0);
        assertEq(tree.get(13), 0);

        assertEq(tree.prefixSum(0),    0);
        assertEq(tree.prefixSum(5),    0);
        assertEq(tree.prefixSum(10),   200 * 1e18);
        assertEq(tree.prefixSum(11),   500 * 1e18);
        assertEq(tree.prefixSum(12),   500 * 1e18);
        assertEq(tree.prefixSum(14),   500 * 1e18);
        assertEq(tree.prefixSum(8191), 500 * 1e18);

        assertEq(tree.treeSum(), 500 * 1e18);

        assertEq(tree.findSum(10 * 1e18),  9);
        assertEq(tree.findSum(200 * 1e18), 9);
        assertEq(tree.findSum(250 * 1e18), 11);
        assertEq(tree.findSum(500 * 1e18), 11);
        assertEq(tree.findSum(700 * 1e18), 8191);
    }

   function testFenwickScaled() external {
        FenwickTreeInstance tree = new FenwickTreeInstance();
        tree.add(5, 100 * 1e18);
        tree.add(9, 200 * 1e18);
        tree.mult(5, 1.1 * 1e18);
        tree.add(11, 300 * 1e18);
        tree.add(9, 200 * 1e18);
        tree.mult(10, 1.2 * 1e18);

        assertEq(tree.prefixSum(0),    0);
        assertEq(tree.prefixSum(4),    0);
        assertEq(tree.prefixSum(5),    132 * 1e18);
        assertEq(tree.prefixSum(10),   612 * 1e18);
        assertEq(tree.prefixSum(11),   912 * 1e18);
        assertEq(tree.prefixSum(12),   912 * 1e18);
        assertEq(tree.prefixSum(14),   912 * 1e18);
        assertEq(tree.prefixSum(8191), 912 * 1e18);

        assertEq(tree.treeSum(), 912 * 1e18);

        assertEq(tree.findSum(10 * 1e18),    5);
        assertEq(tree.findSum(100 * 1e18),   5);
        assertEq(tree.findSum(200 * 1e18),   9);
        assertEq(tree.findSum(350 * 1e18),   9);
        assertEq(tree.findSum(400 * 1e18),   9);
        assertEq(tree.findSum(500 * 1e18),   9);
        assertEq(tree.findSum(900 * 1e18),   11);
        assertEq(tree.findSum(1_000 * 1e18), 8191);

        tree.remove(11, 300 * 1e18);

        assertEq(tree.treeSum(), 612 * 1e18);

        assertEq(tree.findSum(10 * 1e18),    5);
        assertEq(tree.findSum(100 * 1e18),   5);
        assertEq(tree.findSum(200 * 1e18),   9);
        assertEq(tree.findSum(350 * 1e18),   9);
        assertEq(tree.findSum(400 * 1e18),   9);
        assertEq(tree.findSum(500 * 1e18),   9);
        assertEq(tree.findSum(900 * 1e18),   8191);
        assertEq(tree.findSum(1_000 * 1e18), 8191);
    }

    function testFenwickFirstBorrow() external {
        FenwickTreeInstance tree = new FenwickTreeInstance();
        tree.add(8, 6000 * 1e18);
        assertEq(tree.treeSum(),            6000 * 1e18);
        assertEq(tree.findSum(2500 * 1e18), 8);

        tree.add(4, 2000 * 1e18);
        assertEq(tree.treeSum(),            8000 * 1e18);
        assertEq(tree.findSum(2500 * 1e18), 8);

        tree.add(5, 10000 * 1e18);
        assertEq(tree.treeSum(),            18_000 * 1e18);
        assertEq(tree.findSum(2500 * 1e18), 5);
    }

}
