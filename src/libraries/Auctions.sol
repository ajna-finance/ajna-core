// SPDX-License-Identifier: MIT

pragma solidity 0.8.14;

import './Maths.sol';

library AuctionsQueue {

    struct Data {
        address head;
        address tail;
        mapping(address => Liquidation) liquidations;
    }

    struct Liquidation {
        address kicker;         // address that initiated liquidation
        uint256 bondSize;       // bond size posted by kicker to start liquidation
        uint256 bondFactor;     // bond factor used to start liquidation
        uint128 kickTime;       // timestamp when liquidation was started
        uint128 kickPriceIndex; // HPB index at liquidation start
        address prev;           // previous liquidated borrower in auctions queue
        address next;           // next liquidated borrower in auctions queue
    }


    /*********************************/
    /***  Auctions Queue functions ***/
    /*********************************/

    /**
     *  @notice Called to start borrower liquidation and to update the auctions queue
     *  @param  borrower_       Borrower address to liquidate
     *  @param  borrowerDebt_   Borrower debt to be recovered
     *  @param  thresholdPrice_ Current threshold price (used to calculate bond factor)
     *  @param  momp_           Current MOMP (used to calculate bond factor)
     *  @param  hpbIndex_       Current HPB index
     *  @return bondSize_       The bond size posted to liquidate position
     */
    function kick(
        Data storage self_,
        address borrower_,
        uint256 borrowerDebt_,
        uint256 thresholdPrice_,
        uint256 momp_,
        uint256 hpbIndex_
    ) internal returns (uint256 bondSize_) {

        Liquidation storage liquidation = self_.liquidations[borrower_];
        liquidation.kicker         = msg.sender;
        liquidation.kickTime       = uint128(block.timestamp);
        liquidation.kickPriceIndex = uint128(hpbIndex_);

        uint256 bondFactor;
        // bondFactor = min(30%, max(1%, (neutralPrice - thresholdPrice) / neutralPrice))
        if (thresholdPrice_ >= momp_) {
            bondFactor = 0.01 * 1e18;
        } else {
            bondFactor = Maths.min(
                0.3 * 1e18,
                Maths.max(
                    0.01 * 1e18,
                    1e18 - Maths.wdiv(thresholdPrice_, momp_)
                )
            );
        }
        bondSize_ = Maths.wmul(bondFactor, borrowerDebt_);

        liquidation.bondSize   = bondSize_;
        liquidation.bondFactor = bondFactor;

        liquidation.next = address(0);
        if (self_.head != address(0)) {
            // other auctions in queue, liquidation doesn't exist or overwriting.
            self_.liquidations[self_.tail].next = borrower_;
            liquidation.prev = self_.tail;
        } else {
            // first auction in queue
            self_.head = borrower_;
            liquidation.prev  = address(0);
        }

        // update liquidation with the new ordering
        self_.tail = borrower_;
    }

    /**
     *  @notice Removes a borrower from the auctions queue and repairs the queue order.
     *  @dev    Called by _updateLoanQueue if borrower.debt == 0.
     *  @param  borrower_ Borrower whose loan is being placed in queue.
     */
    function remove(Data storage self_, address borrower_) internal {
        address next = self_.liquidations[borrower_].next;
        address prev = self_.liquidations[borrower_].prev;

        if (self_.head == borrower_ && self_.tail == borrower_) {
            // liquidation is the head and tail
            self_.head = address(0);
            self_.tail = address(0);

        } else if(self_.head == borrower_) {
            // liquidation is the head
            self_.liquidations[next].prev = address(0);
            self_.head = next;

        } else if(self_.tail == borrower_) {
            // liquidation is the tail
            self_.liquidations[prev].next = address(0);
            self_.tail = prev;

        } else {
            // liquidation is in the middle
            self_.liquidations[prev].next = next;
            self_.liquidations[next].prev = prev;
        }

        delete self_.liquidations[borrower_];
    }


    /**************************/
    /*** View Functions ***/
    /**************************/

    function getHead(Data storage self_) internal view returns (address) {
        return self_.head;
    }

    function isActive(Data storage self_, address borrower_) internal view returns (bool) {
        return self_.liquidations[borrower_].kicker != address(0);
    }

    function get(
        Data storage self_,
        address borrower_
    )
        internal
        view
        returns (
            address,
            uint256,
            uint256,
            uint128,
            uint128,
            address,
            address
        )
    {
        AuctionsQueue.Liquidation memory liquidation = self_.liquidations[borrower_];
        return (
            liquidation.kicker,
            liquidation.bondSize,
            liquidation.bondFactor,
            liquidation.kickTime,
            liquidation.kickPriceIndex,
            liquidation.prev,
            liquidation.next
        );
    }

}
