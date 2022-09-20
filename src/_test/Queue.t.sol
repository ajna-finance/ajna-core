// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.14;

import { DSTestPlus, QueueInstance }   from "./utils/DSTestPlus.sol";


contract QueueTest is DSTestPlus {

    address internal _borrower;
    address internal _borrower2;
    address internal _borrower3;
    address internal _borrower4;
    address internal _borrower5;
    address internal _borrower6;
    address internal _lender;

    QueueInstance private auctions;

    function setUp() external {
        _borrower  = makeAddr("borrower");
        _borrower2 = makeAddr("borrower2");
        _borrower3 = makeAddr("borrower3");
        //_borrower4 = makeAddr("borrower4");
        //_borrower5 = makeAddr("borrower5");

        auctions = new QueueInstance();
    }
    /**
     *  @notice With 1 lender and 1 borrower test adding collateral and borrowing.
     */
    function testQueueAdd() public {
        // Add _borrower
        skip(100 seconds);
        auctions.add(_borrower); 

        // Check queue head was set correctly
        assertEq(_borrower, auctions.head());
        (address next, address prev, bool active) = auctions.getAuction(auctions.head());
        assertEq(next, address(0));
        assertEq(prev, address(0));
        assertEq(active, true);

        // Insert borrower2 -- _borrower -> _borrower2
        // Check queue head remains, _borrower -> _borrower2
        skip(100 seconds);
        auctions.add(_borrower2); 
        assertEq(_borrower, auctions.head());

        (next, prev, active) = auctions.getAuction(_borrower);
        assertEq(_borrower2, next);
        assertEq(address(0), prev);

        (next, prev, active) = auctions.getAuction(_borrower2);
        assertEq(address(0), next);
        assertEq(_borrower, prev);

        // _borrower -> _borrower2 -> _borrower3
        // Don't adjust time, node should still be inserted at tail
        auctions.add(_borrower3);

        assertEq(_borrower, auctions.head());
        (next, prev, active) = auctions.getAuction(auctions.head());
        assertEq(_borrower2, next);
        assertEq(address(0), prev);

        (next, prev, active) = auctions.getAuction(_borrower2);
        assertEq(_borrower3, next);
        assertEq(_borrower, prev);

        (next, prev, active) = auctions.getAuction(_borrower3);
        assertEq(address(0), next);
        assertEq(_borrower2, prev);
    }

    function testQueueRemove() public {
        // Fill Queue
        skip(12 seconds);
        auctions.add(_borrower);  
        skip(12 seconds);
        auctions.add(_borrower2);  
        skip(12 seconds);
        auctions.add(_borrower3);

        // Remove _borrower from head
        auctions.remove(_borrower);
        (address next, address prev,  bool active) = auctions.getAuction(_borrower);
        assertEq(active, false);

        // assert new head
        assertEq(auctions.head(), _borrower2);
        (next, prev, active) = auctions.getAuction(_borrower2);
        assertEq(prev, address(0));
        assertEq(next, _borrower3);
        assertEq(active, true);

        // Remove _borrower2
        auctions.remove(_borrower2);
        (next, prev, active) = auctions.getAuction(_borrower2);
        assertEq(active, false);


        (next, prev, active) = auctions.getAuction(_borrower3);
        assertEq(active, true);
        assertEq(_borrower3, auctions.head());

    }
    
    function testQueueAddRemoveAdd() public {
        // Fill Queue
        skip(12 seconds);
        auctions.add(_borrower);  
        skip(12 seconds);
        auctions.add(_borrower2);  
        skip(12 seconds);
        auctions.add(_borrower3);

        // Remove _borrower2
        auctions.remove(_borrower2);
        (address next, address prev, bool active) = auctions.getAuction(_borrower);
        assertEq(active, true);
        assertEq(prev, address(0));
        assertEq(next, _borrower3);
        assertEq(auctions.head(), _borrower);

        (next, prev, active) = auctions.getAuction(_borrower3);
        assertEq(active, true);
        assertEq(next, address(0));
        assertEq(prev, _borrower);
        assertEq(auctions.head(), _borrower);

        skip(1 hours);

        // Re-add _borrower by overwriting auctions mapping
        auctions.add(_borrower2);  

        (next, prev, active) = auctions.getAuction(_borrower2);
        assertEq(next, address(0));
        assertEq(prev, _borrower3);
        assertEq(active, true);
        assertEq(auctions.head(), _borrower);
    }
}
