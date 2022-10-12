// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.14;

import './utils/DSTestPlus.sol';

import './utils/AuctionsQueueInstance.sol';

contract AuctionsQueueTest is DSTestPlus {

    address internal _borrower;
    address internal _borrower2;
    address internal _borrower3;
    address internal _borrower4;
    address internal _borrower5;
    address internal _borrower6;
    address internal _lender;

    AuctionsQueueInstance private auctions;

    function setUp() external {
        _borrower  = makeAddr("borrower");
        _borrower2 = makeAddr("borrower2");
        _borrower3 = makeAddr("borrower3");

        auctions = new AuctionsQueueInstance();
    }
    /**
     *  @notice With 1 lender and 1 borrower test adding collateral and borrowing.
     */
    function testAuctionsQueueKick() public {
        // Add _borrower
        skip(100 seconds);
        auctions.kick(_borrower);

        // Check queue head was set correctly
        assertEq(_borrower, auctions.getHead());
        (
            ,
            ,
            ,
            ,
            ,
            address prev,
            address next
        ) = auctions.get(auctions.getHead());
        assertEq(next, address(0));
        assertEq(prev, address(0));
        assertEq(auctions.isActive(_borrower), true);

        // Insert borrower2 -- _borrower -> _borrower2
        // Check queue head remains, _borrower -> _borrower2
        skip(100 seconds);
        auctions.kick(_borrower2);
        assertEq(auctions.getHead(), _borrower);

        (
            ,
            ,
            ,
            ,
            ,
            prev,
            next
        ) = auctions.get(_borrower);
        assertEq(_borrower2, next);
        assertEq(address(0), prev);

        (
            ,
            ,
            ,
            ,
            ,
            prev,
            next
        ) = auctions.get(_borrower2);
        assertEq(address(0), next);
        assertEq(_borrower, prev);

        // _borrower -> _borrower2 -> _borrower3
        // Don't adjust time, node should still be inserted at tail
        auctions.kick(_borrower3);

        assertEq(_borrower, auctions.getHead());
        (
            ,
            ,
            ,
            ,
            ,
            prev,
            next
        ) = auctions.get(auctions.getHead());
        assertEq(_borrower2, next);
        assertEq(address(0), prev);

        (
            ,
            ,
            ,
            ,
            ,
            prev,
            next
        ) = auctions.get(_borrower2);
        assertEq(_borrower3, next);
        assertEq(_borrower, prev);

        (
            ,
            ,
            ,
            ,
            ,
            prev,
            next
        ) = auctions.get(_borrower3);
        assertEq(address(0), next);
        assertEq(_borrower2, prev);
    }

    function testAuctionsQueueRemove() public {
        // Fill Queue
        skip(12 seconds);
        auctions.kick(_borrower);
        skip(12 seconds);
        auctions.kick(_borrower2);
        skip(12 seconds);
        auctions.kick(_borrower3);

        // Remove _borrower from head
        auctions.remove(_borrower);
        assertEq(auctions.isActive(_borrower), false);

        // assert new head
        assertEq(auctions.getHead(), _borrower2);
        (
            ,
            ,
            ,
            ,
            ,
            address prev,
            address next
        ) = auctions.get(_borrower2);
        assertEq(prev, address(0));
        assertEq(next, _borrower3);
        assertEq(auctions.isActive(_borrower2), true);

        // Remove _borrower2
        auctions.remove(_borrower2);
        assertEq(auctions.isActive(_borrower2), false);

        assertEq(auctions.isActive(_borrower3), true);
        assertEq(auctions.getHead(), _borrower3);

    }

    function testAuctionsQueueKickRemoveAdd() public {
        // Fill Queue
        skip(12 seconds);
        auctions.kick(_borrower);
        skip(12 seconds);
        auctions.kick(_borrower2);
        skip(12 seconds);
        auctions.kick(_borrower3);

        // Remove _borrower2
        auctions.remove(_borrower2);
        (
            ,
            ,
            ,
            ,
            ,
            address prev,
            address next
        ) = auctions.get(_borrower);
        assertEq(prev, address(0));
        assertEq(next, _borrower3);
        assertEq(auctions.isActive(_borrower), true);
        assertEq(auctions.getHead(), _borrower);

        (
            ,
            ,
            ,
            ,
            ,
            prev,
            next
        ) = auctions.get(_borrower3);
        assertEq(next, address(0));
        assertEq(prev, _borrower);
        assertEq(auctions.isActive(_borrower3), true);
        assertEq(auctions.getHead(), _borrower);

        skip(1 hours);

        // Re-add _borrower by overwriting auctions mapping
        auctions.kick(_borrower2);

        (
            ,
            ,
            ,
            ,
            ,
            prev,
            next
        ) = auctions.get(_borrower2);
        assertEq(next, address(0));
        assertEq(prev, _borrower3);
        assertEq(auctions.isActive(_borrower), true);
        assertEq(auctions.getHead(), _borrower);
    }
}
