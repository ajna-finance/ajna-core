// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.14;

import './utils/DSTestPlus.sol';
import './utils/HeapInstance.sol';

contract HeapTest is DSTestPlus {
    HeapInstance private _loans;

    function setUp() public {
       _loans = new HeapInstance();
    }

    function testHeapInsertAndRandomlyRemoveTps() public {
        // assert initial state
        assertEq(_loans.getMaxBorrower(), address(0));
        assertEq(_loans.getMaxTp(), 0);

        address b1 = makeAddr("b1");
        address b2 = makeAddr("b2");
        address b3 = makeAddr("b3");
        address b4 = makeAddr("b4");
        address b5 = makeAddr("b5");

        _loans.upsertTp(b1, 100 * 1e18);
        _loans.upsertTp(b5, 500 * 1e18);
        _loans.upsertTp(b2, 200 * 1e18);
        _loans.upsertTp(b4, 400 * 1e18);
        _loans.upsertTp(b3, 300 * 1e18);

        assertEq(_loans.getMaxTp(),       500 * 1e18);
        assertEq(_loans.getMaxBorrower(), b5);
        assertEq(_loans.getTotalTps(),    6);

        _loans.removeTp(b2);
        assertEq(_loans.getMaxTp(),       500 * 1e18);
        assertEq(_loans.getMaxBorrower(), b5);
        assertEq(_loans.getTotalTps(),    5);

        _loans.removeTp(b5);
        assertEq(_loans.getMaxTp(),       400 * 1e18);
        assertEq(_loans.getMaxBorrower(), b4);
        assertEq(_loans.getTotalTps(),    4);

        _loans.removeTp(b4);
        assertEq(_loans.getMaxBorrower(), b3);
        assertEq(_loans.getMaxTp(),       300 * 1e18);
        assertEq(_loans.getTotalTps(),    3);

        _loans.removeTp(b1);
        assertEq(_loans.getMaxBorrower(), b3);
        assertEq(_loans.getMaxTp(),       300 * 1e18);
        assertEq(_loans.getTotalTps(),    2);

        _loans.removeTp(b3);
        assertEq(_loans.getMaxBorrower(), address(0));
        assertEq(_loans.getMaxTp(),       0);
        assertEq(_loans.getTotalTps(),    1);
    }

    function testHeapInsertMultipleLoansWithSameTp() public {
        // assert initial state
        assertEq(_loans.getMaxBorrower(), address(0));
        assertEq(_loans.getMaxTp(), 0);

        address b1 = makeAddr("b1");
        address b2 = makeAddr("b2");
        address b3 = makeAddr("b3");
        address b4 = makeAddr("b4");
        address b5 = makeAddr("b5");
        address b6 = makeAddr("b6");

        _loans.upsertTp(b1, 100 * 1e18);
        _loans.upsertTp(b2, 200 * 1e18);
        _loans.upsertTp(b3, 200 * 1e18);
        _loans.upsertTp(b4, 300 * 1e18);
        _loans.upsertTp(b5, 400 * 1e18);
        _loans.upsertTp(b6, 400 * 1e18);

        assertEq(_loans.getMaxBorrower(), b5);
        assertEq(_loans.getMaxTp(),       400 * 1e18);
        assertEq(_loans.getTotalTps(),    7);

        assertEq(_loans.getTp(b1), 100 * 1e18);
        assertEq(_loans.getTp(b2), 200 * 1e18);
        assertEq(_loans.getTp(b3), 200 * 1e18);
        assertEq(_loans.getTp(b4), 300 * 1e18);
        assertEq(_loans.getTp(b5), 400 * 1e18);
        assertEq(_loans.getTp(b6), 400 * 1e18);

        _loans.removeTp(b5);
        assertEq(_loans.getMaxBorrower(), b6);
        assertEq(_loans.getMaxTp(),       400 * 1e18);
        assertEq(_loans.getTotalTps(),    6);

        _loans.removeTp(b6);
        assertEq(_loans.getMaxBorrower(), b4);
        assertEq(_loans.getMaxTp(),       300 * 1e18);
        assertEq(_loans.getTotalTps(),    5);

        _loans.removeTp(b4);
        assertEq(_loans.getMaxBorrower(), b2);
        assertEq(_loans.getMaxTp(),       200 * 1e18);
        assertEq(_loans.getTotalTps(),    4);

        _loans.upsertTp(b1, 200 * 1e18);
        assertEq(_loans.getMaxBorrower(), b2);
        assertEq(_loans.getMaxTp(),       200 * 1e18);
        assertEq(_loans.getTotalTps(),    4);

        _loans.removeTp(b2);
        assertEq(_loans.getMaxBorrower(), b3);
        assertEq(_loans.getMaxTp(),       200 * 1e18);
        assertEq(_loans.getTotalTps(),    3);

        _loans.removeTp(b3);
        assertEq(_loans.getMaxBorrower(), b1);
        assertEq(_loans.getMaxTp(),       200 * 1e18);
        assertEq(_loans.getTotalTps(),    2);

        _loans.removeTp(b1);
        assertEq(_loans.getMaxBorrower(), address(0));
        assertEq(_loans.getMaxTp(),       0);
        assertEq(_loans.getTotalTps(),    1);
    }

    function testHeapInsertAndRemoveHeadByMaxTp() public {
        // assert initial state
        assertEq(_loans.getMaxBorrower(), address(0));
        assertEq(_loans.getMaxTp(), 0);

        address b1 = makeAddr("b1");
        address b2 = makeAddr("b2");
        address b3 = makeAddr("b3");
        address b4 = makeAddr("b4");
        address b5 = makeAddr("b5");

        _loans.upsertTp(b1, 100 * 1e18);
        _loans.upsertTp(b2, 200 * 1e18);
        _loans.upsertTp(b3, 300 * 1e18);
        _loans.upsertTp(b4, 400 * 1e18);
        _loans.upsertTp(b5, 500 * 1e18);

        assertEq(_loans.getMaxTp(),       500 * 1e18);
        assertEq(_loans.getMaxBorrower(), b5);
        assertEq(_loans.getTotalTps(),    6);

        _loans.removeTp(b5);
        assertEq(_loans.getMaxTp(),       400 * 1e18);
        assertEq(_loans.getMaxBorrower(), b4);
        assertEq(_loans.getTotalTps(),    5);

        _loans.removeTp(b4);
        assertEq(_loans.getMaxBorrower(), b3);
        assertEq(_loans.getMaxTp(),       300 * 1e18);
        assertEq(_loans.getTotalTps(),    4);

        _loans.removeTp(b3);
        assertEq(_loans.getMaxBorrower(), b2);
        assertEq(_loans.getMaxTp(),       200 * 1e18);
        assertEq(_loans.getTotalTps(),    3);

        _loans.removeTp(b2);
        assertEq(_loans.getMaxBorrower(), b1);
        assertEq(_loans.getMaxTp(),       100 * 1e18);
        assertEq(_loans.getTotalTps(),    2);

        _loans.removeTp(b1);
        assertEq(_loans.getMaxBorrower(), address(0));
        assertEq(_loans.getMaxTp(),       0);
        assertEq(_loans.getTotalTps(),    1);
    }

    function testHeapRemoveLastTp() public {
        // assert initial state
        assertEq(_loans.getMaxBorrower(), address(0));
        assertEq(_loans.getMaxTp(),       0);
        assertEq(_loans.getTotalTps(),    1);

        address b1 = makeAddr("b1");
        _loans.upsertTp(b1, 100 * 1e18);

        assertEq(_loans.getMaxBorrower(), b1);
        assertEq(_loans.getMaxTp(),       100 * 1e18);
        assertEq(_loans.getTotalTps(),    2);

        // remove last TP
        _loans.removeTp(b1);
        assertEq(_loans.getMaxBorrower(), address(0));
        assertEq(_loans.getMaxTp(),       0);
        assertEq(_loans.getTotalTps(),    1);
    }

    function testHeapUpdateTp() public {
        address b1 = makeAddr("b1");
        address b2 = makeAddr("b2");
        address b3 = makeAddr("b3");
        address b4 = makeAddr("b4");
        address b5 = makeAddr("b5");
        address b6 = makeAddr("b6");

        _loans.upsertTp(b1, 100 * 1e18);
        _loans.upsertTp(b2, 200 * 1e18);
        _loans.upsertTp(b3, 300 * 1e18);
        _loans.upsertTp(b4, 400 * 1e18);
        _loans.upsertTp(b5, 500 * 1e18);
        _loans.upsertTp(b6, 600 * 1e18);

        assertEq(_loans.getMaxTp(),       600 * 1e18);
        assertEq(_loans.getMaxBorrower(), b6);
        assertEq(_loans.getTotalTps(),    7);

        _loans.upsertTp(b4, 1_000 * 1e18);
        assertEq(_loans.getMaxTp(),       1_000 * 1e18);
        assertEq(_loans.getMaxBorrower(), b4);
        assertEq(_loans.getTotalTps(),    7);

        _loans.upsertTp(b4, 10 * 1e18);
        assertEq(_loans.getMaxTp(),       600 * 1e18);
        assertEq(_loans.getMaxBorrower(), b6);
        assertEq(_loans.getTotalTps(),    7);

        _loans.upsertTp(b6, 100 * 1e18);
        assertEq(_loans.getMaxTp(),       500 * 1e18);
        assertEq(_loans.getMaxBorrower(), b5);
        assertEq(_loans.getTotalTps(),    7);

        _loans.upsertTp(b6, 3_000 * 1e18);
        assertEq(_loans.getMaxTp(),       3_000 * 1e18);
        assertEq(_loans.getMaxBorrower(), b6);
        assertEq(_loans.getTotalTps(),    7);
    }

    function testLoadHeapFuzzy(uint256 inserts_) public {

        // test adding different TPs
        _loans.fuzzyFill(inserts_, true);

        // test adding different TPs
        address removeAddress = _loans.getIdByInsertIndex(randomInRange(1, _loans.numInserts() - 1, true));
        uint256 tp = _loans.getTp(removeAddress);
        uint256 length = _loans.getCount() - 1;

        _loans.removeTp(removeAddress);
        
        assertEq(length - 1, _loans.getCount() - 1);
        assertEq(_loans.getTp(removeAddress), 0);
        assertTrue(_loans.getTp(removeAddress) != tp);
    }

    function testHeapBorrowRepayBorrow() public {
        address b1 = makeAddr("b1");

        _loans.upsertTp(b1, 300 * 1e18);
        assertEq(_loans.getMaxBorrower(), b1);
        assertEq(_loans.getMaxTp(),       300 * 1e18);
        assertEq(_loans.getTotalTps(),    2);

        _loans.removeTp(b1);
        assertEq(_loans.getMaxBorrower(), address(0));
        assertEq(_loans.getMaxTp(),       0);
        assertEq(_loans.getTotalTps(),    1);

        _loans.upsertTp(b1, 400 * 1e18);
        assertEq(_loans.getMaxBorrower(), b1);
        assertEq(_loans.getMaxTp(),       400 * 1e18);
        assertEq(_loans.getTotalTps(),    2);
    }

    function testHeapRemoveMiddleAndHead() public {
        address b1 = makeAddr("b1");
        address b2 = makeAddr("b2");
        address b3 = makeAddr("b3");
        address b4 = makeAddr("b4");
        address b5 = makeAddr("b5");
        address b6 = makeAddr("b6");
        address b7 = makeAddr("b7");

        _loans.upsertTp(b7, 7);
        _loans.upsertTp(b4, 4);
        _loans.upsertTp(b6, 6);
        _loans.upsertTp(b2, 2);
        _loans.upsertTp(b3, 3);
        _loans.upsertTp(b1, 1);
        _loans.upsertTp(b5, 5);
        assertEq(_loans.getMaxBorrower(), b7);
        assertEq(_loans.getMaxTp(),       7);
        assertEq(_loans.getTotalTps(),    8);

        _loans.removeTp(b2);
        assertEq(_loans.getMaxBorrower(), b7);
        assertEq(_loans.getMaxTp(),       7);
        assertEq(_loans.getTotalTps(),    7);

        _loans.removeTp(b7);
        assertEq(_loans.getMaxBorrower(), b6);
        assertEq(_loans.getMaxTp(),       6);
        assertEq(_loans.getTotalTps(),    6);

        _loans.removeTp(b6);
        assertEq(_loans.getMaxBorrower(), b5);
        assertEq(_loans.getMaxTp(),       5);
        assertEq(_loans.getTotalTps(),    5);
    }
}

