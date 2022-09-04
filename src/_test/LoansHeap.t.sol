// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.14;

import { DSTestPlus }  from "./utils/DSTestPlus.sol";

import { LoansHeap } from "../libraries/LoansHeap.sol";

contract TestPool {
    using LoansHeap for LoansHeap.Data;

    LoansHeap.Data private _loansHeap;

    constructor () {
        _loansHeap.init();
    }

    function insertTp(address borrower, uint256 tp) external {
        // _loansHeap.extractByBorrower(borrower);
        _loansHeap.insert(borrower, tp);
    }

    function deleteTp(address borrower) external returns (LoansHeap.Node memory) {
        return _loansHeap.extractByBorrower(borrower);
    }

    function deleteMaxTp() external {
        _loansHeap.extractMax();
    }

    function getTp(address borrower) external view returns (uint256) {
        return _loansHeap.getByBorrower(borrower).tp;
    }

    function getMaxTp() external view returns (uint256) {
        return _loansHeap.getMax().tp;
    }

    function getMaxBorrower() external view returns (address) {
        return _loansHeap.getMax().borrower;
    }

}

contract LoansHeapTest is DSTestPlus {
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

        _pool.deleteMaxTp();
        assertEq(_pool.getMaxTp(), 400 * 1e18);
        assertEq(_pool.getMaxBorrower(), b4);

        _pool.deleteMaxTp();
        assertEq(_pool.getMaxBorrower(), b3);
        assertEq(_pool.getMaxTp(), 300 * 1e18);

        _pool.deleteMaxTp();
        assertEq(_pool.getMaxBorrower(), b2);
        assertEq(_pool.getMaxTp(), 200 * 1e18);

        _pool.deleteMaxTp();
        assertEq(_pool.getMaxBorrower(), b1);
        assertEq(_pool.getMaxTp(), 100 * 1e18);

        _pool.deleteMaxTp();
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
