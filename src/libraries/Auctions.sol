// SPDX-License-Identifier: MIT

pragma solidity 0.8.14;

import './Loans.sol';
import './Maths.sol';

library Auctions {

    struct Data {
        address head;
        address tail;
        mapping(address => Liquidation) liquidations;
        mapping(address => Kicker)      kickers;
    }

    struct Liquidation {
        address kicker;         // address that initiated liquidation
        uint256 bondSize;       // liquidation bond size
        uint256 bondFactor;     // bond factor used to start liquidation
        uint128 kickTime;       // timestamp when liquidation was started
        uint128 kickPriceIndex; // HPB index at liquidation start
        address prev;           // previous liquidated borrower in auctions queue
        address next;           // next liquidated borrower in auctions queue
    }

    struct Kicker {
        uint256 claimable; // kicker's claimable balance
        uint256 locked;    // kicker's balance of tokens locked in auction bonds
    }

    error NoAuction();
    error TakeNotPastCooldown();

    /*********************************/
    /***  Auctions Queue Functions ***/
    /*********************************/

    /**
     *  @notice Removes a collateralized borrower from the auctions queue and repairs the queue order.
     *  @param  borrower_   Borrower whose loan is being placed in queue.
     *  @param  debt_       Borrower's accrued debt.
     *  @param  collateral_ Borrower's pledged collateral.
     *  @param  lup_        Pool's LUP.
     */
    function checkAndRemove(
        Data storage self_,
        address borrower_,
        uint256 debt_,
        uint256 collateral_,
        uint256 lup_
    ) internal {
        if (PoolUtils.collateralization(debt_, collateral_, lup_) >= Maths.WAD) {
            Liquidation memory liquidation = self_.liquidations[borrower_];

            Kicker storage kicker = self_.kickers[liquidation.kicker];
            kicker.locked    -= liquidation.bondSize;
            kicker.claimable += liquidation.bondSize;

            if (self_.head == borrower_ && self_.tail == borrower_) {
                // liquidation is the head and tail
                self_.head = address(0);
                self_.tail = address(0);

            } else if(self_.head == borrower_) {
                // liquidation is the head
                self_.liquidations[liquidation.next].prev = address(0);
                self_.head = liquidation.next;

            } else if(self_.tail == borrower_) {
                // liquidation is the tail
                self_.liquidations[liquidation.prev].next = address(0);
                self_.tail = liquidation.prev;

            } else {
                // liquidation is in the middle
                self_.liquidations[liquidation.prev].next = liquidation.next;
                self_.liquidations[liquidation.next].prev = liquidation.prev;
            }

            delete self_.liquidations[borrower_];
        }
    }

    /**
     *  @notice Called to start borrower liquidation and to update the auctions queue
     *  @param  borrower_          Borrower address to liquidate
     *  @param  borrowerDebt_      Borrower debt to be recovered
     *  @param  thresholdPrice_    Current threshold price (used to calculate bond factor)
     *  @param  momp_              Current MOMP (used to calculate bond factor)
     *  @param  hpbIndex_          Current HPB index
     *  @return kickAuctionAmount_ The amount that kicker should send to pool in order to kick auction
     */
    function kick(
        Data storage self_,
        address borrower_,
        uint256 borrowerDebt_,
        uint256 thresholdPrice_,
        uint256 momp_,
        uint256 hpbIndex_
    ) internal returns (uint256 kickAuctionAmount_) {

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
        uint256 bondSize = Maths.wmul(bondFactor, borrowerDebt_);

        // update kicker balances
        Kicker storage kicker = self_.kickers[msg.sender];
        kicker.locked += bondSize;
        if (kicker.claimable >= bondSize) {
            kicker.claimable -= bondSize;
        } else {
            kickAuctionAmount_ = bondSize - kicker.claimable;
            kicker.claimable = 0;
        }

        // record liquidation info
        Liquidation storage liquidation = self_.liquidations[borrower_];
        liquidation.kicker         = msg.sender;
        liquidation.kickTime       = uint128(block.timestamp);
        liquidation.kickPriceIndex = uint128(hpbIndex_);
        liquidation.bondSize       = bondSize;
        liquidation.bondFactor     = bondFactor;

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

    function take(
        Data storage self_,
        address borrower_,
        uint256 borrowerDebt_,
        uint256 borrowerCollateral_,
        uint256 borrowerMompFactor_,
        uint256 maxCollateral_,
        uint256 poolInflator_
    )
        internal
        returns (
            uint256 quoteTokenAmount_,
            uint256 repayAmount_,
            uint256 collateralTaken_,
            uint256 bondChange_,
            bool isRewarded_
        )
    {
        Liquidation storage liquidation = self_.liquidations[borrower_];
        if (liquidation.kickTime == 0) revert NoAuction();
        if (block.timestamp - liquidation.kickTime <= 1 hours) revert TakeNotPastCooldown();

        uint256 auctionPrice = PoolUtils.auctionPrice(
            liquidation.kickPriceIndex,
            liquidation.kickTime
        );
        // calculate amount
        quoteTokenAmount_ = Maths.wmul(auctionPrice, Maths.min(borrowerCollateral_, maxCollateral_));
        collateralTaken_  = Maths.wdiv(quoteTokenAmount_, auctionPrice);

        int256 bpf = PoolUtils.bpf(
            borrowerDebt_,
            borrowerCollateral_,
            borrowerMompFactor_,
            poolInflator_,
            liquidation.bondFactor,
            auctionPrice
        );

        repayAmount_ = Maths.wmul(quoteTokenAmount_, uint256(1e18 - bpf));
        if (repayAmount_ >= borrowerDebt_) {
            repayAmount_      = borrowerDebt_;
            quoteTokenAmount_ = Maths.wdiv(borrowerDebt_, uint256(1e18 - bpf));
        }

        isRewarded_ = (bpf >= 0);
        if (isRewarded_) {
            // take is below neutralPrice, Kicker is rewarded
            bondChange_ = quoteTokenAmount_ - repayAmount_;
            liquidation.bondSize += bondChange_;
            self_.kickers[liquidation.kicker].locked += bondChange_;
        } else {
            // take is above neutralPrice, Kicker is penalized
            bondChange_ = Maths.wmul(quoteTokenAmount_, uint256(-bpf));
            liquidation.bondSize -= bondChange_;
            self_.kickers[liquidation.kicker].locked -= bondChange_;
        }
    }

    /**********************/
    /*** View Functions ***/
    /**********************/

    function getAuctionInfo(
        Data storage self_,
        address borrower_
    )
        internal
        view
        returns (
            address,
            uint256,
            uint256,
            uint256,
            address,
            address
        )
    {
        Auctions.Liquidation memory liquidation = self_.liquidations[borrower_];
        return (
            liquidation.kicker,
            liquidation.bondFactor,
            uint256(liquidation.kickTime),
            uint256(liquidation.kickPriceIndex),
            liquidation.prev,
            liquidation.next
        );
    }

    function getKickerInfo(
        Data storage self,
        address kicker_
    ) internal view returns (uint256, uint256) {
        return (self.kickers[kicker_].claimable, self.kickers[kicker_].locked);
    }

    function getStatus(
        Data storage self_,
        address borrower_
    ) internal view returns (bool kicked_, bool started_) {
        uint256 kickTime = self_.liquidations[borrower_].kickTime;
        kicked_  = kickTime != 0;
        started_ = kicked_ && (block.timestamp - kickTime > 1 hours);
    }

}
