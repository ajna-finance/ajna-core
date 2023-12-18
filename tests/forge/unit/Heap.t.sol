// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.18;

import '../utils/DSTestPlus.sol';
import '../utils/HeapInstance.sol';

contract HeapTest is DSTestPlus {
    HeapInstance private _loans;

    function setUp() public {
       _loans = new HeapInstance();
    }

    function testHeapInsertAndRandomlyRemoveTps() public {
        // assert initial state
        assertEq(_loans.getMaxBorrower(), address(0));
        assertEq(_loans.getMaxT0DebtToCollateral(), 0);

        address b1 = makeAddr("b1");
        address b2 = makeAddr("b2");
        address b3 = makeAddr("b3");
        address b4 = makeAddr("b4");
        address b5 = makeAddr("b5");

        _loans.upsertT0DebtToCollateral(b1, 100 * 1e18);
        _loans.upsertT0DebtToCollateral(b5, 500 * 1e18);
        _loans.upsertT0DebtToCollateral(b2, 200 * 1e18);
        _loans.upsertT0DebtToCollateral(b4, 400 * 1e18);
        _loans.upsertT0DebtToCollateral(b3, 300 * 1e18);

        assertEq(_loans.getMaxT0DebtToCollateral(),       500 * 1e18);
        assertEq(_loans.getMaxBorrower(), b5);
        assertEq(_loans.getTotalT0DebtToCollaterals(),    6);

        _loans.removeT0DebtToCollateral(b2);
        assertEq(_loans.getMaxT0DebtToCollateral(),       500 * 1e18);
        assertEq(_loans.getMaxBorrower(), b5);
        assertEq(_loans.getTotalT0DebtToCollaterals(),    5);

        _loans.removeT0DebtToCollateral(b5);
        assertEq(_loans.getMaxT0DebtToCollateral(),       400 * 1e18);
        assertEq(_loans.getMaxBorrower(), b4);
        assertEq(_loans.getTotalT0DebtToCollaterals(),    4);

        _loans.removeT0DebtToCollateral(b4);
        assertEq(_loans.getMaxBorrower(), b3);
        assertEq(_loans.getMaxT0DebtToCollateral(),       300 * 1e18);
        assertEq(_loans.getTotalT0DebtToCollaterals(),    3);

        _loans.removeT0DebtToCollateral(b1);
        assertEq(_loans.getMaxBorrower(), b3);
        assertEq(_loans.getMaxT0DebtToCollateral(),       300 * 1e18);
        assertEq(_loans.getTotalT0DebtToCollaterals(),    2);

        _loans.removeT0DebtToCollateral(b3);
        assertEq(_loans.getMaxBorrower(), address(0));
        assertEq(_loans.getMaxT0DebtToCollateral(),       0);
        assertEq(_loans.getTotalT0DebtToCollaterals(),    1);
    }

    function testHeapInsertMultipleLoansWithSameTp() public {
        // assert initial state
        assertEq(_loans.getMaxBorrower(), address(0));
        assertEq(_loans.getMaxT0DebtToCollateral(), 0);

        address b1 = makeAddr("b1");
        address b2 = makeAddr("b2");
        address b3 = makeAddr("b3");
        address b4 = makeAddr("b4");
        address b5 = makeAddr("b5");
        address b6 = makeAddr("b6");

        _loans.upsertT0DebtToCollateral(b1, 100 * 1e18);
        _loans.upsertT0DebtToCollateral(b2, 200 * 1e18);
        _loans.upsertT0DebtToCollateral(b3, 200 * 1e18);
        _loans.upsertT0DebtToCollateral(b4, 300 * 1e18);
        _loans.upsertT0DebtToCollateral(b5, 400 * 1e18);
        _loans.upsertT0DebtToCollateral(b6, 400 * 1e18);

        assertEq(_loans.getMaxBorrower(), b5);
        assertEq(_loans.getMaxT0DebtToCollateral(),       400 * 1e18);
        assertEq(_loans.getTotalT0DebtToCollaterals(),    7);

        assertEq(_loans.getT0DebtToCollateral(b1), 100 * 1e18);
        assertEq(_loans.getT0DebtToCollateral(b2), 200 * 1e18);
        assertEq(_loans.getT0DebtToCollateral(b3), 200 * 1e18);
        assertEq(_loans.getT0DebtToCollateral(b4), 300 * 1e18);
        assertEq(_loans.getT0DebtToCollateral(b5), 400 * 1e18);
        assertEq(_loans.getT0DebtToCollateral(b6), 400 * 1e18);

        _loans.removeT0DebtToCollateral(b5);
        assertEq(_loans.getMaxBorrower(), b6);
        assertEq(_loans.getMaxT0DebtToCollateral(),       400 * 1e18);
        assertEq(_loans.getTotalT0DebtToCollaterals(),    6);

        _loans.removeT0DebtToCollateral(b6);
        assertEq(_loans.getMaxBorrower(), b4);
        assertEq(_loans.getMaxT0DebtToCollateral(),       300 * 1e18);
        assertEq(_loans.getTotalT0DebtToCollaterals(),    5);

        _loans.removeT0DebtToCollateral(b4);
        assertEq(_loans.getMaxBorrower(), b2);
        assertEq(_loans.getMaxT0DebtToCollateral(),       200 * 1e18);
        assertEq(_loans.getTotalT0DebtToCollaterals(),    4);

        _loans.upsertT0DebtToCollateral(b1, 200 * 1e18);
        assertEq(_loans.getMaxBorrower(), b2);
        assertEq(_loans.getMaxT0DebtToCollateral(),       200 * 1e18);
        assertEq(_loans.getTotalT0DebtToCollaterals(),    4);

        _loans.removeT0DebtToCollateral(b2);
        assertEq(_loans.getMaxBorrower(), b3);
        assertEq(_loans.getMaxT0DebtToCollateral(),       200 * 1e18);
        assertEq(_loans.getTotalT0DebtToCollaterals(),    3);

        _loans.removeT0DebtToCollateral(b3);
        assertEq(_loans.getMaxBorrower(), b1);
        assertEq(_loans.getMaxT0DebtToCollateral(),       200 * 1e18);
        assertEq(_loans.getTotalT0DebtToCollaterals(),    2);

        _loans.removeT0DebtToCollateral(b1);
        assertEq(_loans.getMaxBorrower(), address(0));
        assertEq(_loans.getMaxT0DebtToCollateral(),       0);
        assertEq(_loans.getTotalT0DebtToCollaterals(),    1);
    }

    function testHeapInsertAndRemoveHeadByMaxTp() public {
        // assert initial state
        assertEq(_loans.getMaxBorrower(), address(0));
        assertEq(_loans.getMaxT0DebtToCollateral(), 0);

        address b1 = makeAddr("b1");
        address b2 = makeAddr("b2");
        address b3 = makeAddr("b3");
        address b4 = makeAddr("b4");
        address b5 = makeAddr("b5");

        _loans.upsertT0DebtToCollateral(b1, 100 * 1e18);
        _loans.upsertT0DebtToCollateral(b2, 200 * 1e18);
        _loans.upsertT0DebtToCollateral(b3, 300 * 1e18);
        _loans.upsertT0DebtToCollateral(b4, 400 * 1e18);
        _loans.upsertT0DebtToCollateral(b5, 500 * 1e18);

        assertEq(_loans.getMaxT0DebtToCollateral(),       500 * 1e18);
        assertEq(_loans.getMaxBorrower(), b5);
        assertEq(_loans.getTotalT0DebtToCollaterals(),    6);

        _loans.removeT0DebtToCollateral(b5);
        assertEq(_loans.getMaxT0DebtToCollateral(),       400 * 1e18);
        assertEq(_loans.getMaxBorrower(), b4);
        assertEq(_loans.getTotalT0DebtToCollaterals(),    5);

        _loans.removeT0DebtToCollateral(b4);
        assertEq(_loans.getMaxBorrower(), b3);
        assertEq(_loans.getMaxT0DebtToCollateral(),       300 * 1e18);
        assertEq(_loans.getTotalT0DebtToCollaterals(),    4);

        _loans.removeT0DebtToCollateral(b3);
        assertEq(_loans.getMaxBorrower(), b2);
        assertEq(_loans.getMaxT0DebtToCollateral(),       200 * 1e18);
        assertEq(_loans.getTotalT0DebtToCollaterals(),    3);

        _loans.removeT0DebtToCollateral(b2);
        assertEq(_loans.getMaxBorrower(), b1);
        assertEq(_loans.getMaxT0DebtToCollateral(),       100 * 1e18);
        assertEq(_loans.getTotalT0DebtToCollaterals(),    2);

        _loans.removeT0DebtToCollateral(b1);
        assertEq(_loans.getMaxBorrower(), address(0));
        assertEq(_loans.getMaxT0DebtToCollateral(),       0);
        assertEq(_loans.getTotalT0DebtToCollaterals(),    1);
    }

    function testHeapRemoveLastTp() public {
        // assert initial state
        assertEq(_loans.getMaxBorrower(), address(0));
        assertEq(_loans.getMaxT0DebtToCollateral(),       0);
        assertEq(_loans.getTotalT0DebtToCollaterals(),    1);

        address b1 = makeAddr("b1");
        _loans.upsertT0DebtToCollateral(b1, 100 * 1e18);

        assertEq(_loans.getMaxBorrower(), b1);
        assertEq(_loans.getMaxT0DebtToCollateral(),       100 * 1e18);
        assertEq(_loans.getTotalT0DebtToCollaterals(),    2);

        // remove last TP
        _loans.removeT0DebtToCollateral(b1);
        assertEq(_loans.getMaxBorrower(), address(0));
        assertEq(_loans.getMaxT0DebtToCollateral(),       0);
        assertEq(_loans.getTotalT0DebtToCollaterals(),    1);
    }

    function testHeapUpdateTp() public {
        address b1 = makeAddr("b1");
        address b2 = makeAddr("b2");
        address b3 = makeAddr("b3");
        address b4 = makeAddr("b4");
        address b5 = makeAddr("b5");
        address b6 = makeAddr("b6");

        _loans.upsertT0DebtToCollateral(b1, 100 * 1e18);
        _loans.upsertT0DebtToCollateral(b2, 200 * 1e18);
        _loans.upsertT0DebtToCollateral(b3, 300 * 1e18);
        _loans.upsertT0DebtToCollateral(b4, 400 * 1e18);
        _loans.upsertT0DebtToCollateral(b5, 500 * 1e18);
        _loans.upsertT0DebtToCollateral(b6, 600 * 1e18);

        assertEq(_loans.getMaxT0DebtToCollateral(),       600 * 1e18);
        assertEq(_loans.getMaxBorrower(), b6);
        assertEq(_loans.getTotalT0DebtToCollaterals(),    7);

        _loans.upsertT0DebtToCollateral(b4, 1_000 * 1e18);
        assertEq(_loans.getMaxT0DebtToCollateral(),       1_000 * 1e18);
        assertEq(_loans.getMaxBorrower(), b4);
        assertEq(_loans.getTotalT0DebtToCollaterals(),    7);

        _loans.upsertT0DebtToCollateral(b4, 10 * 1e18);
        assertEq(_loans.getMaxT0DebtToCollateral(),       600 * 1e18);
        assertEq(_loans.getMaxBorrower(), b6);
        assertEq(_loans.getTotalT0DebtToCollaterals(),    7);

        _loans.upsertT0DebtToCollateral(b6, 100 * 1e18);
        assertEq(_loans.getMaxT0DebtToCollateral(),       500 * 1e18);
        assertEq(_loans.getMaxBorrower(), b5);
        assertEq(_loans.getTotalT0DebtToCollaterals(),    7);

        _loans.upsertT0DebtToCollateral(b6, 3_000 * 1e18);
        assertEq(_loans.getMaxT0DebtToCollateral(),       3_000 * 1e18);
        assertEq(_loans.getMaxBorrower(), b6);
        assertEq(_loans.getTotalT0DebtToCollaterals(),    7);
    }

    function testHeapZeroInsertion() public {
        address b1 = makeAddr("b1");
        address b2 = makeAddr("b2");
        address b3 = makeAddr("b3");

        _loans.upsertT0DebtToCollateral(b1, 0);
        assertEq(_loans.getMaxT0DebtToCollateral(),       0);
        assertEq(_loans.getMaxBorrower(), b1);
        assertEq(_loans.getTotalT0DebtToCollaterals(),    2);

        _loans.upsertT0DebtToCollateral(b2, 153 * 1e18);
        assertEq(_loans.getMaxT0DebtToCollateral(),       153 * 1e18);
        assertEq(_loans.getMaxBorrower(), b2);
        assertEq(_loans.getTotalT0DebtToCollaterals(),    3);

        _loans.removeT0DebtToCollateral(b2);
        assertEq(_loans.getMaxT0DebtToCollateral(),       0);
        assertEq(_loans.getMaxBorrower(), b1);
        assertEq(_loans.getTotalT0DebtToCollaterals(),    2);

        _loans.upsertT0DebtToCollateral(b3, 2_007 * 1e18);
        assertEq(_loans.getMaxT0DebtToCollateral(),       2_007 * 1e18);
        assertEq(_loans.getMaxBorrower(), b3);
        assertEq(_loans.getTotalT0DebtToCollaterals(),    3);

        _loans.removeT0DebtToCollateral(b1);
        assertEq(_loans.getMaxT0DebtToCollateral(),       2_007 * 1e18);
        assertEq(_loans.getMaxBorrower(), b3);
        assertEq(_loans.getTotalT0DebtToCollaterals(),    2);

        _loans.removeT0DebtToCollateral(b3);
        assertEq(_loans.getMaxBorrower(), address(0));
        assertEq(_loans.getMaxT0DebtToCollateral(),       0);
        assertEq(_loans.getTotalT0DebtToCollaterals(),    1);
    }

    function testLoadHeapFuzzy(uint256 inserts_, uint256 seed_) public {

        // test adding different TPs
        _loans.fuzzyFill(inserts_, seed_, true);

        // test adding different TPs
        address removeAddress = _loans.getIdByInsertIndex(randomInRange(1, _loans.numInserts() - 1, true));
        uint256 tp = _loans.getT0DebtToCollateral(removeAddress);
        uint256 length = _loans.getCount() - 1;

        _loans.removeT0DebtToCollateral(removeAddress);
        
        assertEq(length - 1, _loans.getCount() - 1);
        assertEq(_loans.getT0DebtToCollateral(removeAddress), 0);
        assertTrue(_loans.getT0DebtToCollateral(removeAddress) != tp);
    }

    function testHeapBorrowRepayBorrow() public {
        address b1 = makeAddr("b1");

        _loans.upsertT0DebtToCollateral(b1, 300 * 1e18);
        assertEq(_loans.getMaxBorrower(), b1);
        assertEq(_loans.getMaxT0DebtToCollateral(),       300 * 1e18);
        assertEq(_loans.getTotalT0DebtToCollaterals(),    2);

        _loans.removeT0DebtToCollateral(b1);
        assertEq(_loans.getMaxBorrower(), address(0));
        assertEq(_loans.getMaxT0DebtToCollateral(),       0);
        assertEq(_loans.getTotalT0DebtToCollaterals(),    1);

        _loans.upsertT0DebtToCollateral(b1, 400 * 1e18);
        assertEq(_loans.getMaxBorrower(), b1);
        assertEq(_loans.getMaxT0DebtToCollateral(),       400 * 1e18);
        assertEq(_loans.getTotalT0DebtToCollaterals(),    2);
    }

    function testHeapRemoveMiddleAndHead() public {
        address b1 = makeAddr("b1");
        address b2 = makeAddr("b2");
        address b3 = makeAddr("b3");
        address b4 = makeAddr("b4");
        address b5 = makeAddr("b5");
        address b6 = makeAddr("b6");
        address b7 = makeAddr("b7");

        _loans.upsertT0DebtToCollateral(b7, 7);
        _loans.upsertT0DebtToCollateral(b4, 4);
        _loans.upsertT0DebtToCollateral(b6, 6);
        _loans.upsertT0DebtToCollateral(b2, 2);
        _loans.upsertT0DebtToCollateral(b3, 3);
        _loans.upsertT0DebtToCollateral(b1, 1);
        _loans.upsertT0DebtToCollateral(b5, 5);
        assertEq(_loans.getMaxBorrower(), b7);
        assertEq(_loans.getMaxT0DebtToCollateral(),       7);
        assertEq(_loans.getTotalT0DebtToCollaterals(),    8);

        _loans.removeT0DebtToCollateral(b2);
        assertEq(_loans.getMaxBorrower(), b7);
        assertEq(_loans.getMaxT0DebtToCollateral(),       7);
        assertEq(_loans.getTotalT0DebtToCollaterals(),    7);

        _loans.removeT0DebtToCollateral(b7);
        assertEq(_loans.getMaxBorrower(), b6);
        assertEq(_loans.getMaxT0DebtToCollateral(),       6);
        assertEq(_loans.getTotalT0DebtToCollaterals(),    6);

        _loans.removeT0DebtToCollateral(b6);
        assertEq(_loans.getMaxBorrower(), b5);
        assertEq(_loans.getMaxT0DebtToCollateral(),       5);
        assertEq(_loans.getTotalT0DebtToCollaterals(),    5);
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
            _loans.upsertT0DebtToCollateral(borrower, 1 * 1e18 + i * 1e18);
            _borrowers.push(borrower);
        }
    }

    function testLoadHeapGasExerciseDeleteOnAllNodes() public {
        assertEq(_loans.getTotalT0DebtToCollaterals(), NODES_COUNT + 1); // account node 0 too

        for (uint256 i; i < NODES_COUNT; i++) {
            uint256 snapshot = vm.snapshot();
            assertEq(_loans.getTotalT0DebtToCollaterals(), NODES_COUNT + 1);

            _loans.removeT0DebtToCollateral(_borrowers[i]);

            assertEq(_loans.getTotalT0DebtToCollaterals(), NODES_COUNT);
            vm.revertTo(snapshot);
        }

        assertEq(_loans.getTotalT0DebtToCollaterals(), NODES_COUNT + 1);
    }

    function testLoadHeapGasExerciseUpsertOnAllNodes() public {
        assertEq(_loans.getTotalT0DebtToCollaterals(), NODES_COUNT + 1); // account node 0 too

        for (uint256 i; i < NODES_COUNT; i++) {
            uint256 snapshot = vm.snapshot();
            assertEq(_loans.getTotalT0DebtToCollaterals(), NODES_COUNT + 1);

            _loans.upsertT0DebtToCollateral(_borrowers[i], 1_000_000 * 1e18 + i * 1e18);

            assertEq(_loans.getTotalT0DebtToCollaterals(), NODES_COUNT + 1);
            vm.revertTo(snapshot);
        }

        assertEq(_loans.getTotalT0DebtToCollaterals(), NODES_COUNT + 1);
    }
}
