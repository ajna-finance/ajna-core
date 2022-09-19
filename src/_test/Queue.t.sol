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
        vm.warp(block.timestamp + 100 seconds);
        auctions.add(_borrower, block.timestamp, address(0)); 
        // check queue head was set correctly
        assertEq(_borrower, auctions.head());
        (uint256 val, address next, bool active) = auctions.getAuction(auctions.head());
        assertEq(address(0), next);

        // insert borrower2
        // _borrower -> _borrower2
        vm.warp(block.timestamp + 100 seconds);
        auctions.add(_borrower2, block.timestamp, _borrower); 

        // check queue head remains, _borrower -> _borrower2
        assertEq(_borrower, auctions.head());
        (val, next, active) = auctions.getAuction(auctions.head());
        assertEq(address(_borrower2), next);
        (val, next, active) = auctions.getAuction(_borrower2);
        assertEq(address(0), next);
        assertEq(val, block.timestamp);

        (val, next, active) = auctions.getAuction(_borrower);
        assertEq(_borrower2, next);

        // _borrower -> _borrower2 -> _borrower3
        // Don't adjust time, node should still be inserted at tail
        auctions.add(_borrower3, block.timestamp, _borrower2);

        assertEq(_borrower, auctions.head());
        (val, next, active) = auctions.getAuction(auctions.head());
        assertEq(address(_borrower2), next);

        (val, next, active) = auctions.getAuction(_borrower2);
        assertEq(address(_borrower3), next);

        (val, next, active) = auctions.getAuction(_borrower3);
        assertEq(address(0), next);
    }

    function testQueueRemove() public {
        vm.warp(block.timestamp + 1 seconds);
        auctions.add(_borrower, block.timestamp, address(0));  
        vm.warp(block.timestamp + 1 seconds);
        auctions.add(_borrower2, block.timestamp, _borrower);  
        vm.warp(block.timestamp + 1 seconds);
        auctions.add(_borrower3, block.timestamp, _borrower2);

        vm.expectRevert("Q:RH:AUCT_NOT_REM");
        auctions.removeHead();
        auctions.remove(_borrower);
        (uint256 val, address next, bool active) = auctions.getAuction(_borrower);
        assertEq(active, false);
        auctions.removeHead();

        assertEq(auctions.head(), _borrower2);

        auctions.remove(_borrower2);
        (val, next, active) = auctions.getAuction(_borrower2);
        assertEq(active, false);
    }
}
