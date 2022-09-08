// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.14;

import { DSTestPlus, HeapInstance }  from "./utils/DSTestPlus.sol";

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

    function testHeapUpsertRequireChecks() public {
        address b1 = makeAddr("b1");
        vm.expectRevert("H:I:VAL_EQ_0");
        _loans.upsertTp(b1, 0);

        _loans.upsertTp(b1, 100 * 1e18);

        vm.expectRevert("H:I:VAL_EQ_0");
        _loans.upsertTp(b1, 0);
    }

    function testHeapFuzzy(uint256 inserts_) public {

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

    function testHeapRemoveNonExistentTp() public {
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
        assertEq(_loans.getMaxBorrower(), b6);
        assertEq(_loans.getTotalTps(),    7);

        vm.expectRevert("H:R:NO_ID");
        _loans.removeTp(address(100));
    }

}
