// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity 0.8.14;

import './DSTestPlus.sol';

contract HeapInstance is DSTestPlus {
    using Heap for Heap.Data;

    Heap.Data private _heap;

    /**
     *  @notice used to track fuzzing test insertions.
     */
    address[] private inserts;

    constructor () {
        _heap.init();
    }

    function getCount() public view returns (uint256) {
        return _heap.nodes.length;
    }

    function numInserts() public view returns (uint256) {
        return inserts.length;
    }

    function getIdByInsertIndex(uint256 i_) public view returns (address) {
        return inserts[i_];
    }

    function upsertTp(address borrower_, uint256 tp_) public {
        _heap.upsert(borrower_, tp_);
    }

    function removeTp(address borrower_) external {
        _heap.remove(borrower_);
    }

    function getTp(address borrower_) public view returns (uint256) {
        return _heap.getById(borrower_).val;
    }

    function getMaxTp() external view returns (uint256) {
        return _heap.getMax().val;
    }

    function getMaxBorrower() external view returns (address) {
        return _heap.getMax().id;
    }

    function getTotalTps() external view returns (uint256) {
        return _heap.nodes.length;
    }


    /**
     *  @notice fills Heap with fuzzed values and tests additions.
     */
    function fuzzyFill(
        uint256 inserts_,
        bool trackInserts_)
        external {

        uint256 tp;
        address borrower;

        // Calculate total insertions 
        uint256 totalInserts = bound(inserts_, 1000, 2000);
        uint256 insertsDec = totalInserts;

        while (insertsDec > 0) {

            // build address and TP
            borrower = makeAddr(vm.toString(insertsDec));
            tp = randomInRange(99_836_282_890, 1_004_968_987.606512354182109771 * 10**18, true);

            // Insert TP
            upsertTp(borrower, tp);
            insertsDec  -=  1;

            // Verify amount of Heap TPs
            assertEq(_heap.nodes.length - 1, totalInserts - insertsDec);
            assertEq(getTp(borrower), tp);

            if (trackInserts_)  inserts.push(borrower);
        }

        assertEq(_heap.nodes.length - 1, totalInserts);
    }
}

