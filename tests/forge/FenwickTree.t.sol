// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.14;

import './utils/DSTestPlus.sol';
import './utils/FenwickTreeInstance.sol';

import 'src/libraries/internal/Maths.sol';

contract FenwickTreeTest is DSTestPlus {

    uint internal constant MAX_INDEX = 7388;

    FenwickTreeInstance private _tree;

    function setUp() public {
       _tree = new FenwickTreeInstance();
    }
    
    /**
     *  @notice Tests additions to tree.
     */
    function testFenwickUnscaled() external {
        _tree.add(11, 300 * 1e18);
        _tree.add(9,  200 * 1e18);

        assertEq(_tree.get(8),  0);
        assertEq(_tree.get(9),  200 * 1e18);
        assertEq(_tree.get(11), 300 * 1e18);
        assertEq(_tree.get(12), 0);
        assertEq(_tree.get(13), 0);

        assertEq(_tree.prefixSum(0),    0);
        assertEq(_tree.prefixSum(5),    0);
        assertEq(_tree.prefixSum(10),   200 * 1e18);
        assertEq(_tree.prefixSum(11),   500 * 1e18);
        assertEq(_tree.prefixSum(12),   500 * 1e18);
        assertEq(_tree.prefixSum(14),   500 * 1e18);
        assertEq(_tree.prefixSum(8191), 500 * 1e18);

        assertEq(_tree.treeSum(), 500 * 1e18);

        assertEq(_tree.findIndexOfSum(10 * 1e18),  9);
        assertEq(_tree.findIndexOfSum(200 * 1e18), 9);
        assertEq(_tree.findIndexOfSum(250 * 1e18), 11);
        assertEq(_tree.findIndexOfSum(500 * 1e18), 11);
        assertEq(_tree.findIndexOfSum(700 * 1e18), MAX_INDEX);
    }
    /**
     *  @notice Tests additions and scaling values in the tree.
     */
    function testFenwickScaled() external {
        _tree.add(5, 100 * 1e18);
        _tree.add(9, 200 * 1e18);
        _tree.mult(5, 1.1 * 1e18);
        _tree.add(11, 300 * 1e18);
        _tree.add(9, 200 * 1e18);
        _tree.mult(10, 1.2 * 1e18);

        assertEq(_tree.get(5),  132 * 1e18);
        assertEq(_tree.get(9),  480 * 1e18);
        assertEq(_tree.get(10), 0);
        assertEq(_tree.get(11), 300 * 1e18);

        assertEq(_tree.prefixSum(0),    0);
        assertEq(_tree.prefixSum(4),    0);
        assertEq(_tree.prefixSum(5),    132 * 1e18);
        assertEq(_tree.prefixSum(10),   612 * 1e18);
        assertEq(_tree.prefixSum(11),   912 * 1e18);
        assertEq(_tree.prefixSum(12),   912 * 1e18);
        assertEq(_tree.prefixSum(14),   912 * 1e18);
        assertEq(_tree.prefixSum(8191), 912 * 1e18);

        assertEq(_tree.treeSum(), 912 * 1e18);

        assertEq(_tree.findIndexOfSum(10 * 1e18),    5);
        assertEq(_tree.findIndexOfSum(100 * 1e18),   5);
        assertEq(_tree.findIndexOfSum(200 * 1e18),   9);
        assertEq(_tree.findIndexOfSum(350 * 1e18),   9);
        assertEq(_tree.findIndexOfSum(400 * 1e18),   9);
        assertEq(_tree.findIndexOfSum(500 * 1e18),   9);
        assertEq(_tree.findIndexOfSum(900 * 1e18),   11);
        assertEq(_tree.findIndexOfSum(1_000 * 1e18), MAX_INDEX);

        _tree.remove(11, 300 * 1e18);

        assertEq(_tree.treeSum(), 612 * 1e18);

        assertEq(_tree.findIndexOfSum(10 * 1e18),    5);
        assertEq(_tree.findIndexOfSum(100 * 1e18),   5);
        assertEq(_tree.findIndexOfSum(200 * 1e18),   9);
        assertEq(_tree.findIndexOfSum(350 * 1e18),   9);
        assertEq(_tree.findIndexOfSum(400 * 1e18),   9);
        assertEq(_tree.findIndexOfSum(500 * 1e18),   9);
        assertEq(_tree.findIndexOfSum(900 * 1e18),   MAX_INDEX);
        assertEq(_tree.findIndexOfSum(1_000 * 1e18), MAX_INDEX);

        assertEq(_tree.get(5),  132 * 1e18);
        assertEq(_tree.get(9),  480 * 1e18);
        assertEq(_tree.get(10), 0);
        assertEq(_tree.get(11), 0);

        _tree.obliterate(9);
        assertEq(_tree.get(9), 0);
    }

    /**
     *  @notice Fuzz tests additions and scaling values, testing prefixSum.
     */
    function testFenwickFuzzyScalingPrefix(
        uint256 insertions_,
        uint256 totalAmount_,
        uint256 scaleIndex_,
        uint256 factor_
        ) external {

        _tree.fuzzyFill(insertions_, totalAmount_, false);

        uint256 scaleIndex = bound(scaleIndex_, 2, MAX_INDEX);
        uint256 subIndex   = randomInRange(1, scaleIndex - 1);
        uint256 factor     = bound(factor_, 1 * 1e18, 5 * 1e18);

        uint256 scaleIndexSum = _tree.prefixSum(scaleIndex);
        uint256 subIndexSum   = _tree.prefixSum(subIndex);

        _tree.mult(scaleIndex, factor);

        uint256 max = Maths.max(Maths.wmul(scaleIndexSum, factor), _tree.prefixSum(scaleIndex));
        uint256 min = Maths.min(Maths.wmul(scaleIndexSum, factor), _tree.prefixSum(scaleIndex));

        uint256 subMax = Maths.max(Maths.wmul(subIndexSum, factor), _tree.prefixSum(subIndex));
        uint256 subMin = Maths.min(Maths.wmul(subIndexSum, factor), _tree.prefixSum(subIndex));

        // 3 >= scaling discrepency
        assertLe(max - min, 3);
        assertLe(subMax - subMin, 3);
    }

    function testFenwickRemovePrecision() external {
        _tree.add(   3_696, 2_000 * 1e18);
        _tree.add(   3_698, 5_000 * 1e18);
        _tree.add(   3_700, 11_000 * 1e18);
        _tree.add(   3_702, 25_000 * 1e18);
        _tree.add(   3_704, 30_000 * 1e18);
        _tree.mult(  3_701, 1.000054318968922188 * 1e18);
        _tree.obliterate(3_696);
        _tree.remove(3_700, 2_992.8 * 1e18);
        _tree.mult(  3_701, 1.000070411233491284 * 1e18);
        _tree.mult(  3_739, 1.000001510259590795 * 1e18);

        assertEq(_tree.valueAt(3_700), 8_008.373442262808824908 * 1e18);
        _tree.obliterate(3_700);
        assertEq(_tree.valueAt(3_700), 0);
    }

    /**
     *  @notice Fuzz tests additions and scaling values, testing findSum.
     */
    function testLoadFenwickFuzzyScalingFind(
        uint256 insertions_,
        uint256 totalAmount_,
        uint256 scaleIndex_,
        uint256 factor_
        ) external {

        _tree.fuzzyFill(insertions_, totalAmount_, false);

        uint256 scaleIndex = bound(scaleIndex_, 2, 7388);
        uint256 subIndex = randomInRange(0, scaleIndex - 1);
        uint256 factor = bound(factor_, 1 * 1e18, 5 * 1e18);

        _tree.mult(scaleIndex, factor);

        // This offset is done because of a rounding issue that occurs when we calculate the prefixSum
        uint256 treeDirectedIndex = _tree.findIndexOfSum(_tree.prefixSum(scaleIndex) + 1) - 1;
        uint256 treeDirectedSubIndex = _tree.findIndexOfSum(_tree.prefixSum(subIndex) + 1) - 1;

        uint256 max = Maths.max(_tree.prefixSum(treeDirectedIndex), _tree.prefixSum(scaleIndex));
        uint256 min = Maths.min(_tree.prefixSum(treeDirectedIndex), _tree.prefixSum(scaleIndex));

        uint256 subMax = Maths.max(_tree.prefixSum(treeDirectedSubIndex), _tree.prefixSum(subIndex));
        uint256 subMin = Maths.min(_tree.prefixSum(treeDirectedSubIndex), _tree.prefixSum(subIndex));

        // 2 >= scaling discrepency
        assertLe(max - min, 2);
        assertLe(subMax - subMin, 2);
    }

    /**
     *  @notice Fuzz tests additions and value removals.
     */
    function testLoadFenwickFuzzyRemoval(
        uint256 insertions_,
        uint256 totalAmount_
        ) external {

        _tree.fuzzyFill(insertions_, totalAmount_, true);

        // get Index randombly 
        uint256 removalIndex  = _tree.getIByInsertIndex(randomInRange(0, _tree.numInserts() - 1));
        uint256 removalAmount = _tree.get(removalIndex);
        uint256 parentIndex   = randomInRange(removalIndex + 1, MAX_INDEX);

        uint256 preRemovalParentIndexSum = _tree.prefixSum(parentIndex);
        uint256 preRemovalIndexSum       = _tree.prefixSum(removalIndex); 
        uint256 preRemovalTreeSum        = _tree.treeSum(); 

        _tree.remove(removalIndex, removalAmount);

        uint256 postRemovalIndexSum       = _tree.prefixSum(removalIndex); 
        uint256 postRemovalParentIndexSum = _tree.prefixSum(parentIndex); 

        assertEq(preRemovalIndexSum - removalAmount,       postRemovalIndexSum);
        assertEq(preRemovalTreeSum - removalAmount,        _tree.treeSum());
        assertEq(preRemovalParentIndexSum - removalAmount, postRemovalParentIndexSum);
    }

}