contract HeapGasLoadTest is DSTestPlus {
    HeapInstance private _loans;
    address[] private _borrowers;
    uint256 private constant NODES_COUNT = 10_000;

    function setUp() public {
        _loans = new HeapInstance();
        for (uint256 i; i < NODES_COUNT; i++) {
                address borrower = makeAddr(vm.toString(i));
            _loans.upsertTp(borrower, 1 * 1e18 + i * 1e18);
            _borrowers.push(borrower);
        }
    }

    function testLoadHeapGasExerciseDeleteOnAllNodes() public {
        assertEq(_loans.getTotalTps(), NODES_COUNT + 1); // account node 0 too

        for (uint256 i; i < NODES_COUNT; i++) {
            uint256 snapshot = vm.snapshot();
            assertEq(_loans.getTotalTps(), NODES_COUNT + 1);

            _loans.removeTp(_borrowers[i]);

            assertEq(_loans.getTotalTps(), NODES_COUNT);
            vm.revertTo(snapshot);
        }

        assertEq(_loans.getTotalTps(), NODES_COUNT + 1);
    }

    function testLoadHeapGasExerciseUpsertOnAllNodes() public {
        assertEq(_loans.getTotalTps(), NODES_COUNT + 1); // account node 0 too

        for (uint256 i; i < NODES_COUNT; i++) {
            uint256 snapshot = vm.snapshot();
            assertEq(_loans.getTotalTps(), NODES_COUNT + 1);

            _loans.upsertTp(_borrowers[i], 1_000_000 * 1e18 + i * 1e18);

            assertEq(_loans.getTotalTps(), NODES_COUNT + 1);
            vm.revertTo(snapshot);
        }

        assertEq(_loans.getTotalTps(), NODES_COUNT + 1);
    }
}
