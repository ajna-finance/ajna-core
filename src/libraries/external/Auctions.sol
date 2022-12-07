// SPDX-License-Identifier: MIT

pragma solidity 0.8.14;

import { PRBMathSD59x18 } from "@prb-math/contracts/PRBMathSD59x18.sol";

import '../Buckets.sol';
import '../Loans.sol';

import '../../base/PoolHelper.sol';
import '../../base/Pool.sol';

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

    struct TakeResult {
        uint256 quoteTokenAmount; // The quote token amount that taker should pay for collateral taken.
        uint256 t0repayAmount;    // The amount of debt (quote tokens) that is recovered / repayed by take t0 terms.
        uint256 collateralAmount;  // The amount of collateral taken.
        uint256 auctionPrice;     // The price of auction.
        uint256 bucketPrice;      // The bucket price.
        uint256 bondChange;       // The change made on the bond size (beeing reward or penalty).
        address kicker;           // Address of auction kicker.
        bool    isRewarded;       // True if kicker is rewarded (auction price lower than neutral price), false if penalized (auction price greater than neutral price).
    }

    struct SettleParams {
        address borrower;    // borrower address to settle
        uint256 collateral;  // remaining collateral pledged by borrower that can be used to settle debt
        uint256 t0debt;      // borrower t0 debt to settle 
        uint256 reserves;    // current reserves in pool
        uint256 inflator;    // current pool inflator
        uint256 bucketDepth; // number of buckets to use when settle debt
    }

    struct KickParams {
        address borrower;       // borrower address to kick
        uint256 collateral;     // borrower collateral
        uint256 debt;           // borrower debt 
        uint256 momp;           // loan's MOMP
        uint256 neutralPrice;   // loan's Neutral Price
        uint256 rate;           // pool's Interest Rate
    }

    struct TakeParams {
        address borrower;       // borrower address to take from
        uint256 collateral;     // borrower available collateral to take
        uint256 t0debt;         // borrower t0 debt
        uint256 takeCollateral; // desired amount to take
        uint256 inflator;       // current pool inflator
        bool    depositTake;    // deposit or arb take, used by bucket take
        uint256 index;          // bucket index, used by bucket take
    }

    struct StartReserveAuctionParams {
        uint256 poolSize;    // total deposits in pool (with accrued debt)
        uint256 poolDebt;    // current t0 pool debt
        uint256 poolBalance; // pool quote token balance
        uint256 inflator;    // pool current inflator
    }

    event BucketTake(
        address indexed borrower,
        uint256 index,
        uint256 amount,
        uint256 collateral,
        uint256 bondChange,
        bool    isReward
    );

    event Kick(
        address indexed borrower,
        uint256 debt,
        uint256 collateral,
        uint256 bond
    );

    event Take(
        address indexed borrower,
        uint256 amount,
        uint256 collateral,
        uint256 bondChange,
        bool    isReward
    );

    event ReserveAuction(
        uint256 claimableReservesRemaining,
        uint256 auctionPrice
    );

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
     *  @notice Bucket to arb must have more quote available in the bucket.
     */
    error InsufficientLiquidity();
    /**
     *  @notice User is attempting to take more collateral than available.
     */
    error InsufficientCollateral();
    /**
     *  @notice Actor is attempting to take or clear an inactive auction.
     */
    error NoAuction();
    /**
     *  @notice No pool reserves are claimable.
     */
    error NoReserves();
    /**
     *  @notice Actor is attempting to take or clear an inactive reserves auction.
     */
    error NoReservesAuction();
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
     *  @param  params_ Settle params
     *  @return The amount of borrower collateral left after settle.
     *  @return The amount of borrower debt left after settle.
     */
    function settlePoolDebt(
        Data storage self,
        mapping(uint256 => Buckets.Bucket) storage buckets_,
        Deposits.Data storage deposits_,
        SettleParams memory params_
    ) external returns (uint256, uint256) {
        uint256 kickTime = self.liquidations[params_.borrower].kickTime;
        if (kickTime == 0) revert NoAuction();

        if ((block.timestamp - kickTime < 72 hours) && (params_.collateral != 0)) revert AuctionNotClearable();

        // HpbLocalVars memory hpbVars;

        // auction has debt to cover with remaining collateral
        while (params_.bucketDepth != 0 && params_.t0debt != 0 && params_.collateral != 0) {
            uint256 index   = Deposits.findIndexOfSum(deposits_, 1);
            uint256 deposit = Deposits.valueAt(deposits_, index);
            uint256 price   = _priceAt(index);

            uint256 depositToRemove = deposit;
            uint256 collateralUsed;

            {
                uint256 debtToSettle      = Maths.wmul(params_.t0debt, params_.inflator);     // current debt to be settled
                uint256 maxSettleableDebt = Maths.wmul(params_.collateral, price);          // max debt that can be settled with existing collateral

                if (depositToRemove >= debtToSettle && maxSettleableDebt >= debtToSettle) { // enough deposit in bucket and collateral avail to settle entire debt
                    depositToRemove    = debtToSettle;                                      // remove only what's needed to settle the debt
                    params_.t0debt    = 0;                                                 // no remaining debt to settle
                    collateralUsed     = Maths.wdiv(debtToSettle, price);
                    params_.collateral -= collateralUsed;
                } else if (maxSettleableDebt >= depositToRemove) {                          // enough collateral, therefore not enough deposit to settle entire debt, we settle only deposit amount
                    params_.t0debt     -= Maths.wdiv(depositToRemove, params_.inflator);    // subtract from debt the corresponding t0 amount of deposit
                    collateralUsed     = Maths.wdiv(depositToRemove, price);
                    params_.collateral -= collateralUsed;
                } else {                                                                    // constrained by collateral available
                    depositToRemove    = maxSettleableDebt;
                    params_.t0debt     -= Maths.wdiv(maxSettleableDebt, params_.inflator);
                    collateralUsed     = params_.collateral;
                    params_.collateral = 0;
                }
            }

            buckets_[index].collateral += collateralUsed;                // add settled collateral into bucket
            Deposits.remove(deposits_, index, depositToRemove, deposit); // remove amount to settle debt from bucket (could be entire deposit or only the settled debt)

            --params_.bucketDepth;
        }

        // if there's still debt and no collateral
        if (params_.t0debt != 0 && params_.collateral == 0) {
            // settle debt from reserves
            params_.t0debt -= Maths.min(params_.t0debt, Maths.wdiv(params_.reserves, params_.inflator));

            // if there's still debt after settling from reserves then start to forgive amount from next HPB
            while (params_.bucketDepth != 0 && params_.t0debt != 0) { // loop through remaining buckets if there's still debt to settle
                uint256 index   = Deposits.findIndexOfSum(deposits_, 1);
                uint256 deposit = Deposits.valueAt(deposits_, index);

                uint256 depositToRemove = deposit;
                uint256 debtToSettle    = Maths.wmul(params_.t0debt, params_.inflator);

                if (depositToRemove >= debtToSettle) {                               // enough deposit in bucket to settle entire debt
                    depositToRemove = debtToSettle;                                  // remove only what's needed to settle the debt
                    params_.t0debt  = 0;                                             // no remaining debt to settle

                } else {                                                             // not enough deposit to settle entire debt, we settle only deposit amount
                    params_.t0debt -= Maths.wdiv(depositToRemove, params_.inflator); // subtract from remaining debt the corresponding t0 amount of deposit

                    Buckets.Bucket storage hpbBucket = buckets_[index];
                    if (hpbBucket.collateral == 0) {                                 // existing LPB and LP tokens for the bucket shall become unclaimable.
                        hpbBucket.lps = 0;
                        hpbBucket.bankruptcyTime = block.timestamp;
                    }
                }

                Deposits.remove(deposits_, index, depositToRemove, deposit);

                --params_.bucketDepth;
            }
        }

        return (params_.collateral, params_.t0debt);
    }

    /**
     *  @notice Called to start borrower liquidation and to update the auctions queue.
     *  @param  params_            Kick params.
     *  @return kickAuctionAmount_ The amount that kicker should send to pool in order to kick auction.
     *  @return kickPenalty_       The kick penalty (three months of interest).
     */
    function kick(
        Data storage self,
        KickParams calldata params_
    ) external returns (uint256 kickAuctionAmount_, uint256 kickPenalty_) {
        uint256 thresholdPrice = params_.debt  * Maths.WAD / params_.collateral;
        uint256 bondFactor;
        // bondFactor = min(30%, max(1%, (MOMP - thresholdPrice) / MOMP))
        if (thresholdPrice >= params_.momp) {
            bondFactor = 0.01 * 1e18;
        } else {
            bondFactor = Maths.min(
                0.3 * 1e18,
                Maths.max(
                    0.01 * 1e18,
                    1e18 - Maths.wdiv(thresholdPrice, params_.momp)
                )
            );
        }

        // update kicker balances
        uint256 bondSize = Maths.wmul(bondFactor,  params_.debt);
        Kicker storage kicker = self.kickers[msg.sender];
        kicker.locked += bondSize;
        uint256 kickerClaimable = kicker.claimable;
        if (kickerClaimable >= bondSize) {
            kicker.claimable -= bondSize;
        } else {
            kickAuctionAmount_ = bondSize - kickerClaimable;
            kicker.claimable = 0;
        }
        // update totalBondEscrowed accumulator
        self.totalBondEscrowed += bondSize;

        // record liquidation info
        Liquidation storage liquidation = self.liquidations[ params_.borrower];
        liquidation.kicker              = msg.sender;
        liquidation.kickTime            = uint96(block.timestamp);
        liquidation.kickMomp            = uint96(params_.momp);
        liquidation.bondSize            = uint160(bondSize);
        liquidation.bondFactor          = uint96(bondFactor);
        liquidation.neutralPrice        = uint96(params_.neutralPrice);

        if (self.head != address(0)) {
            // other auctions in queue, liquidation doesn't exist or overwriting.
            self.liquidations[self.tail].next =  params_.borrower;
            liquidation.prev = self.tail;
        } else {
            // first auction in queue
            self.head = params_.borrower;
        }

        // update liquidation with the new ordering
        self.tail =  params_.borrower;

        // when loan is kicked, penalty of three months of interest is added
        kickPenalty_ = Maths.wmul(Maths.wdiv(params_.rate, 4 * 1e18), params_.debt );
        emit Kick(
            params_.borrower,
            params_.debt + kickPenalty_,
            params_.collateral,
            bondSize
        );
    }

    /**
     *  @notice Performs bucket take collateral on an auction and rewards taker and kicker (if case).
     *  @param  params_ Struct containing take action details.
     *  @return Collateral amount taken.
     *  @return T0 debt amount repaid.
    */
    function bucketTake(
        Data storage self,
        Deposits.Data storage deposits_,
        mapping(uint256 => Buckets.Bucket) storage buckets_,
        TakeParams calldata params_
    ) external returns (uint256, uint256) {
        if (params_.collateral == 0) revert InsufficientCollateral(); // revert if borrower's collateral is 0

        uint256 bucketDeposit = Deposits.valueAt(deposits_, params_.index);
        if (bucketDeposit == 0) revert InsufficientLiquidity(); // revert if no quote tokens in arbed bucket

        Liquidation storage liquidation = self.liquidations[params_.borrower];

        uint256 kickTime = liquidation.kickTime;
        if (kickTime == 0) revert NoAuction();
        if (block.timestamp - kickTime <= 1 hours) revert TakeNotPastCooldown();

        TakeResult memory result;
        result.bucketPrice  = _priceAt(params_.index);
        result.auctionPrice = _auctionPrice(
            liquidation.kickMomp,
            kickTime
        );
        // cannot arb with a price lower than the auction price
        if (result.auctionPrice > result.bucketPrice) revert AuctionPriceGtBucketPrice();

        // if deposit take then price to use when calculating take is bucket price
        uint256 price = params_.depositTake ? result.bucketPrice : result.auctionPrice;
        (
            uint256 borrowerDebt,
            int256  bpf,
            uint256 factor
        ) = _takeParameters(
            liquidation,
            params_.collateral,
            params_.t0debt,
            price,
            params_.inflator
        );
        result.kicker = liquidation.kicker;
        result.isRewarded = (bpf >= 0);

        // determine how much of the loan will be repaid
        if (borrowerDebt >= bucketDeposit) {
            result.t0repayAmount    = Maths.wdiv(bucketDeposit, params_.inflator);
            result.quoteTokenAmount = Maths.wdiv(bucketDeposit, factor);
        } else {
            result.t0repayAmount    = params_.t0debt;
            result.quoteTokenAmount = Maths.wdiv(borrowerDebt, factor);
        }

        result.collateralAmount = Maths.wdiv(result.quoteTokenAmount, price);

        if (result.collateralAmount > params_.collateral) {
            result.collateralAmount = params_.collateral;
            result.quoteTokenAmount = Maths.wmul(result.collateralAmount, price);
            result.t0repayAmount    = Maths.wdiv(Maths.wmul(factor, result.quoteTokenAmount), params_.inflator);
        }

        if (!result.isRewarded) {
            // take is above neutralPrice, Kicker is penalized
            result.bondChange = Maths.min(liquidation.bondSize, Maths.wmul(result.quoteTokenAmount, uint256(-bpf)));
            liquidation.bondSize                -= uint160(result.bondChange);
            self.kickers[result.kicker].locked -= result.bondChange;
            self.totalBondEscrowed              -= result.bondChange;
        } else {
            result.bondChange = Maths.wmul(result.quoteTokenAmount, uint256(bpf)); // will be rewarded as LPBs
        }

        _rewardBucketTake(
            deposits_,
            buckets_,
            bucketDeposit,
            params_.index,
            params_.depositTake,
            result
        );

        emit BucketTake(
            params_.borrower,
            params_.index,
            result.quoteTokenAmount,
            result.collateralAmount,
            result.bondChange,
            result.isRewarded
        );
        return(result.collateralAmount, result.t0repayAmount);

    }

    /**
     *  @notice Performs take collateral on an auction and updates bond size and kicker balance accordingly.
     *  @param  params_ Struct containing take action params details.
     *  @return Collateral amount taken.
     *  @return Quote token to be received from taker.
     *  @return T0 debt amount repaid.
     *  @return Auction price.
    */
    function take(
        Data storage self,
        TakeParams calldata params_
    ) external returns (uint256, uint256, uint256, uint256) {
        Liquidation storage liquidation = self.liquidations[params_.borrower];

        uint256 kickTime = liquidation.kickTime;
        if (kickTime == 0) revert NoAuction();
        if (block.timestamp - kickTime <= 1 hours) revert TakeNotPastCooldown();

        TakeResult memory result;
        result.auctionPrice = _auctionPrice(
            liquidation.kickMomp,
            kickTime
        );
        result.kicker = liquidation.kicker;
        (
            uint256 borrowerDebt,
            int256 bpf,
            uint256 factor
        ) = _takeParameters(
            liquidation,
            params_.collateral,
            params_.t0debt,
            result.auctionPrice,
            params_.inflator
        );
        result.isRewarded = (bpf >= 0);

        // determine how much of the loan will be repaid
        result.collateralAmount = Maths.min(params_.collateral, params_.takeCollateral);
        result.quoteTokenAmount = Maths.wmul(result.auctionPrice, result.collateralAmount);
        result.t0repayAmount    = Maths.wdiv(Maths.wmul(result.quoteTokenAmount, factor), params_.inflator);

        if (result.t0repayAmount >= params_.t0debt) {
            result.t0repayAmount    = params_.t0debt;
            result.quoteTokenAmount = Maths.wdiv(borrowerDebt, factor);
            result.collateralAmount = Maths.min(Maths.wdiv(result.quoteTokenAmount, result.auctionPrice), result.collateralAmount);
        }

        if (result.isRewarded) {
            // take is below neutralPrice, Kicker is rewarded
            result.bondChange = Maths.wmul(result.quoteTokenAmount, uint256(bpf));
            liquidation.bondSize                += uint160(result.bondChange);
            self.kickers[result.kicker].locked += result.bondChange;
            self.totalBondEscrowed              += result.bondChange;

        } else {
            // take is above neutralPrice, Kicker is penalized
            result.bondChange = Maths.min(liquidation.bondSize, Maths.wmul(result.quoteTokenAmount, uint256(-bpf)));
            liquidation.bondSize                -= uint160(result.bondChange);
            self.kickers[result.kicker].locked -= result.bondChange;
            self.totalBondEscrowed              -= result.bondChange;
        }

        emit Take(
            params_.borrower,
            result.quoteTokenAmount,
            result.collateralAmount,
            result.bondChange,
            result.isRewarded
        );
        return (
            result.collateralAmount,
            result.quoteTokenAmount,
            result.t0repayAmount,
            result.auctionPrice
        );
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
            uint256 auctionPrice = _auctionPrice(
                self.liquidations[borrowerAddress_].kickMomp,
                self.liquidations[borrowerAddress_].kickTime
            );
            bucketIndex_ = _indexOf(auctionPrice);
            lps_ = Buckets.addCollateral(
                buckets_[bucketIndex_],
                borrowerAddress_,
                Deposits.valueAt(deposits_, bucketIndex_),
                fractionalCollateral,
                _priceAt(bucketIndex_)
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

    /***********************/
    /*** Reserve Auction ***/
    /***********************/

    function startClaimableReserveAuction(
        Data storage self,
        Pool.ReserveAuctionParams storage reserveAuction_,
        StartReserveAuctionParams calldata params_
    ) external returns (uint256 kickerAward_) {
        uint256 curUnclaimedAuctionReserve = reserveAuction_.unclaimed;
        uint256 claimable = _claimableReserves(
            Maths.wmul(params_.poolDebt, params_.inflator),
            params_.poolSize,
            self.totalBondEscrowed,
            curUnclaimedAuctionReserve,
            params_.poolBalance
        );
        kickerAward_ = Maths.wmul(0.01 * 1e18, claimable);
        curUnclaimedAuctionReserve += claimable - kickerAward_;
        if (curUnclaimedAuctionReserve == 0) revert NoReserves();

        reserveAuction_.unclaimed = curUnclaimedAuctionReserve;
        reserveAuction_.kicked    = block.timestamp;
        emit ReserveAuction(curUnclaimedAuctionReserve, _reserveAuctionPrice(block.timestamp));
    }

    function takeReserves(
        Pool.ReserveAuctionParams storage reserveAuction_,
        uint256 maxAmount_
    ) external returns (uint256 amount_, uint256 ajnaRequired_) {
        uint256 kicked = reserveAuction_.kicked;

        if (kicked != 0 && block.timestamp - kicked <= 72 hours) {
            uint256 unclaimed = reserveAuction_.unclaimed;
            uint256 price     = _reserveAuctionPrice(kicked);

            amount_       = Maths.min(unclaimed, maxAmount_);
            ajnaRequired_ = Maths.wmul(amount_, price);

            unclaimed -= amount_;
            reserveAuction_.unclaimed = unclaimed;

            emit ReserveAuction(unclaimed, price);
        } else revert NoReservesAuction();
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
     *  @param  result_        Struct containing take action result details.
     */
    function _rewardBucketTake(
        Deposits.Data storage deposits_,
        mapping(uint256 => Buckets.Bucket) storage buckets_,
        uint256 bucketDeposit_,
        uint256 bucketIndex_,
        bool depositTake_,
        TakeResult memory result_
    ) internal {
        Buckets.Bucket storage bucket = buckets_[bucketIndex_];
        uint256 bucketExchangeRate = Buckets.getExchangeRate(
            bucket.collateral,
            bucket.lps,
            bucketDeposit_,
            result_.bucketPrice
        );

        uint256 bankruptcyTime = bucket.bankruptcyTime;
        uint256 totalLPsReward;
        // if arb take - taker is awarded collateral * (bucket price - auction price) worth (in quote token terms) units of LPB in the bucket
        if (!depositTake_) {
            uint256 takerLPsReward = Maths.wrdivr(
                Maths.wmul(result_.collateralAmount, result_.bucketPrice - result_.auctionPrice),
                bucketExchangeRate
            );

            totalLPsReward += takerLPsReward;
            Buckets.addLenderLPs(bucket, bankruptcyTime, msg.sender, takerLPsReward);
        }

        // the bondholder/kicker is awarded bond change worth of LPB in the bucket
        uint256 depositAmountToRemove = result_.quoteTokenAmount;
        if (result_.isRewarded) {
            uint256 kickerLPsReward = Maths.wrdivr(result_.bondChange, bucketExchangeRate);
            depositAmountToRemove -= result_.bondChange;

            totalLPsReward += kickerLPsReward;
            Buckets.addLenderLPs(bucket, bankruptcyTime, result_.kicker, kickerLPsReward);
        }

        Deposits.remove(deposits_, bucketIndex_, depositAmountToRemove, bucketDeposit_); // remove quote tokens from bucket’s deposit

        // total rewarded LPs are added to the bucket LP balance
        bucket.lps += totalLPsReward;
        // collateral is added to the bucket’s claimable collateral
        bucket.collateral += result_.collateralAmount;
    }

    function _auctionPrice(
        uint256 referencePrice,
        uint256 kickTime_
    ) internal view returns (uint256 price_) {
        uint256 elapsedHours = Maths.wdiv((block.timestamp - kickTime_) * 1e18, 1 hours * 1e18);
        elapsedHours -= Maths.min(elapsedHours, 1e18);  // price locked during cure period

        int256 timeAdjustment = PRBMathSD59x18.mul(-1 * 1e18, int256(elapsedHours));
        price_ = 32 * Maths.wmul(referencePrice, uint256(PRBMathSD59x18.exp2(timeAdjustment)));
    }

    /**
     *  @notice Calculates bond penalty factor.
     *  @dev Called in kick and take.
     *  @param debt_             Borrower debt.
     *  @param collateral_       Borrower collateral.
     *  @param neutralPrice_     NP of auction.
     *  @param bondFactor_       Factor used to determine bondSize.
     *  @param price_            Auction price at the time of call.
     *  @return bpf_             Factor used in determining bond Reward (positive) or penalty (negative).
     */
    function _bpf(
        uint256 debt_,
        uint256 collateral_,
        uint256 neutralPrice_,
        uint256 bondFactor_,
        uint256 price_
    ) internal pure returns (int256) {
        int256 thresholdPrice = int256(Maths.wdiv(debt_, collateral_));

        int256 sign;
        if (thresholdPrice < int256(neutralPrice_)) {
            // BPF = BondFactor * min(1, max(-1, (neutralPrice - price) / (neutralPrice - thresholdPrice)))
            sign = Maths.minInt(
                    1e18,
                    Maths.maxInt(
                        -1 * 1e18,
                        PRBMathSD59x18.div(
                            int256(neutralPrice_) - int256(price_),
                            int256(neutralPrice_) - thresholdPrice
                        )
                    )
            );
        } else {
            int256 val = int256(neutralPrice_) - int256(price_);
            if (val < 0 )      sign = -1e18;
            else if (val != 0) sign = 1e18;
        }

        return PRBMathSD59x18.mul(int256(bondFactor_), sign);
    }

    /**
     *  @notice Utility function to calculate take's parameters.
     *  @param  liquidation_  Liquidation struct holding auction details.
     *  @param  collateral_   Borrower collateral.
     *  @param  t0Debt_       Borrower t0 debt.
     *  @param  poolInflator_ The pool's inflator, used to calculate borrower debt.
     *  @return borrowerDebt_ The debt of auctioned borrower.
     *  @return bpf_          The bond penalty factor.
     *  @return factor_       The take factor, calculated based on bond penalty factor.
     */
    function _takeParameters(
        Liquidation storage liquidation_,
        uint256 collateral_,
        uint256 t0Debt_,
        uint256 price_,
        uint256 poolInflator_
    ) internal view returns (
        uint256 borrowerDebt_,
        int256  bpf_,
        uint256 factor_
    ) {
        // calculate the bond payment factor
        borrowerDebt_ = Maths.wmul(t0Debt_, poolInflator_);
        bpf_ = _bpf(
            borrowerDebt_,
            collateral_,
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
        if (kickTime != 0) {
            if (block.timestamp - kickTime > 72 hours) revert AuctionNotCleared();

            Loans.Borrower storage borrower = loans_.borrowers[head];
            if (borrower.t0debt != 0 && borrower.collateral == 0) revert AuctionNotCleared();
        }
    }

}