contract FenwickTreeGasLoadTest is DSTestPlus {
    FenwickTreeInstance private _tree;

    function setUp() public {
        _tree = new FenwickTreeInstance();
        for (uint256 i; i < MAX_FENWICK_INDEX; i++) {
            _tree.add(i, 100 * 1e18);
        }
    }

    function testLoadFenwickTreeGasExerciseDeleteOnAllDeposits() public {

        for (uint256 i; i < MAX_FENWICK_INDEX; i++) {
            uint256 snapshot = vm.snapshot();
            assertEq(_tree.treeSum(), MAX_FENWICK_INDEX * 100 * 1e18);

            _tree.remove(i, 100 * 1e18);

            assertEq(_tree.treeSum(), MAX_FENWICK_INDEX * 100 * 1e18 - 100 * 1e18);
            vm.revertTo(snapshot);
        }
    }

    function testLoadFenwickTreeGasExerciseAddOnAllDeposits() public {

        for (uint256 i; i < MAX_FENWICK_INDEX; i++) {
            uint256 snapshot = vm.snapshot();
            assertEq(_tree.treeSum(), MAX_FENWICK_INDEX * 100 * 1e18);

            _tree.add(i, 100 * 1e18);

            assertEq(_tree.treeSum(), MAX_FENWICK_INDEX * 100 * 1e18 + 100 * 1e18);
            vm.revertTo(snapshot);
        }
    }

    function testLoadFenwickTreeGasExercisefindIndexOfSumOnAllDeposits() public {
        for (uint256 i; i < MAX_FENWICK_INDEX; i++) {
            // 100 quote tokens are deposited into each bucket, and there are 7388 buckets.
            assertEq(_tree.findIndexOfSum(738_800 * 1e18 - i * 100 * 1e18), MAX_FENWICK_INDEX - i - 1);
        }
    }

    function testLoadFenwickTreeGasExerciseFindPrefixSumOnAllDeposits() public {
        for (uint256 i; i < MAX_FENWICK_INDEX; i++) {
            assertEq(_tree.prefixSum(i), 100 * 1e18 + i * 100 * 1e18);
        }
    }

    function testLoadFenwickTreeGasExerciseGetOnAllIndexes() public {
        for (uint256 i; i < MAX_FENWICK_INDEX; i++) {
            assertEq(_tree.get(i), 100 * 1e18);
        }
    }

    function testLoadFenwickTreeGasExerciseScaleOnAllDeposits() public {
        for (uint256 i; i < MAX_FENWICK_INDEX; i++) {
            uint256 snapshot = vm.snapshot();
            assertEq(_tree.treeSum(), MAX_FENWICK_INDEX * 100 * 1e18);

            _tree.mult(i, 100 * 1e18);
            _tree.scale(2);
            vm.revertTo(snapshot);
        }
    }
}
