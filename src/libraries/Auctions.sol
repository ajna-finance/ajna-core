// SPDX-License-Identifier: MIT

pragma solidity 0.8.14;

import './Loans.sol';
import './Maths.sol';

library Auctions {

    struct Data {
        address head;
        address tail;
        uint256 liquidationBondEscrowed; // [WAD]
        mapping(address => Liquidation) liquidations;
        mapping(address => Kicker)      kickers;
    }

    struct Liquidation {
        address kicker;          // address that initiated liquidation
        uint256 bondSize;        // liquidation bond size
        uint256 bondFactor;      // bond factor used to start liquidation
        uint128 kickTime;        // timestamp when liquidation was started
        uint128 kickPriceIndex;  // HPB price index at liquidation kick time
        address prev;            // previous liquidated borrower in auctions queue
        address next;            // next liquidated borrower in auctions queue
    }

    struct Kicker {
        uint256 claimable; // kicker's claimable balance
        uint256 locked;    // kicker's balance of tokens locked in auction bonds
    }

    /**
     *  @notice Actor is attempting to take or clear an inactive auction.
     */
    error NoAuction();
    /**
     *  @notice Take was called before 1 hour had passed from kick time.
     */
    error TakeNotPastCooldown();

    /*********************************/
    /***  Auctions Queue Functions ***/
    /*********************************/

    /**
     *  @notice Removes a collateralized borrower from the auctions queue and repairs the queue order.
     *  @notice Updates kicker's claimable balance with bond size awarded and subtracts bond size awarded from liquidationBondEscrowed.
     *  @param  borrower_          Borrower whose loan is being placed in queue.
     *  @param  collateralization_ Borrower's collateralization.
     */
    function checkAndRemove(
        Data storage self,
        address borrower_,
        uint256 collateralization_
    ) internal {

        if (collateralization_ >= Maths.WAD && self.liquidations[borrower_].kickTime != 0) {

            Liquidation memory liquidation = self.liquidations[borrower_];
            // update kicker balances
            Kicker storage kicker = self.kickers[liquidation.kicker];
            kicker.locked    -= liquidation.bondSize;
            kicker.claimable += liquidation.bondSize;

            if (self.head == borrower_ && self.tail == borrower_) {
                // liquidation is the head and tail
                self.head = address(0);
                self.tail = address(0);

            } else if(self.head == borrower_) {
                // liquidation is the head
                self.liquidations[liquidation.next].prev = address(0);
                self.head = liquidation.next;

            } else if(self.tail == borrower_) {
                // liquidation is the tail
                self.liquidations[liquidation.prev].next = address(0);
                self.tail = liquidation.prev;

            } else {
                // liquidation is in the middle
                self.liquidations[liquidation.prev].next = liquidation.next;
                self.liquidations[liquidation.next].prev = liquidation.prev;
            }
            // delete liquidation
            delete self.liquidations[borrower_];
        }
    }

    /**
     *  @notice Called to start borrower liquidation and to update the auctions queue.
     *  @param  borrower_          Borrower address to liquidate.
     *  @param  borrowerDebt_      Borrower debt to be recovered.
     *  @param  thresholdPrice_    Current threshold price (used to calculate bond factor).
     *  @param  momp_              Current MOMP (used to calculate bond factor).
     *  @param  hpbIndex_          Current HPB index.
     *  @return kickAuctionAmount_ The amount that kicker should send to pool in order to kick auction.
     */
    function kick(
        Data storage self,
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
        Kicker storage kicker = self.kickers[msg.sender];
        kicker.locked += bondSize;
        if (kicker.claimable >= bondSize) {
            kicker.claimable -= bondSize;
        } else {
            kickAuctionAmount_ = bondSize - kicker.claimable;
            kicker.claimable = 0;
        }
        // update liquidationBondEscrowed accumulator
        self.liquidationBondEscrowed += bondSize;

        // record liquidation info
        Liquidation storage liquidation = self.liquidations[borrower_];
        liquidation.kicker         = msg.sender;
        liquidation.kickTime       = uint128(block.timestamp);
        liquidation.kickPriceIndex = uint128(hpbIndex_);
        liquidation.bondSize       = bondSize;
        liquidation.bondFactor     = bondFactor;

        liquidation.next = address(0);
        if (self.head != address(0)) {
            // other auctions in queue, liquidation doesn't exist or overwriting.
            self.liquidations[self.tail].next = borrower_;
            liquidation.prev = self.tail;
        } else {
            // first auction in queue
            self.head = borrower_;
            liquidation.prev  = address(0);
        }

        // update liquidation with the new ordering
        self.tail = borrower_;
    }

    /**
     *  @notice Performs take collateral on an auction and updates bond size and kicker balance accordingly.
     *  @param  borrowerAddress_  Borrower address in auction.
     *  @param  borrower_         Borrower struct containing updated info of auctioned borrower.
     *  @param  maxCollateral_    The max collateral amount to be taken from auction.
     *  @return quoteTokenAmount_ The quote token amount that taker should pay for collateral taken.
     *  @return repayAmount_      The amount of debt (quote tokens) that is recovered / repayed by take.
     *  @return collateralTaken_  The amount of collateral taken.
     *  @return bondChange_       The change made on the bond size (beeing reward or penalty).
     *  @return isRewarded_       True if kicker is rewarded (auction price lower than neutral price), false if penalized (auction price greater than neutral price).
     */
    function take(
        Data storage self,
        address borrowerAddress_,
        Loans.Borrower memory borrower_,
        uint256 maxCollateral_
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
        Liquidation storage liquidation = self.liquidations[borrowerAddress_];
        if (liquidation.kickTime == 0) revert NoAuction();
        if (block.timestamp - liquidation.kickTime <= 1 hours) revert TakeNotPastCooldown();

        uint256 auctionPrice = PoolUtils.auctionPrice(
            PoolUtils.indexToPrice(liquidation.kickPriceIndex),
            liquidation.kickTime
        );
        // calculate amount
        quoteTokenAmount_ = Maths.wmul(auctionPrice, Maths.min(borrower_.collateral, maxCollateral_));
        collateralTaken_  = Maths.wdiv(quoteTokenAmount_, auctionPrice);

        int256 bpf = PoolUtils.bpf(
            borrower_.debt,
            borrower_.collateral,
            borrower_.mompFactor,
            borrower_.inflatorSnapshot,
            liquidation.bondFactor,
            auctionPrice
        );

        repayAmount_ = Maths.wmul(quoteTokenAmount_, uint256(1e18 - bpf));
        if (repayAmount_ >= borrower_.debt) {
            repayAmount_      = borrower_.debt;
            quoteTokenAmount_ = Maths.wdiv(borrower_.debt, uint256(1e18 - bpf));
        }

        isRewarded_ = (bpf >= 0);
        if (isRewarded_) {
            // take is below neutralPrice, Kicker is rewarded
            bondChange_ = quoteTokenAmount_ - repayAmount_;
            liquidation.bondSize += bondChange_;
            self.kickers[liquidation.kicker].locked += bondChange_;
        } else {
            // take is above neutralPrice, Kicker is penalized
            bondChange_ = Maths.wmul(quoteTokenAmount_, uint256(-bpf));
            liquidation.bondSize -= Maths.min(liquidation.bondSize, bondChange_);
            if (bondChange_ >= self.kickers[liquidation.kicker].locked) {
                self.kickers[liquidation.kicker].locked = 0;
            }
            else self.kickers[liquidation.kicker].locked -= bondChange_;
        }
    }

    /**********************/
    /*** View Functions ***/
    /**********************/

    /**
     *  @notice Retrieves status of auction for a given borrower address.
     *  @param  borrower_ Borrower address to get auction status for.
     *  @return kicked_   True if auction was kicked (kick time is different than 0).
     *  @return started_  True if auction is started (more than 1 hours elapsed since it was kicked).
     */
    function getStatus(
        Data storage self,
        address borrower_
    ) internal view returns (bool kicked_, bool started_) {
        uint256 kickTime = self.liquidations[borrower_].kickTime;
        kicked_  = kickTime != 0;
        started_ = kicked_ && (block.timestamp - kickTime > 1 hours);
    }

}
