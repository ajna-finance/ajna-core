// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.14;

import './DSTestPlus.sol';

import 'src/libraries/internal/Deposits.sol';

contract FenwickTreeInstance is DSTestPlus {
    using Deposits for DepositsState;

    DepositsState private deposits;

    /**
     *  @notice used to track fuzzing test insertions.
     */
    uint256[] private inserts;

    function numInserts() public view returns (uint256) {
        return inserts.length;
    }

    function getIByInsertIndex(uint256 i_) public view returns (uint256) {
        return inserts[i_];
    }

    function add(uint256 i_, uint256 x_) public {
        deposits.unscaledAdd(i_, Maths.wdiv(x_, deposits.scale(i_)));
    }

    function remove(uint256 i_, uint256 x_) public {
        deposits.unscaledRemove(i_, Maths.wdiv(x_, deposits.scale(i_)));
    }

    function mult(uint256 i_, uint256 f_) public {
        deposits.mult(i_, f_);
    }

    function treeSum() external view returns (uint256) {
        return deposits.treeSum();
    }

    function get(uint256 i_) external view returns (uint256 m_) {
        return deposits.valueAt(i_);
    }

    function scale(uint256 i_) external view returns (uint256 a_) {
        return deposits.scale(i_);
    }

    function findIndexOfSum(uint256 x_) external view returns (uint256 m_) {
        return deposits.findIndexOfSum(x_);
    }

    function prefixSum(uint256 i_) external view returns (uint256 s_) {
        return deposits.prefixSum(i_);
    }

    function obliterate(uint256 i_) public {
        uint256 deposit = deposits.unscaledValueAt(i_);
        deposits.unscaledRemove(i_, deposit);
    }

    function valueAt(uint256 i_) external view returns (uint256 s_) {
        return deposits.valueAt(i_);
    }

    /**
     *  @notice fills fenwick tree with fuzzed values and tests additions.
     */
    function fuzzyFill(
        uint256 insertions_,    // number of insertions to perform
        uint256 amount_,        // total amount to insert
        uint256 seed_,          // seed for psuedorandom number generator
        bool    trackInserts
    ) external {
        uint256 i;
        uint256 amount;
        uint256 cumulativeAmount;

        // Calculate total insertions 
        insertions_ = bound(insertions_, 1000, 2000);

        // Calculate total amount to insert
        amount_ = bound(amount_, 1 * 1e18, 9_000_000_000_000_000 * 1e18);

        // Initialize and print seed for randomness
        setRandomSeed(bound(seed_, 0, type(uint256).max - 1));

        while (amount_ > 0 && insertions_ > 0) {

            // Insert at random index
            i = randomInRange(1, MAX_FENWICK_INDEX);

            // If last iteration, insert remaining
            amount = insertions_ == 1 ? amount_ : (amount_ % insertions_) * randomInRange(1_000, 1 * 1e10, true);

            // Update values
            add(i, amount);
            amount_          -= amount;
            insertions_      -= 1;
            cumulativeAmount += amount;

            // Verify tree sum
            assertEq(deposits.treeSum(), cumulativeAmount);

            if (trackInserts)  inserts.push(i);
        }

        assertEq(deposits.treeSum(), cumulativeAmount);
    }

    /**
     *  @notice fills fenwick tree with deterministic values and tests additions.
     */
    function nonFuzzyFill(
        uint256 insertions_,    // number of insertions to perform
        uint256 amount_,        // total amount to insert
        uint256 seed_,          // seed for psuedorandom number generator
        bool    trackInserts
    ) external {
        uint256 i;
        uint256 amount;
        uint256 cumulativeAmount;

        // Initialize and print seed for randomness
        setRandomSeed(seed_);

        while (amount_ > 0 && insertions_ > 0) {

            // Insert at random index
            i = randomInRange(1, MAX_FENWICK_INDEX);

            // If last iteration, insert remaining
            amount = insertions_ == 1 ? amount_ : (amount_ % insertions_) * randomInRange(1_000, 1 * 1e10, true);

            // Update values
            add(i, amount);
            amount_          -= amount;
            insertions_      -= 1;
            cumulativeAmount += amount;

            // Verify tree sum
            assertEq(deposits.treeSum(), cumulativeAmount);

            if (trackInserts)  inserts.push(i);
        }

        assertEq(deposits.treeSum(), cumulativeAmount);
    }
}
