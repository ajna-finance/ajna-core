// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.14;

import { FenwickTree } from "../base/FenwickTree.sol";
import { DSTestPlus }  from "./utils/DSTestPlus.sol";

import { Maths } from "../libraries/Maths.sol";

contract FenwickTreeInstance is FenwickTree, DSTestPlus {

    function add(uint256 i_, uint256 x_) public {
        _add(i_, x_);
    }

    function mult(uint256 i_, uint256 f_) public {
        _mult(i_, f_);
    }

    function fillFenwickFuzzy(uint256 insertions_, uint256 amount_) external {
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
            insertsDec   -=  1;

            // Verify tree sum
            assertEq(_treeSum(), totalAmount - totalAmountDec);
        }

        assertEq(_treeSum(), totalAmount);
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
        tree.fillFenwickFuzzy(insertions_, totalAmount_);

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



    //function testFenwickFuzzy(uint256 index_, uint256 amount_) external {
    //    uint256 boundIndex   = bound(index_, 1, 8192);
    //    uint256 boundAmount  = bound(amount_, 1, 9_000_000_000_000_000 * 1e18);
    //    uint256 boundScaler  = bound(amount_, 1, 2 * 1e18);

    //    FenwickTreeInstance tree = new FenwickTreeInstance();

    //    // check adds work as expected
    //    tree.add(boundIndex, boundAmount);
    //    assertEq(tree.treeSum(),             boundAmount);
    //    assertEq(tree.prefixSum(boundIndex), boundAmount);

    //    if (boundIndex != 0) {
    //        assertEq(tree.get(boundIndex), boundAmount);
    //    }
    //    else {
    //        // can't find the rangeSum of the 0 index due to integer underflow
    //    }

    //    // check scaling of the tree
    //    // tree.mult(boundIndex, boundScaler);
    //    // assertEq(tree.treeSum(),             boundAmount);

    //    // TODO: dynamically add multiple indexes and check findSum
    //    // uint256 nextIndex = boundIndex > 0 ? boundIndex : boundIndex + 1;
    //    // assertEq(tree.get(boundIndex),      boundAmount);
    //    // assertEq(tree.findSum(2500 * 1e18), 8);
    //}

}
