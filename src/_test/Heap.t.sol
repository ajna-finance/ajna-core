// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.14;

import { DSTestPlus }  from "./utils/DSTestPlus.sol";

import { Heap } from "../libraries/Heap.sol";
import "forge-std/console.sol";


contract TestPool is DSTestPlus {
    using Heap for Heap.Data;

    Heap.Data private _loansHeap;

    /**
     *  @notice used to track fuzzing test insertions.
     */
    address[] private inserts;

    constructor () {
        _loansHeap.init();
    }

    function getCount() public view returns (uint256) {
        return _loansHeap.count;
    }

    function numInserts() public view returns (uint256) {
        return inserts.length;
    }

    function getIdByInsertIndex(uint256 i_) public view returns (address) {
        return inserts[i_];
    }

    function upsertTp(address borrower_, uint256 tp_) public {
        _loansHeap.upsert(borrower_, tp_);
    }

    function removeTp(address borrower_) external {
        _loansHeap.remove(borrower_);
    }

    function getTp(address borrower_) public view returns (uint256) {
        return _loansHeap.getById(borrower_).val;
    }

    function getMaxTp() external view returns (uint256) {
        return _loansHeap.getMax().val;
    }

    function getMaxBorrower() external view returns (address) {
        return _loansHeap.getMax().id;
    }

    function getTotalTps() external view returns (uint256) {
        return _loansHeap.count;
    }


    /**
     *  @notice fills Heap with fuzzed values and tests additions.
     */
    function fuzzyFill(
        uint256 insertions_,
        bool trackInserts)
        external {

        uint256 tp;
        address borrower;

        // Calculate total insertions 
        uint256 totalInserts = bound(insertions_, 1000, 2000); 
        uint256 insertsDec = totalInserts;

        while (insertsDec > 0) {

            // build address and TP
            borrower = makeAddr(vm.toString(insertsDec));
            tp = randomInRange(99_836_282_890, 1_004_968_987.606512354182109771 * 10**18, true);

            // Insert TP
            upsertTp(borrower, tp);
            insertsDec  -=  1;

            // Verify amount of Heap TPs
            assertEq(_loansHeap.count - 1, totalInserts - insertsDec);
            assertEq(getTp(borrower), tp);

            if (trackInserts)  inserts.push(borrower);
        }

        assertEq(_loansHeap.count - 1, totalInserts);
    }
}

