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

        // check queue head was set correctly
        assertEq(_borrower, auctions.head());
        (address next, bool active) = auctions.getAuction(auctions.head());
        assertEq(next, address(0));
        assertEq(active, true);

        // insert borrower2 -- _borrower -> _borrower2
        // check queue head remains, _borrower -> _borrower2
        skip(100 seconds);
        auctions.add(_borrower2); 
        assertEq(_borrower, auctions.head());
        (next, active) = auctions.getAuction(auctions.head());
        assertEq(address(_borrower2), next);
        (next, active) = auctions.getAuction(_borrower2);
        assertEq(address(0), next);

        (next, active) = auctions.getAuction(_borrower);
        assertEq(_borrower2, next);

        // _borrower -> _borrower2 -> _borrower3
        // Don't adjust time, node should still be inserted at tail
        auctions.add(_borrower3);

        assertEq(_borrower, auctions.head());
        (next, active) = auctions.getAuction(auctions.head());
        assertEq(address(_borrower2), next);

        (next, active) = auctions.getAuction(_borrower2);
        assertEq(address(_borrower3), next);

        (next, active) = auctions.getAuction(_borrower3);
        assertEq(address(0), next);
    }

    function testQueueRemove() public {
        // Fill Queue
        skip(12 seconds);
        auctions.add(_borrower);  
        skip(12 seconds);
        auctions.add(_borrower2);  
        skip(12 seconds);
        auctions.add(_borrower3);

        // Deactivate _borrower then remove from head
        vm.expectRevert("Q:RH:AUCT_NOT_DEACT");
        auctions.removeHead();
        auctions.deactivate(_borrower);
        (address next, bool active) = auctions.getAuction(_borrower);
        assertEq(next, _borrower2);
        assertEq(active, false);

        // remove _borrower from head
        auctions.removeHead();
        (next, active) = auctions.getAuction(_borrower);
        assertEq(next, address(0));
        assertEq(active, false);

        // assert new head
        assertEq(auctions.head(), _borrower2);

        // Deactivate _borrower2
        auctions.deactivate(_borrower2);
        (next, active) = auctions.getAuction(_borrower2);
        assertEq(next, _borrower3);
        assertEq(active, false);
    }
    
    function skiptestQueueAddRemoveAdd() public {
        // Fill Queue
        skip(12 seconds);
        auctions.add(_borrower);  
        skip(12 seconds);
        auctions.add(_borrower2);  
        skip(12 seconds);
        auctions.add(_borrower3);

        // Deactivate _borrower
        vm.expectRevert("Q:RH:AUCT_NOT_DEACT");
        auctions.removeHead();
        auctions.deactivate(_borrower);
        (address next, bool active) = auctions.getAuction(_borrower);
        assertEq(active, false);
        assertEq(auctions.head(), _borrower);

        skip(1 hours);

        // Re-add _borrower by overwriting auctions mapping
        auctions.add(_borrower);  

        (next, active) = auctions.getAuction(_borrower);
        assertEq(next, address(0));
        assertEq(active, true);

         // remove _borrower from head
         // TODO: This case breaks when it shouldn't, this is a fault of the current design
        auctions.removeHead();
        (next, active) = auctions.getAuction(_borrower);
        assertEq(next, address(0));
        assertEq(active, false);
        
        // assert new head
        assertEq(auctions.head(), _borrower2);
    }
}
