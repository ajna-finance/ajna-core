// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.14;

import { DSTestPlus }  from "./utils/DSTestPlus.sol";

import { Heap } from "../libraries/Heap.sol";

contract TestPool {
    using Heap for Heap.Data;

    Heap.Data private _loansHeap;

    constructor () {
        _loansHeap.init();
    }

    function insertTp(address borrower_, uint256 tp_) external {
        _loansHeap.upsert(borrower_, tp_);
    }

    function deleteTp(address borrower_) external {
        _loansHeap.remove(borrower_);
    }

    function getTp(address borrower_) external view returns (uint256) {
        return _loansHeap.getById(borrower_).val;
    }

    function getMaxTp() external view returns (uint256) {
        return _loansHeap.getMax().val;
    }

    function getMaxBorrower() external view returns (address) {
        return _loansHeap.getMax().id;
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

        _pool.insertTp(b1, 100 * 1e18);
        _pool.insertTp(b5, 500 * 1e18);
        _pool.insertTp(b2, 200 * 1e18);
        _pool.insertTp(b4, 400 * 1e18);
        _pool.insertTp(b3, 300 * 1e18);

        assertEq(_pool.getMaxTp(), 500 * 1e18);
        assertEq(_pool.getMaxBorrower(), b5);

        _pool.deleteTp(b2);
        assertEq(_pool.getMaxTp(), 500 * 1e18);
        assertEq(_pool.getMaxBorrower(), b5);

        _pool.deleteTp(b5);
        assertEq(_pool.getMaxTp(), 400 * 1e18);
        assertEq(_pool.getMaxBorrower(), b4);

        _pool.deleteTp(b4);
        assertEq(_pool.getMaxBorrower(), b3);
        assertEq(_pool.getMaxTp(), 300 * 1e18);

        _pool.deleteTp(b1);
        assertEq(_pool.getMaxBorrower(), b3);
        assertEq(_pool.getMaxTp(), 300 * 1e18);

        _pool.deleteTp(b3);
        assertEq(_pool.getMaxBorrower(), address(0));
        assertEq(_pool.getMaxTp(), 0);
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

        _pool.insertTp(b1, 100 * 1e18);
        _pool.insertTp(b2, 200 * 1e18);
        _pool.insertTp(b3, 300 * 1e18);
        _pool.insertTp(b4, 400 * 1e18);
        _pool.insertTp(b5, 500 * 1e18);

        assertEq(_pool.getMaxTp(), 500 * 1e18);
        assertEq(_pool.getMaxBorrower(), b5);

        _pool.deleteTp(b5);
        assertEq(_pool.getMaxTp(), 400 * 1e18);
        assertEq(_pool.getMaxBorrower(), b4);

        _pool.deleteTp(b4);
        assertEq(_pool.getMaxBorrower(), b3);
        assertEq(_pool.getMaxTp(), 300 * 1e18);

        _pool.deleteTp(b3);
        assertEq(_pool.getMaxBorrower(), b2);
        assertEq(_pool.getMaxTp(), 200 * 1e18);

        _pool.deleteTp(b2);
        assertEq(_pool.getMaxBorrower(), b1);
        assertEq(_pool.getMaxTp(), 100 * 1e18);

        _pool.deleteTp(b1);
        assertEq(_pool.getMaxBorrower(), address(0));
        assertEq(_pool.getMaxTp(), 0);
    }

    function testHeapInsertAndRemoveHeadByAddress() public {
        // assert initial state
        assertEq(_pool.getMaxBorrower(), address(0));
        assertEq(_pool.getMaxTp(), 0);

        address b1 = makeAddr("b1");
        address b2 = makeAddr("b2");
        address b3 = makeAddr("b3");
        address b4 = makeAddr("b4");
        address b5 = makeAddr("b5");

        _pool.insertTp(b1, 100 * 1e18);
        _pool.insertTp(b2, 200 * 1e18);
        _pool.insertTp(b3, 300 * 1e18);
        _pool.insertTp(b4, 400 * 1e18);
        _pool.insertTp(b5, 500 * 1e18);

        assertEq(_pool.getMaxTp(), 500 * 1e18);
        assertEq(_pool.getMaxBorrower(), b5);

        _pool.deleteTp(b5);
        assertEq(_pool.getMaxTp(), 400 * 1e18);
        assertEq(_pool.getMaxBorrower(), b4);

        _pool.deleteTp(b4);
        assertEq(_pool.getMaxBorrower(), b3);
        assertEq(_pool.getMaxTp(), 300 * 1e18);

        _pool.deleteTp(b3);
        assertEq(_pool.getMaxBorrower(), b2);
        assertEq(_pool.getMaxTp(), 200 * 1e18);

        _pool.deleteTp(b2);
        assertEq(_pool.getMaxBorrower(), b1);
        assertEq(_pool.getMaxTp(), 100 * 1e18);

        _pool.deleteTp(b1);
        assertEq(_pool.getMaxBorrower(), address(0));
        assertEq(_pool.getMaxTp(), 0);
    }

    function testHeapRemoveLastTp() public {
        // assert initial state
        assertEq(_pool.getMaxBorrower(), address(0));
        assertEq(_pool.getMaxTp(), 0);

        address b1 = makeAddr("b1");
        _pool.insertTp(b1, 100 * 1e18);

        assertEq(_pool.getMaxBorrower(), b1);
        assertEq(_pool.getMaxTp(), 100 * 1e18);

        // remove last TP
        _pool.deleteTp(b1);
        assertEq(_pool.getMaxBorrower(), address(0));
        assertEq(_pool.getMaxTp(), 0);
    }

    function testHeapUpdateTps() public {
        // TODO
    }

}