contract HeapTest is DSTestPlus {
    TestPool private _pool;

    function setUp() public {
       _pool = new TestPool();
    }

    function testHeapInsertAndRandomlyRemoveTps() public {
        // assert initial state
        assertEq(_pool.getMaxBorrower(), address(0));
        assertEq(_pool.getMaxTp(), 0);

        address b1 = makeAddr("b1");
        address b2 = makeAddr("b2");
        address b3 = makeAddr("b3");
        address b4 = makeAddr("b4");
        address b5 = makeAddr("b5");

        _pool.upsertTp(b1, 100 * 1e18);
        _pool.upsertTp(b5, 500 * 1e18);
        _pool.upsertTp(b2, 200 * 1e18);
        _pool.upsertTp(b4, 400 * 1e18);
        _pool.upsertTp(b3, 300 * 1e18);

        assertEq(_pool.getMaxTp(),       500 * 1e18);
        assertEq(_pool.getMaxBorrower(), b5);
        assertEq(_pool.getTotalTps(),    6);

        _pool.removeTp(b2);
        assertEq(_pool.getMaxTp(),       500 * 1e18);
        assertEq(_pool.getMaxBorrower(), b5);
        assertEq(_pool.getTotalTps(),    5);

        _pool.removeTp(b5);
        assertEq(_pool.getMaxTp(),       400 * 1e18);
        assertEq(_pool.getMaxBorrower(), b4);
        assertEq(_pool.getTotalTps(),    4);

        _pool.removeTp(b4);
        assertEq(_pool.getMaxBorrower(), b3);
        assertEq(_pool.getMaxTp(),       300 * 1e18);
        assertEq(_pool.getTotalTps(),    3);

        _pool.removeTp(b1);
        assertEq(_pool.getMaxBorrower(), b3);
        assertEq(_pool.getMaxTp(),       300 * 1e18);
        assertEq(_pool.getTotalTps(),    2);

        _pool.removeTp(b3);
        assertEq(_pool.getMaxBorrower(), address(0));
        assertEq(_pool.getMaxTp(),       0);
        assertEq(_pool.getTotalTps(),    1);
    }

    function testHeapInsertAndRemoveHeadByMaxTp() public {
        // assert initial state
        assertEq(_pool.getMaxBorrower(), address(0));
        assertEq(_pool.getMaxTp(), 0);

        address b1 = makeAddr("b1");
        address b2 = makeAddr("b2");
        address b3 = makeAddr("b3");
        address b4 = makeAddr("b4");
        address b5 = makeAddr("b5");

        _pool.upsertTp(b1, 100 * 1e18);
        _pool.upsertTp(b2, 200 * 1e18);
        _pool.upsertTp(b3, 300 * 1e18);
        _pool.upsertTp(b4, 400 * 1e18);
        _pool.upsertTp(b5, 500 * 1e18);

        assertEq(_pool.getMaxTp(),       500 * 1e18);
        assertEq(_pool.getMaxBorrower(), b5);
        assertEq(_pool.getTotalTps(),    6);

        _pool.removeTp(b5);
        assertEq(_pool.getMaxTp(),       400 * 1e18);
        assertEq(_pool.getMaxBorrower(), b4);
        assertEq(_pool.getTotalTps(),    5);

        _pool.removeTp(b4);
        assertEq(_pool.getMaxBorrower(), b3);
        assertEq(_pool.getMaxTp(),       300 * 1e18);
        assertEq(_pool.getTotalTps(),    4);

        _pool.removeTp(b3);
        assertEq(_pool.getMaxBorrower(), b2);
        assertEq(_pool.getMaxTp(),       200 * 1e18);
        assertEq(_pool.getTotalTps(),    3);

        _pool.removeTp(b2);
        assertEq(_pool.getMaxBorrower(), b1);
        assertEq(_pool.getMaxTp(),       100 * 1e18);
        assertEq(_pool.getTotalTps(),    2);

        _pool.removeTp(b1);
        assertEq(_pool.getMaxBorrower(), address(0));
        assertEq(_pool.getMaxTp(),       0);
        assertEq(_pool.getTotalTps(),    1);
    }

    function testHeapRemoveLastTp() public {
        // assert initial state
        assertEq(_pool.getMaxBorrower(), address(0));
        assertEq(_pool.getMaxTp(),       0);
        assertEq(_pool.getTotalTps(),    1);

        address b1 = makeAddr("b1");
        _pool.upsertTp(b1, 100 * 1e18);

        assertEq(_pool.getMaxBorrower(), b1);
        assertEq(_pool.getMaxTp(),       100 * 1e18);
        assertEq(_pool.getTotalTps(),    2);

        // remove last TP
        _pool.removeTp(b1);
        assertEq(_pool.getMaxBorrower(), address(0));
        assertEq(_pool.getMaxTp(),       0);
        assertEq(_pool.getTotalTps(),    1);
    }

    function testHeapUpdateTp() public {
        address b1 = makeAddr("b1");
        address b2 = makeAddr("b2");
        address b3 = makeAddr("b3");
        address b4 = makeAddr("b4");
        address b5 = makeAddr("b5");
        address b6 = makeAddr("b6");

        _pool.upsertTp(b1, 100 * 1e18);
        _pool.upsertTp(b2, 200 * 1e18);
        _pool.upsertTp(b3, 300 * 1e18);
        _pool.upsertTp(b4, 400 * 1e18);
        _pool.upsertTp(b5, 500 * 1e18);
        _pool.upsertTp(b6, 600 * 1e18);

        assertEq(_pool.getMaxTp(),       600 * 1e18);
        assertEq(_pool.getMaxBorrower(), b6);
        assertEq(_pool.getTotalTps(),    7);

        _pool.upsertTp(b4, 1_000 * 1e18);
        assertEq(_pool.getMaxTp(),       1_000 * 1e18);
        assertEq(_pool.getMaxBorrower(), b4);
        assertEq(_pool.getTotalTps(),    7);

        _pool.upsertTp(b4, 10 * 1e18);
        assertEq(_pool.getMaxTp(),       600 * 1e18);
        assertEq(_pool.getMaxBorrower(), b6);
        assertEq(_pool.getTotalTps(),    7);

        _pool.upsertTp(b6, 100 * 1e18);
        assertEq(_pool.getMaxTp(),       500 * 1e18);
        assertEq(_pool.getMaxBorrower(), b5);
        assertEq(_pool.getTotalTps(),    7);

        _pool.upsertTp(b6, 3_000 * 1e18);
        assertEq(_pool.getMaxTp(),       3_000 * 1e18);
        assertEq(_pool.getMaxBorrower(), b6);
        assertEq(_pool.getTotalTps(),    7);
    }

    function testHeapUpsertRequireChecks() public {
        address b1 = makeAddr("b1");
        vm.expectRevert("H:I:VAL_EQ_0");
        _pool.upsertTp(b1, 0);

        _pool.upsertTp(b1, 100 * 1e18);

        vm.expectRevert("H:I:VAL_EQ_0");
        _pool.upsertTp(b1, 0);
    }

    function testHeapFuzzy(uint256 inserts_) public {

        // test adding different TPs
        _pool.fuzzyFill(inserts_, true);

        // test adding different TPs
        address removeAddress = _pool.getIdByInsertIndex(randomInRange(1, _pool.numInserts() - 1, true));
        uint256 tp = _pool.getTp(removeAddress);
        uint256 length = _pool.getCount() - 1;

        _pool.removeTp(removeAddress);
        
        assertEq(length - 1, _pool.getCount() - 1);
        assertEq(_pool.getTp(removeAddress), 0);
        assertTrue(_pool.getTp(removeAddress) != tp);
    }

}
