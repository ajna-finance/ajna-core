// SPDX-License-Identifier: MIT

pragma solidity 0.8.14;

import './Buckets.sol';
import './Loans.sol';
import './Maths.sol';
import './PoolUtils.sol';

library Auctions {

    struct Data {
        address head;
        address tail;
        uint256 totalBondEscrowed; // [WAD]
        mapping(address => Liquidation) liquidations;
        mapping(address => Kicker)      kickers;
    }

    struct Liquidation {
        address kicker;         // address that initiated liquidation
        uint96  bondFactor;     // bond factor used to start liquidation
        uint96  kickTime;       // timestamp when liquidation was started
        address prev;           // previous liquidated borrower in auctions queue
        uint96  kickMomp;       // Momp when liquidation was started
        address next;           // next liquidated borrower in auctions queue
        uint160 bondSize;       // liquidation bond size
        uint96  neutralPrice;   // Neutral Price when liquidation was started
    }

    struct Kicker {
        uint256 claimable; // kicker's claimable balance
        uint256 locked;    // kicker's balance of tokens locked in auction bonds
    }

    struct TakeParams {
        uint256 quoteTokenAmount; // The quote token amount that taker should pay for collateral taken.
        uint256 t0repayAmount;    // The amount of debt (quote tokens) that is recovered / repayed by take t0 terms.
        uint256 collateralAmount;  // The amount of collateral taken.
        uint256 auctionPrice;     // The price of auction.
        uint256 bucketPrice;      // The bucket price.
        uint256 bondChange;       // The change made on the bond size (beeing reward or penalty).
        address kicker;           // Address of auction kicker.
        bool    isRewarded;       // True if kicker is rewarded (auction price lower than neutral price), false if penalized (auction price greater than neutral price).
    }

    /**
     *  @dev Struct to hold HPB details, used to prevent stack too deep error.
     */
    struct HpbLocalVars {
        uint256 index;
        uint256 deposit;
        uint256 price;
    }

    /**
     *  @notice The action cannot be executed on an active auction.
     */
    error AuctionActive();
    /**
     *  @notice Attempted auction to clear doesn't meet conditions.
     */
    error AuctionNotClearable();
    /**
     *  @notice Head auction should be cleared prior of executing this action.
     */
    error AuctionNotCleared();
    /**
     *  @notice The auction price is greater than the arbed bucket price.
     */
    error AuctionPriceGtBucketPrice();
    /**
     *  @notice Actor is attempting to take or clear an inactive auction.
     */
    error NoAuction();
    /**
     *  @notice Take was called before 1 hour had passed from kick time.
     */
    error TakeNotPastCooldown();

    /***************************/
    /***  External Functions ***/
    /***************************/

    /**
     *  @notice Settles the debt of the given loan / borrower.
     *  @notice Updates kicker's claimable balance with bond size awarded and subtracts bond size awarded from liquidationBondEscrowed.
     *  @param  collateral_          The amount of collateral available to settle debt.
     *  @param  t0DebtToSettle_      The amount of t0 debt to settle.
     *  @param  borrower_            Borrower address whose debt is settled.
     *  @param  reserves_            Pool reserves.
     *  @param  poolInflator_        Current inflator pool.
     *  @param  bucketDepth_         Max number of buckets settle action should iterate through.
     *  @return The amount of borrower collateral left after settle.
     *  @return The amount of borrower debt left after settle.
     */
    function settlePoolDebt(
        Data storage self,
        mapping(uint256 => Buckets.Bucket) storage buckets_,
        Deposits.Data storage deposits_,
        uint256 collateral_,
        uint256 t0DebtToSettle_,
        address borrower_,
        uint256 reserves_,
        uint256 poolInflator_,
        uint256 bucketDepth_
    ) external returns (uint256, uint256) {
        uint256 kickTime = self.liquidations[borrower_].kickTime;
        if (kickTime == 0) revert NoAuction();

        if ((block.timestamp - kickTime < 72 hours) && (collateral_ != 0)) revert AuctionNotClearable();

        HpbLocalVars memory hpbVars;

        // auction has debt to cover with remaining collateral
        while (bucketDepth_ != 0 && t0DebtToSettle_ != 0 && collateral_ != 0) {
            hpbVars.index   = Deposits.findIndexOfSum(deposits_, 1);
            hpbVars.deposit = Deposits.valueAt(deposits_, hpbVars.index);
            hpbVars.price   = PoolUtils.indexToPrice(hpbVars.index);

            uint256 depositToRemove = hpbVars.deposit;
            uint256 collateralUsed;

            {
                uint256 debtToSettle      = Maths.wmul(t0DebtToSettle_, poolInflator_);     // current debt to be settled
                uint256 maxSettleableDebt = Maths.wmul(collateral_, hpbVars.price);         // max debt that can be settled with existing collateral

                if (depositToRemove >= debtToSettle && maxSettleableDebt >= debtToSettle) { // enough deposit in bucket and collateral avail to settle entire debt
                    depositToRemove = debtToSettle;                                         // remove only what's needed to settle the debt
                    t0DebtToSettle_ = 0;                                                    // no remaining debt to settle
                    collateralUsed  = Maths.wdiv(debtToSettle, hpbVars.price);
                    collateral_     -= collateralUsed;
                } else if (maxSettleableDebt >= depositToRemove) {                          // enough collateral, therefore not enough deposit to settle entire debt, we settle only deposit amount
                    t0DebtToSettle_ -= Maths.wdiv(depositToRemove, poolInflator_);          // subtract from debt the corresponding t0 amount of deposit
                    collateralUsed  = Maths.wdiv(depositToRemove, hpbVars.price);
                    collateral_     -= collateralUsed;
                } else {                                                                    // constrained by collateral available
                    depositToRemove = maxSettleableDebt;
                    t0DebtToSettle_ -= Maths.wdiv(maxSettleableDebt, poolInflator_);
                    collateralUsed  = collateral_;
                    collateral_     = 0;
                }
            }

            buckets_[hpbVars.index].collateral += collateralUsed;                        // add settled collateral into bucket
            Deposits.remove(deposits_, hpbVars.index, depositToRemove, hpbVars.deposit); // remove amount to settle debt from bucket (could be entire deposit or only the settled debt)

            --bucketDepth_;
        }

        // if there's still debt and no collateral
        if (t0DebtToSettle_ != 0 && collateral_ == 0) {
            // settle debt from reserves
            t0DebtToSettle_ -= Maths.min(t0DebtToSettle_, Maths.wdiv(reserves_, poolInflator_));

            // if there's still debt after settling from reserves then start to forgive amount from next HPB
            while (bucketDepth_ != 0 && t0DebtToSettle_ != 0) { // loop through remaining buckets if there's still debt to settle
                hpbVars.index   = Deposits.findIndexOfSum(deposits_, 1);
                hpbVars.deposit = Deposits.valueAt(deposits_, hpbVars.index);

                uint256 depositToRemove = hpbVars.deposit;
                uint256 debtToSettle    = Maths.wmul(t0DebtToSettle_, poolInflator_);

                if (depositToRemove >= debtToSettle) {                             // enough deposit in bucket to settle entire debt
                    depositToRemove = debtToSettle;                                // remove only what's needed to settle the debt
                    t0DebtToSettle_ = 0;                                           // no remaining debt to settle

                } else {                                                           // not enough deposit to settle entire debt, we settle only deposit amount
                    t0DebtToSettle_ -= Maths.wdiv(depositToRemove, poolInflator_); // subtract from remaining debt the corresponding t0 amount of deposit

                    Buckets.Bucket storage hpbBucket = buckets_[hpbVars.index];
                    if (hpbBucket.collateral == 0) {                               // existing LPB and LP tokens for the bucket shall become unclaimable.
                        hpbBucket.lps = 0;
                        hpbBucket.bankruptcyTime = block.timestamp;
                    }
                }

                Deposits.remove(deposits_, hpbVars.index, depositToRemove, hpbVars.deposit);

                --bucketDepth_;
            }
        }

        return (collateral_, t0DebtToSettle_);
    }

    /**
     *  @notice Called to start borrower liquidation and to update the auctions queue.
     *  @param  borrower_          Borrower address to liquidate.
     *  @param  borrowerDebt_      Borrower debt to be recovered.
     *  @param  thresholdPrice_    Current threshold price (used to calculate bond factor).
     *  @param  momp_              Current MOMP (used to calculate bond factor).
     *  @param  neutralPrice_      Neutral Price of auction.
     *  @return kickAuctionAmount_ The amount that kicker should send to pool in order to kick auction.
     *  @return bondSize_          The amount that kicker locks in pool to kick auction.
     */
    function kick(
        Data storage self,
        address borrower_,
        uint256 borrowerDebt_,
        uint256 thresholdPrice_,
        uint256 momp_,
        uint256 neutralPrice_
    ) external returns (uint256 kickAuctionAmount_, uint256 bondSize_) {

        uint256 bondFactor;
        // bondFactor = min(30%, max(1%, (MOMP - thresholdPrice) / MOMP))
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

        // update kicker balances
        Kicker storage kicker = self.kickers[msg.sender];
        kicker.locked += bondSize_;
        if (kicker.claimable >= bondSize_) {
            kicker.claimable -= bondSize_;
        } else {
            kickAuctionAmount_ = bondSize_ - kicker.claimable;
            kicker.claimable = 0;
        }
        // update totalBondEscrowed accumulator
        self.totalBondEscrowed += bondSize_;

        // record liquidation info
        Liquidation storage liquidation = self.liquidations[borrower_];
        liquidation.kicker              = msg.sender;
        liquidation.kickTime            = uint96(block.timestamp);
        liquidation.kickMomp            = uint96(momp_);
        liquidation.bondSize            = uint160(bondSize_);
        liquidation.bondFactor          = uint96(bondFactor);
        liquidation.neutralPrice        = uint96(neutralPrice_);

        if (self.head != address(0)) {
            // other auctions in queue, liquidation doesn't exist or overwriting.
            self.liquidations[self.tail].next = borrower_;
            liquidation.prev = self.tail;
        } else {
            // first auction in queue
            self.head = borrower_;
        }

        // update liquidation with the new ordering
        self.tail = borrower_;
    }

    /**
     *  @notice Performs bucket take collateral on an auction and rewards taker and kicker (if case).
     *  @param  borrowerAddress_  Borrower address in auction.
     *  @param  borrower_         Borrower struct containing updated info of auctioned borrower.
     *  @param  bucketDeposit_    Arbed bucket deposit.
     *  @param  bucketIndex_      Bucket index.
     *  @param  depositTake_      If true then the take happens at bucket price. Auction price is used otherwise.
     *  @param  poolInflator_     The pool's inflator, used to calculate borrower debt.
     *  @return params_           Struct containing take action details.
    */
    function bucketTake(
        Data storage self,
        Deposits.Data storage deposits_,
        Buckets.Bucket storage bucket_,
        address borrowerAddress_,
        Loans.Borrower memory borrower_,
        uint256 bucketDeposit_,
        uint256 bucketIndex_,
        bool    depositTake_,
        uint256 poolInflator_
    ) external returns (TakeParams memory params_) {
        Liquidation storage liquidation = self.liquidations[borrowerAddress_];
        _validateTake(liquidation);

        params_.bucketPrice  = PoolUtils.indexToPrice(bucketIndex_);
        params_.auctionPrice = PoolUtils.auctionPrice(
            liquidation.kickMomp,
            liquidation.kickTime
        );
        // cannot arb with a price lower than the auction price
        if (params_.auctionPrice > params_.bucketPrice) revert AuctionPriceGtBucketPrice();

        // if deposit take then price to use when calculating take is bucket price
        uint256 price = depositTake_ ? params_.bucketPrice : params_.auctionPrice;
        (
            uint256 borrowerDebt,
            int256  bpf,
            uint256 factor
        ) = _takeParameters(liquidation, borrower_, price, poolInflator_);
        params_.kicker = liquidation.kicker;
        params_.isRewarded = (bpf >= 0);

        // determine how much of the loan will be repaid
        if (borrowerDebt >= bucketDeposit_) {
            params_.t0repayAmount    = Maths.wdiv(bucketDeposit_, poolInflator_);
            params_.quoteTokenAmount = Maths.wdiv(bucketDeposit_, factor);
        } else {
            params_.t0repayAmount    = borrower_.t0debt;
            params_.quoteTokenAmount = Maths.wdiv(borrowerDebt, factor);
        }

        params_.collateralAmount = Maths.wdiv(params_.quoteTokenAmount, price);

        if (params_.collateralAmount > borrower_.collateral) {
            params_.collateralAmount = borrower_.collateral;
            params_.quoteTokenAmount = Maths.wmul(params_.collateralAmount, price);
            params_.t0repayAmount    = Maths.wdiv(Maths.wmul(factor, params_.quoteTokenAmount), poolInflator_);
        }

        if (!params_.isRewarded) {
            // take is above neutralPrice, Kicker is penalized
            params_.bondChange = Maths.min(liquidation.bondSize, Maths.wmul(params_.quoteTokenAmount, uint256(-bpf)));
            liquidation.bondSize                -= uint160(params_.bondChange);
            self.kickers[params_.kicker].locked -= params_.bondChange;
            self.totalBondEscrowed              -= params_.bondChange;
        } else {
            params_.bondChange = Maths.wmul(params_.quoteTokenAmount, uint256(bpf)); // will be rewarded as LPBs
        }

        _rewardBucketTake(deposits_, bucket_, bucketDeposit_, bucketIndex_, depositTake_, params_);
    }

    /**
     *  @notice Performs take collateral on an auction and updates bond size and kicker balance accordingly.
     *  @param  borrowerAddress_  Borrower address in auction.
     *  @param  borrower_         Borrower struct containing updated info of auctioned borrower.
     *  @param  maxCollateral_    The max collateral amount to be taken from auction.
     *  @param  poolInflator_     The pool's inflator, used to calculate borrower debt.
     *  @return params_           Struct containing take action details.
    */
    function take(
        Data storage self,
        address borrowerAddress_,
        Loans.Borrower memory borrower_,
        uint256 maxCollateral_,
        uint256 poolInflator_
    ) external returns (TakeParams memory params_) {
        Liquidation storage liquidation = self.liquidations[borrowerAddress_];
        _validateTake(liquidation);

        params_.auctionPrice = PoolUtils.auctionPrice(
            liquidation.kickMomp,
            liquidation.kickTime
        );
        params_.kicker = liquidation.kicker;
        (
            uint256 borrowerDebt,
            int256 bpf,
            uint256 factor
        ) = _takeParameters(liquidation, borrower_, params_.auctionPrice, poolInflator_);
        params_.isRewarded = (bpf >= 0);

        // determine how much of the loan will be repaid
        params_.collateralAmount = Maths.min(borrower_.collateral, maxCollateral_);
        params_.quoteTokenAmount = Maths.wmul(params_.auctionPrice, params_.collateralAmount);
        params_.t0repayAmount    = Maths.wdiv(Maths.wmul(params_.quoteTokenAmount, factor), poolInflator_);

        if (params_.t0repayAmount >= borrower_.t0debt) {
            params_.t0repayAmount    = borrower_.t0debt;
            params_.quoteTokenAmount = Maths.wdiv(borrowerDebt, factor);
            params_.collateralAmount  = Maths.min(Maths.wdiv(params_.quoteTokenAmount, params_.auctionPrice), params_.collateralAmount);
        }

        if (params_.isRewarded) {
            // take is below neutralPrice, Kicker is rewarded
            params_.bondChange = Maths.wmul(params_.quoteTokenAmount, uint256(bpf));
            liquidation.bondSize                += uint160(params_.bondChange);
            self.kickers[params_.kicker].locked += params_.bondChange;
            self.totalBondEscrowed              += params_.bondChange;

        } else {
            // take is above neutralPrice, Kicker is penalized
            params_.bondChange = Maths.min(liquidation.bondSize, Maths.wmul(params_.quoteTokenAmount, uint256(-bpf)));
            liquidation.bondSize                -= uint160(params_.bondChange);
            self.kickers[params_.kicker].locked -= params_.bondChange;
            self.totalBondEscrowed              -= params_.bondChange;
        }
    }

   /**
     *  @notice Performs ERC20 auction settlement.
     *  @param  borrower_ Borrower address to settle.
     */
    function settleERC20Auction(
        Data storage self,
        address borrower_
    ) external {
        _removeAuction(self, borrower_);
    }

    /**
     *  @notice Performs NFT auction settlement by rounding down borrower's collateral amount and by moving borrower's token ids to pool claimable array.
     *  @param borrowerTokens_     Array of borrower NFT token ids.
     *  @param poolTokens_         Array of claimable NFT token ids in pool.
     *  @param borrowerAddress_    Address of the borrower that exits auction.
     *  @param borrowerCollateral_ Borrower collateral amount before auction exit (could be fragmented as result of partial takes).
     *  @return floorCollateral_   Rounded down collateral, the number of NFT tokens borrower can pull after auction exit.
     *  @return lps_               LPs given to the borrower to compensate fractional collateral (if any).
     *  @return bucketIndex_       Index of the bucket with LPs to compensate.
     */
    function settleNFTAuction(
        Data storage self,
        mapping(uint256 => Buckets.Bucket) storage buckets_,
        Deposits.Data storage deposits_,
        uint256[] storage borrowerTokens_,
        uint256[] storage poolTokens_,
        address borrowerAddress_,
        uint256 borrowerCollateral_
    ) external returns (uint256 floorCollateral_, uint256 lps_, uint256 bucketIndex_) {
        floorCollateral_ = (borrowerCollateral_ / Maths.WAD) * Maths.WAD; // floor collateral of borrower

        // if there's fraction of NFTs remaining then reward difference to borrower as LPs in auction price bucket
        if (floorCollateral_ != borrowerCollateral_) {
            // cover borrower's fractional amount with LPs in auction price bucket
            uint256 fractionalCollateral = borrowerCollateral_ - floorCollateral_;
            uint256 auctionPrice = PoolUtils.auctionPrice(
                self.liquidations[borrowerAddress_].kickMomp,
                self.liquidations[borrowerAddress_].kickTime
            );
            bucketIndex_ = PoolUtils.priceToIndex(auctionPrice);
            lps_ = Buckets.addCollateral(
                buckets_[bucketIndex_],
                borrowerAddress_,
                Deposits.valueAt(deposits_, bucketIndex_),
                fractionalCollateral,
                PoolUtils.indexToPrice(bucketIndex_)
            );
        }

        // rebalance borrower's collateral, transfer difference to floor collateral from borrower to pool claimable array
        uint256 noOfTokensPledged    = borrowerTokens_.length;
        uint256 noOfTokensToTransfer = noOfTokensPledged - floorCollateral_ / 1e18;
        for (uint256 i = 0; i < noOfTokensToTransfer;) {
            uint256 tokenId = borrowerTokens_[--noOfTokensPledged]; // start with moving the last token pledged by borrower
            borrowerTokens_.pop();                                  // remove token id from borrower
            poolTokens_.push(tokenId);                              // add token id to pool claimable tokens
            unchecked {
                ++i;
            }
        }

        _removeAuction(self, borrowerAddress_);
    }


    /***************************/
    /***  Internal Functions ***/
    /***************************/

    /**
     *  @notice Removes auction and repairs the queue order.
     *  @notice Updates kicker's claimable balance with bond size awarded and subtracts bond size awarded from liquidationBondEscrowed.
     *  @param  borrower_ Auctioned borrower address.
     */
    function _removeAuction(
        Data storage self,
        address borrower_
    ) internal {
        Liquidation memory liquidation = self.liquidations[borrower_];
        // update kicker balances
        Kicker storage kicker = self.kickers[liquidation.kicker];
        kicker.locked    -= liquidation.bondSize;
        kicker.claimable += liquidation.bondSize;

        // remove auction bond size from bond escrow accumulator 
        self.totalBondEscrowed -= liquidation.bondSize;

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

    /**
     *  @notice Rewards actors of a bucket take action.
     *  @param  bucketDeposit_ Arbed bucket deposit.
     *  @param  bucketIndex_   Bucket index.
     *  @param  params_        Struct containing take action details.
     */
    function _rewardBucketTake(
        Deposits.Data storage deposits_,
        Buckets.Bucket storage bucket_,
        uint256 bucketDeposit_,
        uint256 bucketIndex_,
        bool depositTake_,
        TakeParams memory params_
    ) internal {
        uint256 bucketExchangeRate = Buckets.getExchangeRate(
            bucket_.collateral,
            bucket_.lps,
            bucketDeposit_,
            params_.bucketPrice
        );

        // if arb take - taker is awarded collateral * (bucket price - auction price) worth (in quote token terms) units of LPB in the bucket
        if (!depositTake_) Buckets.addLPs(
            bucket_,
            msg.sender,
            Maths.wrdivr(
                Maths.wmul(params_.collateralAmount, params_.bucketPrice - params_.auctionPrice),
                bucketExchangeRate
            )
        );
        bucket_.collateral += params_.collateralAmount; // collateral is added to the bucket’s claimable collateral

        // the bondholder/kicker is awarded bond change worth of LPB in the bucket
        uint256 depositAmountToRemove = params_.quoteTokenAmount;
        if (params_.isRewarded) {
            Buckets.addLPs(
                bucket_,
                params_.kicker,
                Maths.wrdivr(params_.bondChange, bucketExchangeRate)
            );
            depositAmountToRemove -= params_.bondChange;
        }
        Deposits.remove(deposits_, bucketIndex_, depositAmountToRemove, bucketDeposit_); // remove quote tokens from bucket’s deposit
    }

    /**
     *  @notice Utility function to validate take action.
     *  @param  liquidation_  Liquidation struct holding auction details.
     */
    function _validateTake(
        Liquidation storage liquidation_
    ) internal view {
        if (liquidation_.kickTime == 0) revert NoAuction();
        if (block.timestamp - liquidation_.kickTime <= 1 hours) revert TakeNotPastCooldown();
    }

    /**
     *  @notice Utility function to calculate take's parameters.
     *  @param  liquidation_  Liquidation struct holding auction details.
     *  @param  borrower_     Borrower struct holding details of the borrower being liquidated.
     *  @param  price_        The price to be used by take.
     *  @param  poolInflator_ The pool's inflator, used to calculate borrower debt.
     *  @return borrowerDebt_ The debt of auctioned borrower.
     *  @return bpf_          The bond penalty factor.
     *  @return factor_       The take factor, calculated based on bond penalty factor.
     */
    function _takeParameters(
        Liquidation storage liquidation_,
        Loans.Borrower memory borrower_,
        uint256 price_,
        uint256 poolInflator_
    ) internal view returns (
        uint256 borrowerDebt_,
        int256  bpf_,
        uint256 factor_
    ) {
        // calculate the bond payment factor
        borrowerDebt_ = Maths.wmul(borrower_.t0debt, poolInflator_);
        bpf_ = PoolUtils.bpf(
            borrowerDebt_,
            borrower_.collateral,
            liquidation_.neutralPrice,
            liquidation_.bondFactor,
            price_
        );
        factor_ = uint256(1e18 - Maths.maxInt(0, bpf_));
    }

    /**********************/
    /*** View Functions ***/
    /**********************/

    /**
     *  @notice Check if there is an ongoing auction for current borrower and revert if such.
     *  @dev    Used to prevent an auctioned borrower to draw more debt or while in liquidation.
     *  @dev    Used to prevent kick on an auctioned borrower.
     *  @param  borrower_ Borrower address to check auction status for.
     */
    function revertIfActive(
        Data storage self,
        address borrower_
    ) internal view {
        if (isActive(self, borrower_)) revert AuctionActive();
    }

    /**
     *  @notice Returns true if borrower is in auction.
     *  @dev    Used to accuratley increment and decrement t0DebtInAuction.
     *  @param  borrower_ Borrower address to check auction status for.
     *  @return  active_ Boolean, based on if borrower is in auction.
     */
    function isActive(
        Data storage self,
        address borrower_
    ) internal view returns (bool) {
        return self.liquidations[borrower_].kickTime != 0;
    }

    /**
     *  @notice Check if head auction is clearable (auction is kicked and 72 hours passed since kick time or auction still has debt but no remaining collateral).
     *  @notice Revert if auction is clearable
     */
    function revertIfAuctionClearable(
        Data storage self,
        Loans.Data storage loans_
    ) internal view {
        address head     = self.head;
        uint256 kickTime = self.liquidations[head].kickTime;
        if (
            kickTime != 0
            &&
            (
                block.timestamp - kickTime > 72 hours
                ||
                (loans_.borrowers[head].t0debt != 0 && loans_.borrowers[head].collateral == 0)
            )
        ) revert AuctionNotCleared();
    }

}
