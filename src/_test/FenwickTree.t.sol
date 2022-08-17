// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.14;

import { FenwickTree } from "../base/FenwickTree.sol";
import { DSTestPlus }  from "./utils/DSTestPlus.sol";

import { Maths } from "../libraries/Maths.sol";

contract FenwickTreeInstance is FenwickTree, DSTestPlus {

    uint256[] public inserts;

    function add(uint256 i_, uint256 x_) public {
        _add(i_, x_);
    }

    function remove(uint256 i_, uint256 x_) public {
        _remove(i_, x_);
    }

    function mult(uint256 i_, uint256 f_) public {
        _mult(i_, f_);
    }

    function numInserts() public returns (uint256) {
        return inserts.length;
    }

    function fillFenwickFuzzy(
        uint256 insertions_,
        uint256 amount_,
        bool trackInserts)
        external {

        uint256 i;
        uint256 amount;

        // Calculate total insertions 
        uint256 insertsDec = bound(insertions_, 1, 4000);

        // Calculate total amount to insert
        uint256 totalAmount = bound(amount_, 1 * 1e18, 9_000_000_000_000_000 * 1e18);
        uint256 totalAmountDec = totalAmount;

        while (totalAmountDec > 0 && insertsDec > 0) {

            // Insert at random index
            i = randomInRange(0, 8191);

            // If last iteration, insert remaining
            amount = insertsDec == 1 ? totalAmountDec : randomInRange(1, totalAmountDec, true);

            // Update values
            add(i, amount);
            totalAmountDec  -=  amount;
            insertsDec      -=  1;

            // Verify tree sum
            assertEq(_treeSum(), totalAmount - totalAmountDec);

            if (trackInserts)  inserts.push(i);
        }

        assertEq(_treeSum(), totalAmount);
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
    }

    function testFenwickScaledSum() external {
        FenwickTreeInstance tree = new FenwickTreeInstance();
        tree.add(5, 100 * 1e18);
        assertEq(tree.prefixSum(5),   100 * 1e18);
        assertEq(tree.prefixSum(6), 100 * 1e18);
        assertEq(tree.prefixSum(8), 100 * 1e18);
        assertEq(tree.prefixSum(8191), 100 * 1e18);

        tree.add(13, 200 * 1e18);
        tree.add(14, 200 * 1e18);

        assertEq(tree.prefixSum(5),   100 * 1e18);
        assertEq(tree.prefixSum(13), 300 * 1e18);
        assertEq(tree.prefixSum(14), 500 * 1e18);
        assertEq(tree.prefixSum(8191), 500 * 1e18);

        tree.mult(13, 2 * 1e18);

        assertEq(tree.prefixSum(5),   200 * 1e18);
        assertEq(tree.prefixSum(13), 600 * 1e18);
        assertEq(tree.prefixSum(14), 800 * 1e18);
        assertEq(tree.prefixSum(8191), 800 * 1e18);
    }

    function testFenwickUnscaledAddMult() external {
        FenwickTreeInstance tree = new FenwickTreeInstance();
        tree.add(7, 2 * 1e18);
        assertEq(tree.prefixSum(8191), 2 * 1e18);

        tree.add(8, 3.5 * 1e18);
        assertEq(tree.prefixSum(8191), 5.5 * 1e18);

        tree.add(15, 4 * 1e18);
        assertEq(tree.prefixSum(14), 5.5 * 1e18);

        tree.mult(13, 1.5 * 1e18);
        assertEq(tree.prefixSum(8191), 12.25 * 1e18);
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

    function testFenwickFuzzyScaling(
        uint256 insertions_,
        uint256 totalAmount_,
        uint256 scaleIndex_,
        uint256 factor_
        ) external {

        FenwickTreeInstance tree = new FenwickTreeInstance();
        tree.fillFenwickFuzzy(insertions_, totalAmount_, false);

        uint256 scaleIndex = bound(scaleIndex_, 2, 8191);
        uint256 subIndex = randomInRange(0, scaleIndex - 1);
        uint256 factor = bound(factor_, 1 * 1e18, 5 * 1e18);

        uint256 scaleIndexSum = tree.prefixSum(scaleIndex);
        uint256 subIndexSum = tree.prefixSum(subIndex);
        uint256 unScaledSum = tree.treeSum() - scaleIndexSum;

        tree.mult(scaleIndex, factor);

        assertEq(Maths.wmul(scaleIndexSum, factor), tree.prefixSum(scaleIndex));
        assertEq(Maths.wmul(subIndexSum, factor), tree.prefixSum(subIndex));
        assertEq(Maths.wmul(scaleIndexSum, factor), (tree.treeSum() - unScaledSum));
    }


    // TODO: check random parent to verify sum post removal
    function testFenwickFuzzyRemoval(
        uint256 insertions_,
        uint256 totalAmount_
        ) external {

        FenwickTreeInstance tree = new FenwickTreeInstance();
        tree.fillFenwickFuzzy(insertions_, totalAmount_, true);

        uint256 removalIndex = tree.inserts(randomInRange(0, tree.numInserts()));
        uint256 removalAmount = tree.get(removalIndex); 
        uint256 preRemovalIndexSum = tree.prefixSum(removalIndex); 
        uint256 preRemovalTreeSum = tree.treeSum(); 

        tree.remove(removalIndex, removalAmount);

        uint256 postRemovalIndexSum = tree.prefixSum(removalIndex); 

        assertEq(preRemovalIndexSum - removalAmount, postRemovalIndexSum);
        assertEq(preRemovalTreeSum - removalAmount, tree.treeSum());
    }

}
