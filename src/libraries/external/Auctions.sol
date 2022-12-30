// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.14;

import { PRBMathSD59x18 } from "@prb-math/contracts/PRBMathSD59x18.sol";

import {
    PoolState,
    DepositsState,
    AuctionsState,
    Liquidation,
    Kicker,
    ReserveAuctionState,
    SettleParams,
    KickResult,
    BucketTakeParams,
    TakeParams,
    StartReserveAuctionParams
} from '../../base/interfaces/IPool.sol';

import '../Buckets.sol';
import '../Deposits.sol';
import '../Loans.sol';

import '../../base/PoolHelper.sol';

library Auctions {

    struct KickWithDepositLocalVars {
        uint256 bucketLPs;
        uint256 bucketCollateral;
        uint256 bucketPrice;
        uint256 bucketUnscaledDeposit;
        uint256 bucketScale;
        uint256 bucketDeposit;
        uint256 lenderLPs;
        uint256 bucketRate;
        uint256 amountToDebitFromDeposit;
        uint256 redeemedLPs;
    }

    struct TakeResult {
        uint256 auctionPrice;             // The price of auction.
        uint256 bondChange;               // The change made on the bond size (beeing reward or penalty).
        uint256 borrowerDebt;             // The accrued debt of auctioned borrower.
        int256  bpf;                      // The bond penalty factor.
        uint256 bucketPrice;              // The bucket price.
        uint256 bucketScale;              // The bucket scale.
        uint256 collateralAmount;         // The amount of collateral taken.
        uint256 factor;                   // The take factor, calculated based on bond penalty factor.
        bool    isRewarded;               // True if kicker is rewarded (auction price lower than neutral price), false if penalized (auction price greater than neutral price).
        address kicker;                   // Address of auction kicker.
        uint256 scaledQuoteTokenAmount;   // Unscaled quantity in Fenwick tree and before 1-bpf factor, paid for collateral
        uint256 t0RepayAmount;            // The amount of debt (quote tokens) that is recovered / repayed by take t0 terms.
        uint256 t0Debt;                   // Borrower's t0 debt.
        uint256 t0DebtPenalty;            // Borrower's t0 penalty - 7% from current debt if intial take, 0 otherwise.
        uint256 unscaledDeposit;          // Unscaled bucket quantity
        uint256 unscaledQuoteTokenAmount; // The unscaled token amount that taker should pay for collateral taken.
    }

    /**
     *  @notice Emitted when an actor uses quote token to arb higher-priced deposit off the book.
     *  @param  borrower    Identifies the loan being liquidated.
     *  @param  index       The index of the Highest Price Bucket used for this take.
     *  @param  amount      Amount of quote token used to purchase collateral.
     *  @param  collateral  Amount of collateral purchased with quote token.
     *  @param  bondChange  Impact of this take to the liquidation bond.
     *  @param  isReward    True if kicker was rewarded with `bondChange` amount, false if kicker was penalized.
     *  @dev    amount / collateral implies the auction price.
     */
    event BucketTake(
        address indexed borrower,
        uint256 index,
        uint256 amount,
        uint256 collateral,
        uint256 bondChange,
        bool    isReward
    );

    /**
     *  @notice Emitted when LPs are awarded to a taker or kicker in a bucket take.
     *  @param  taker           Actor who invoked the bucket take.
     *  @param  kicker          Actor who started the auction.
     *  @param  lpAwardedTaker  Amount of LP awarded to the taker.
     *  @param  lpAwardedKicker Amount of LP awarded to the actor who started the auction.
     */
    event BucketTakeLPAwarded(
        address indexed taker,
        address indexed kicker,
        uint256 lpAwardedTaker,
        uint256 lpAwardedKicker
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

    /**
     *  @notice Emitted when lender kick and remove quote token from the pool.
     *  @param  lender     Recipient that removed quote tokens.
     *  @param  price      Price at which quote tokens were removed.
     *  @param  amount     Amount of quote tokens removed from the pool.
     *  @param  lpRedeemed Amount of LP exchanged for quote token.
     *  @param  lup        LUP calculated after removal.
     */
    event RemoveQuoteToken(
        address indexed lender,
        uint256 indexed price,
        uint256 amount,
        uint256 lpRedeemed,
        uint256 lup
    );

    event ReserveAuction(
        uint256 claimableReservesRemaining,
        uint256 auctionPrice
    );

    /**
     *  @notice Emitted when an actor settles debt in a completed liquidation
     *  @param  borrower   Identifies the loan under liquidation.
     *  @param  settledDebt Amount of pool debt settled in this transaction.
     *  @dev    When amountRemaining_ == 0, the auction has been completed cleared and removed from the queue.
     */
    event Settle(
        address indexed borrower,
        uint256 settledDebt
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
     *  @notice Borrower has a healthy over-collateralized position.
     */
    error BorrowerOk();
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
     *  @notice Actor is attempting to remove using a bucket with price below the LUP.
     */
    error PriceBelowLUP();
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
        AuctionsState storage auctions_,
        mapping(uint256 => Bucket) storage buckets_,
        DepositsState storage deposits_,
        SettleParams memory params_
    ) external returns (uint256, uint256) {
        uint256 kickTime = auctions_.liquidations[params_.borrower].kickTime;
        if (kickTime == 0) revert NoAuction();

        if ((block.timestamp - kickTime < 72 hours) && (params_.collateral != 0)) revert AuctionNotClearable();

        uint256 t0DebtInitial = params_.t0Debt;

        // auction has debt to cover with remaining collateral
        while (params_.bucketDepth != 0 && params_.t0Debt != 0 && params_.collateral != 0) {
            uint256 index           = Deposits.findIndexOfSum(deposits_, 1);
            uint256 unscaledDeposit = Deposits.unscaledValueAt(deposits_, index);
            uint256 scale           = Deposits.scale(deposits_, index);
            uint256 price           = _priceAt(index);
            uint256 collateralUsed;

            if (unscaledDeposit != 0) {
                uint256 debt              = Maths.wmul(params_.t0Debt, params_.inflator);   // current debt to be settled
                uint256 maxSettleableDebt = Maths.wmul(params_.collateral, price);          // max debt that can be settled with existing collateral
                uint256 scaledDeposit     = Maths.wmul(scale, unscaledDeposit);

                if (scaledDeposit >= debt && maxSettleableDebt >= debt) {                   // enough deposit in bucket and collateral avail to settle entire debt
                    unscaledDeposit = Maths.wdiv(debt, scale);                              // remove only what's needed to settle the debt
                    params_.t0Debt    = 0;                                                  // no remaining debt to settle
                    collateralUsed     = Maths.wdiv(debt, price);
                } else if (maxSettleableDebt >= scaledDeposit) {                            // enough collateral, therefore not enough deposit to settle entire debt, we settle only deposit amount
                    params_.t0Debt     -= Maths.wdiv(scaledDeposit, params_.inflator);      // subtract from debt the corresponding t0 amount of deposit
                    collateralUsed     = Maths.wdiv(scaledDeposit, price);
                } else {                                                                    // constrained by collateral available
                    unscaledDeposit    = Maths.wdiv(maxSettleableDebt, scale);
                    params_.t0Debt     -= Maths.wdiv(maxSettleableDebt, params_.inflator);
                    collateralUsed     = params_.collateral;
                }

                params_.collateral         -= collateralUsed;                // move settled collateral from loan into bucket
                buckets_[index].collateral += collateralUsed;
                Deposits.unscaledRemove(deposits_, index, unscaledDeposit); // remove amount to settle debt from bucket (could be entire deposit or only the settled debt)
            } else {
                // Deposits in the tree is zero, insert entire collateral into lowest bucket 7388
                Buckets.addCollateral(
                    buckets_[index],
                    params_.borrower,
                    0,  // zero deposit in bucket
                    params_.collateral,
                    price
                );
                params_.collateral = 0; // entire collateral added into bucket
            }

            --params_.bucketDepth;
        }

        // if there's still debt and no collateral
        if (params_.t0Debt != 0 && params_.collateral == 0) {
            // settle debt from reserves -- round reserves down however
            params_.t0Debt -= Maths.min(params_.t0Debt, (params_.reserves / params_.inflator) * 1e18);

            // if there's still debt after settling from reserves then start to forgive amount from next HPB
            while (params_.bucketDepth != 0 && params_.t0Debt != 0) { // loop through remaining buckets if there's still debt to settle
                uint256 index   = Deposits.findIndexOfSum(deposits_, 1);
                uint256 unscaledDeposit = Deposits.unscaledValueAt(deposits_, index);
                uint256 scale        = Deposits.scale(deposits_, index);

                uint256 depositToRemove = Maths.wmul(scale, unscaledDeposit);
                uint256 debt            = Maths.wmul(params_.t0Debt, params_.inflator);

                if (depositToRemove >= debt) {                                          // enough deposit in bucket to settle entire debt
                    Deposits.unscaledRemove(deposits_, index, Maths.wdiv(debt, scale));
                    params_.t0Debt  = 0;                                                // no remaining debt to settle

                } else {                                                                // not enough deposit to settle entire debt, we settle only deposit amount
                    params_.t0Debt -= Maths.wdiv(depositToRemove, params_.inflator);    // subtract from remaining debt the corresponding t0 amount of deposit

                    Deposits.unscaledRemove(deposits_, index, unscaledDeposit);         // Remove all deposit from bucket
                    Bucket storage hpbBucket = buckets_[index];
                    
                    if (hpbBucket.collateral == 0) {                                    // existing LPB and LP tokens for the bucket shall become unclaimable.
                        hpbBucket.lps = 0;
                        hpbBucket.bankruptcyTime = block.timestamp;
                    }
                }

                --params_.bucketDepth;
            }
        }

        emit Settle(params_.borrower, t0DebtInitial - params_.t0Debt);

        return (params_.collateral, params_.t0Debt);
    }

    /**
     *  @notice Called to start borrower liquidation and to update the auctions queue.
     *  @param  poolState_       Current state of the pool.
     *  @param  borrowerAddress_ Address of the borrower to kick.
     *  @return kickResult_      The result of the kick action.
     */
    function kick(
        AuctionsState storage auctions_,
        DepositsState storage deposits_,
        LoansState    storage loans_,
        PoolState calldata poolState_,
        address borrowerAddress_
    ) external returns (
        KickResult memory
    ) {
        return _kick(
            auctions_,
            deposits_,
            loans_,
            poolState_,
            borrowerAddress_,
            0
        );
    }

    /**
     *  @notice Called by lenders to kick loans using their deposits.
     *  @param  poolState_           Current state of the pool.
     *  @param  index_               The deposit index from where lender removes liquidity.
     *  @return kickResult_ The result of the kick action.
     */
    function kickWithDeposit(
        AuctionsState storage auctions_,
        DepositsState storage deposits_,
        mapping(uint256 => Bucket) storage buckets_,
        LoansState    storage loans_,
        PoolState memory poolState_,
        uint256 index_
    ) external returns (
        KickResult memory kickResult_
    ) {
        Bucket storage bucket = buckets_[index_];
        Lender storage lender = bucket.lenders[msg.sender];

        KickWithDepositLocalVars memory vars;
        if (bucket.bankruptcyTime < lender.depositTime) vars.lenderLPs = lender.lps;

        vars.bucketLPs                = bucket.lps;
        vars.bucketCollateral         = bucket.collateral;
        vars.bucketPrice              = _priceAt(index_);
        vars.bucketUnscaledDeposit    = Deposits.unscaledValueAt(deposits_, index_);
        vars.bucketScale              = Deposits.scale(deposits_, index_);
        vars.bucketDeposit            = Maths.wmul(vars.bucketUnscaledDeposit, vars.bucketScale);
        // calculate max amount that can be removed (constrained by lender LPs in bucket, bucket deposit and the amount lender wants to remove)
        vars.bucketRate               = Buckets.getExchangeRate(
            vars.bucketCollateral,
            vars.bucketLPs,
            vars.bucketDeposit,
            vars.bucketPrice
        );
        vars.amountToDebitFromDeposit = Maths.rayToWad(Maths.rmul(vars.lenderLPs, vars.bucketRate));                // calculate amount to remove based on lender LPs in bucket
        if (vars.amountToDebitFromDeposit > vars.bucketDeposit) vars.amountToDebitFromDeposit = vars.bucketDeposit; // cap the amount to remove at bucket deposit

        // revert if no amount that can be removed
        if (vars.amountToDebitFromDeposit == 0) revert InsufficientLiquidity();

        // kick top borrower
        kickResult_ = _kick(
            auctions_,
            deposits_,
            loans_,
            poolState_,
            Loans.getMax(loans_).borrower,
            vars.amountToDebitFromDeposit
        );

        // amount to remove from deposit covers entire bond amount
        if (vars.amountToDebitFromDeposit > kickResult_.amountToCoverBond) {
            vars.amountToDebitFromDeposit = kickResult_.amountToCoverBond;                      // cap amount to remove from deposit at amount to cover bond

            kickResult_.lup = _lup(deposits_, poolState_.debt + vars.amountToDebitFromDeposit); // recalculate the LUP with the amount to cover bond
            kickResult_.amountToCoverBond = 0;                                                  // entire bond is covered from deposit, no additional amount to be send by lender
        } else {
            kickResult_.amountToCoverBond -= vars.amountToDebitFromDeposit;                     // lender should send additional amount to cover bond
        }

        // revert if the bucket price used to kick and remove is below new LUP
        if (vars.bucketPrice < kickResult_.lup) revert PriceBelowLUP();

        // remove amount from deposits
        if (vars.amountToDebitFromDeposit == vars.bucketDeposit && vars.bucketCollateral == 0) {
            // In this case we are redeeming the entire bucket exactly, and need to ensure bucket LPs are set to 0
            vars.redeemedLPs = vars.bucketLPs;
            Deposits.unscaledRemove(deposits_, index_, vars.bucketUnscaledDeposit);
        } else {
            vars.redeemedLPs = Maths.wrdivr(vars.amountToDebitFromDeposit, vars.bucketRate);
            Deposits.unscaledRemove(
                deposits_,
                index_,
                Maths.wdiv(vars.amountToDebitFromDeposit, vars.bucketScale)
            );
        }

        // remove bucket LPs coresponding to the amount removed from deposits
        lender.lps -= vars.redeemedLPs;
        bucket.lps -= vars.redeemedLPs;

        emit RemoveQuoteToken(msg.sender, index_, vars.amountToDebitFromDeposit, vars.redeemedLPs, kickResult_.lup);
    }

    /**
     *  @notice Performs bucket take collateral on an auction and rewards taker and kicker (if case).
     *  @param  params_ Struct containing take action details.
     *  @return Collateral amount taken.
     *  @return T0 debt amount repaid.
     *  @return T0 penalty debt.
    */
    function bucketTake(
        AuctionsState storage auctions_,
        DepositsState storage deposits_,
        mapping(uint256 => Bucket) storage buckets_,
        BucketTakeParams calldata params_
    ) external returns (uint256, uint256, uint256, uint256) {
        if (params_.collateral == 0) revert InsufficientCollateral(); // revert if borrower's collateral is 0

        Liquidation storage liquidation = auctions_.liquidations[params_.borrower];
        TakeResult memory result = _prepareTake(liquidation, params_.t0Debt, params_.collateral, params_.inflator);

        result.unscaledDeposit = Deposits.unscaledValueAt(deposits_, params_.index);
        if (result.unscaledDeposit == 0) revert InsufficientLiquidity(); // revert if no quote tokens in arbed bucket

        result.bucketPrice  = _priceAt(params_.index);
        // cannot arb with a price lower than the auction price
        if (result.auctionPrice > result.bucketPrice) revert AuctionPriceGtBucketPrice();
        
        // if deposit take then price to use when calculating take is bucket price
        if (params_.depositTake) result.auctionPrice = result.bucketPrice;

        result.bucketScale = Deposits.scale(deposits_, params_.index);

        (
            result.collateralAmount,
            result.t0RepayAmount,
            result.unscaledQuoteTokenAmount,
            result.scaledQuoteTokenAmount
        ) = _calculateTakeFlows(
            params_.collateral,
            params_.t0Debt,
            params_.inflator,
            result
        );

        if (result.isRewarded) {
            result.bondChange = Maths.wmul(result.scaledQuoteTokenAmount, uint256(result.bpf)); // will be rewarded as LPBs
        } else {
            // take is above neutralPrice, Kicker is penalized
            result.bondChange = Maths.min(liquidation.bondSize, Maths.wmul(result.scaledQuoteTokenAmount, uint256(-result.bpf)));
            liquidation.bondSize                    -= uint160(result.bondChange);
            auctions_.kickers[result.kicker].locked -= result.bondChange;
            auctions_.totalBondEscrowed             -= result.bondChange;
        }

        _rewardBucketTake(
            deposits_,
            buckets_,
            params_.index,
            params_.depositTake,
            result
        );

        emit BucketTake(
            params_.borrower,
            params_.index,
            result.scaledQuoteTokenAmount,
            result.collateralAmount,
            result.bondChange,
            result.isRewarded
        );

        return (
            result.collateralAmount,
            result.t0RepayAmount,
            result.t0Debt,
            result.t0DebtPenalty
        );
    }

    /**
     *  @notice Performs take collateral on an auction and updates bond size and kicker balance accordingly.
     *  @param  params_ Struct containing take action params details.
     *  @return Collateral amount taken.
     *  @return Quote token to be received from taker.
     *  @return T0 debt amount repaid.
     *  @return T0 penalty debt.
     *  @return Auction price.
    */
    function take(
        AuctionsState storage auctions_,
        TakeParams calldata params_
    ) external returns (uint256, uint256, uint256, uint256, uint256, uint256) {
        Liquidation storage liquidation = auctions_.liquidations[params_.borrower];
        TakeResult memory result = _prepareTake(liquidation, params_.t0Debt, params_.collateral, params_.inflator);
        // These are placeholder max values passed to calculateTakeFlows because there is no explicit bound on the
        // quote token amount in take calls (as opposed to bucketTake)
        result.unscaledDeposit = type(uint256).max;
        result.bucketScale = Maths.WAD;

        uint256 collateralBound = Maths.min(params_.collateral, params_.takeCollateral);

        // In the case of take, the taker binds the collateral qty but not the quote token qty
        // ugly to get take work like a bucket take -- this is the max amount of quote token from the take that could go to
        // reduce the debt of the borrower -- analagous to the amount of deposit in the bucket for a bucket take
        (
            result.collateralAmount,
            result.t0RepayAmount,
            result.unscaledQuoteTokenAmount,
            result.scaledQuoteTokenAmount
        ) = _calculateTakeFlows(
            collateralBound,
            params_.t0Debt,
            params_.inflator,
            result
        );

        if (result.isRewarded) {
            // take is below neutralPrice, Kicker is rewarded
            result.bondChange = Maths.wmul(result.scaledQuoteTokenAmount, uint256(result.bpf));
            liquidation.bondSize                     += uint160(result.bondChange);
            auctions_.kickers[result.kicker].locked  += result.bondChange;
            auctions_.totalBondEscrowed              += result.bondChange;
        } else {
            // take is above neutralPrice, Kicker is penalized
            result.bondChange = Maths.min(liquidation.bondSize, Maths.wmul(result.scaledQuoteTokenAmount, uint256(-result.bpf)));
            liquidation.bondSize                     -= uint160(result.bondChange);
            auctions_.kickers[result.kicker].locked  -= result.bondChange;
            auctions_.totalBondEscrowed              -= result.bondChange;
        }

        emit Take(
            params_.borrower,
            result.scaledQuoteTokenAmount,
            result.collateralAmount,
            result.bondChange,
            result.isRewarded
        );

        return (
            result.collateralAmount,
            result.scaledQuoteTokenAmount,
            result.t0RepayAmount,
            result.t0Debt,
            result.t0DebtPenalty,
            result.auctionPrice
        );
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
        AuctionsState storage auctions_,
        mapping(uint256 => Bucket) storage buckets_,
        DepositsState storage deposits_,
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
                auctions_.liquidations[borrowerAddress_].kickMomp,
                auctions_.liquidations[borrowerAddress_].kickTime
            );
            bucketIndex_ = auctionPrice > MIN_PRICE ? _indexOf(auctionPrice) : MAX_FENWICK_INDEX;
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

        _removeAuction(auctions_, borrowerAddress_);
    }

    /***********************/
    /*** Reserve Auction ***/
    /***********************/

    function startClaimableReserveAuction(
        AuctionsState storage auctions_,
        ReserveAuctionState storage reserveAuction_,
        StartReserveAuctionParams calldata params_
    ) external returns (uint256 kickerAward_) {
        uint256 curUnclaimedAuctionReserve = reserveAuction_.unclaimed;
        uint256 claimable = _claimableReserves(
            Maths.wmul(params_.poolDebt, params_.inflator),
            params_.poolSize,
            auctions_.totalBondEscrowed,
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
        ReserveAuctionState storage reserveAuction_,
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
     *  @notice Called to start borrower liquidation and to update the auctions queue.
     *  @param  poolState_       Current state of the pool.
     *  @param  borrowerAddress_ Address of the borrower to kick.
     *  @param  additionalDebt_  Additional debt to be used when calculating proposed LUP.
     *  @return kickResult_      The result of the kick action.
     */
    function _kick(
        AuctionsState storage auctions_,
        DepositsState storage deposits_,
        LoansState    storage loans_,
        PoolState memory poolState_,
        address borrowerAddress_,
        uint256 additionalDebt_
    ) internal returns (
        KickResult memory kickResult_
    ) {
        Borrower storage borrower = loans_.borrowers[borrowerAddress_];
        kickResult_.t0KickedDebt = borrower.t0Debt;

        uint256 borrowerDebt       = Maths.wmul(kickResult_.t0KickedDebt, poolState_.inflator);
        uint256 borrowerCollateral = borrower.collateral;

        // add amount to remove to pool debt in order to calculate proposed LUP
        kickResult_.lup = _lup(deposits_, poolState_.debt + additionalDebt_);
        if (
            _isCollateralized(borrowerDebt , borrowerCollateral, kickResult_.lup, poolState_.poolType)
        ) revert BorrowerOk();

        // calculate auction params
        uint256 noOfLoans = Loans.noOfLoans(loans_) + auctions_.noOfAuctions;
        uint256 momp = _priceAt(
            Deposits.findIndexOfSum(
                deposits_,
                Maths.wdiv(poolState_.debt, noOfLoans * 1e18)
            )
        );
        (uint256 bondFactor, uint256 bondSize) = _bondParams(
            borrowerDebt,
            borrowerCollateral,
            momp
        );
        // when loan is kicked, penalty of three months of interest is added
        kickResult_.kickPenalty   = Maths.wmul(Maths.wdiv(poolState_.rate, 4 * 1e18), borrowerDebt);
        kickResult_.t0KickPenalty = Maths.wdiv(kickResult_.kickPenalty, poolState_.inflator);

        // record liquidation info
        uint256 neutralPrice = Maths.wmul(borrower.t0Np, poolState_.inflator);
        _recordAuction(
            auctions_,
            borrowerAddress_,
            bondSize,
            bondFactor,
            momp,
            neutralPrice
        );
        // update kicker balances and get the difference needed to cover bond (after using any kick claimable funds if any)
        kickResult_.amountToCoverBond = _updateKicker(auctions_, bondSize);

        // remove kicked loan from heap
        Loans.remove(loans_, borrowerAddress_, loans_.indices[borrowerAddress_]);

        kickResult_.t0KickedDebt += kickResult_.t0KickPenalty;
        borrower.t0Debt =  kickResult_.t0KickedDebt;

        emit Kick(
            borrowerAddress_,
            borrowerDebt + kickResult_.kickPenalty,
            borrower.collateral,
            bondSize
        );
    }

    /**
     *  @notice Calculates bond parameters of an auction.
     *  @param  borrowerDebt_ Borrower's debt before entering in liquidation.
     *  @param  collateral_   Borrower's collateral before entering in liquidation.
     *  @param  momp_         Current pool momp.
     */
    function _bondParams(
        uint256 borrowerDebt_,
        uint256 collateral_,
        uint256 momp_
    ) internal pure returns (uint256 bondFactor_, uint256 bondSize_) {
        uint256 thresholdPrice = borrowerDebt_  * Maths.WAD / collateral_;
        // bondFactor = min(30%, max(1%, (MOMP - thresholdPrice) / MOMP))
        if (thresholdPrice >= momp_) {
            bondFactor_ = 0.01 * 1e18;
        } else {
            bondFactor_ = Maths.min(
                0.3 * 1e18,
                Maths.max(
                    0.01 * 1e18,
                    1e18 - Maths.wdiv(thresholdPrice, momp_)
                )
            );
        }

        bondSize_ = Maths.wmul(bondFactor_,  borrowerDebt_);
    }

    /**
     *  @notice Updates kicker balances.
     *  @param  bondSize_       Bond size to cover newly kicked auction.
     *  @return bondDifference_ The amount that kicker should send to pool to cover auction bond.
     */
    function _updateKicker(
        AuctionsState storage auctions_,
        uint256 bondSize_
    ) internal returns (uint256 bondDifference_){
        Kicker storage kicker = auctions_.kickers[msg.sender];
        kicker.locked += bondSize_;
        uint256 kickerClaimable = kicker.claimable;
        if (kickerClaimable >= bondSize_) {
            kicker.claimable -= bondSize_;
        } else {
            bondDifference_  = bondSize_ - kickerClaimable;
            kicker.claimable = 0;
        }
    }

    /**
     *  @notice Computes the flows of collateral, quote token between the borrower, lender and kicker.
     *  @param  totalCollateral_        Total collateral in loan.
     *  @param  t0Debt_                 t0 equivalent debt in loan.
     *  @param  inflator_               Current pool inflator.
     *  @param  result_                 TakeParams for the take/buckettake
     *  @return collateral_             Collateral purchased in auction.
     *  @return t0debtPaid_             t0 equivalent amount of debt repaid in take.
     *  @return unscaledQuoteTokenPaid_ Unscaled amount of quote token paid (used to decrement deposit, or whatever is paid in qt in take).
     *  @return scaledQuoteTokenPaid_   Scaled amount of quote token paid - same as current debt reduction
     */
    function _calculateTakeFlows(
        uint256           totalCollateral_,
        uint256           t0Debt_,
        uint256           inflator_,
        TakeResult memory result_
    ) internal pure returns (
        uint256 collateral_,
        uint256 t0debtPaid_,
        uint256 unscaledQuoteTokenPaid_,
        uint256 scaledQuoteTokenPaid_
    ) {
        // price is the current auction price, which is the price paid by the LENDER for collateral
        // from the borrower point of view, the price is actually (1-bpf) * price, as the rewards to the
        // bond holder are effectively paid for by the borrower.
        uint256 borrowerPayoffFactor = (result_.isRewarded) ? Maths.WAD - uint256(result_.bpf) : Maths.WAD;
        uint256 borrowerPrice = (result_.isRewarded) ? Maths.wmul(borrowerPayoffFactor, result_.auctionPrice) : result_.auctionPrice;

        // If there is no unscaled quote token bound, then we pass in max, but that cannot be scaled without an overflow.  So we check in the line below.
        scaledQuoteTokenPaid_ = (result_.unscaledDeposit != type(uint256).max) ? Maths.wmul(result_.unscaledDeposit, result_.bucketScale) : type(uint256).max;

        uint256 borrowerCollateralValue = Maths.wmul(totalCollateral_, borrowerPrice);
        
        if (scaledQuoteTokenPaid_ <= result_.borrowerDebt && scaledQuoteTokenPaid_ <= borrowerCollateralValue) {
            // quote token used to purchase is constraining factor
            collateral_             = Maths.wdiv(scaledQuoteTokenPaid_, borrowerPrice);
            t0debtPaid_             = Maths.wdiv(scaledQuoteTokenPaid_, inflator_);
            unscaledQuoteTokenPaid_ = result_.unscaledDeposit;
        } else if (result_.borrowerDebt <= borrowerCollateralValue) {
            // borrower debt is constraining factor
            collateral_             = Maths.wdiv(result_.borrowerDebt, borrowerPrice);
            t0debtPaid_             = t0Debt_;
            unscaledQuoteTokenPaid_ = Maths.wdiv(result_.borrowerDebt, result_.bucketScale);
            scaledQuoteTokenPaid_   = (result_.isRewarded) ? Maths.wdiv(result_.borrowerDebt, borrowerPayoffFactor) : result_.borrowerDebt;
        } else {
            // collateral available is constraint
            collateral_             = totalCollateral_;
            t0debtPaid_             = Maths.wdiv(borrowerCollateralValue, inflator_);
            unscaledQuoteTokenPaid_ = Maths.wdiv(borrowerCollateralValue, result_.bucketScale);
            scaledQuoteTokenPaid_   = Maths.wmul(collateral_, result_.auctionPrice);
        }
    }

    /**
     *  @notice Saves a new liquidation that was kicked.
     *  @param  borrowerAddress_ Address of the borrower that is kicked.
     *  @param  bondSize_        Bond size to cover newly kicked auction.
     *  @param  bondFactor_      Bond factor of the newly kicked auction.
     *  @param  momp_            Current pool MOMP.
     *  @param  neutralPrice_    Current pool Neutral Price.
     */
    function _recordAuction(
        AuctionsState storage auctions_,
        address borrowerAddress_,
        uint256 bondSize_,
        uint256 bondFactor_,
        uint256 momp_,
        uint256 neutralPrice_
    ) internal {
        Liquidation storage liquidation = auctions_.liquidations[borrowerAddress_];
        if (liquidation.kickTime != 0) revert AuctionActive();

        // record liquidation info
        liquidation.kicker              = msg.sender;
        liquidation.kickTime            = uint96(block.timestamp);
        liquidation.kickMomp            = uint96(momp_);
        liquidation.bondSize            = uint160(bondSize_);
        liquidation.bondFactor          = uint96(bondFactor_);
        liquidation.neutralPrice        = uint96(neutralPrice_);

        // increment number of active auctions
        ++ auctions_.noOfAuctions;

        // update totalBondEscrowed accumulator
        auctions_.totalBondEscrowed += bondSize_;

        // update auctions queue
        if (auctions_.head != address(0)) {
            // other auctions in queue, liquidation doesn't exist or overwriting.
            auctions_.liquidations[auctions_.tail].next = borrowerAddress_;
            liquidation.prev = auctions_.tail;
        } else {
            // first auction in queue
            auctions_.head = borrowerAddress_;
        }
        // update liquidation with the new ordering
        auctions_.tail = borrowerAddress_;
    }

    /**
     *  @notice Removes auction and repairs the queue order.
     *  @notice Updates kicker's claimable balance with bond size awarded and subtracts bond size awarded from liquidationBondEscrowed.
     *  @param  borrower_ Auctioned borrower address.
     */
    function _removeAuction(
        AuctionsState storage auctions_,
        address borrower_
    ) internal {
        Liquidation memory liquidation = auctions_.liquidations[borrower_];
        // update kicker balances
        Kicker storage kicker = auctions_.kickers[liquidation.kicker];
        kicker.locked    -= liquidation.bondSize;
        kicker.claimable += liquidation.bondSize;

        // decrement number of active auctions
        -- auctions_.noOfAuctions;

        // remove auction bond size from bond escrow accumulator 
        auctions_.totalBondEscrowed -= liquidation.bondSize;

        // update auctions queue
        if (auctions_.head == borrower_ && auctions_.tail == borrower_) {
            // liquidation is the head and tail
            auctions_.head = address(0);
            auctions_.tail = address(0);

        } else if(auctions_.head == borrower_) {
            // liquidation is the head
            auctions_.liquidations[liquidation.next].prev = address(0);
            auctions_.head = liquidation.next;

        } else if(auctions_.tail == borrower_) {
            // liquidation is the tail
            auctions_.liquidations[liquidation.prev].next = address(0);
            auctions_.tail = liquidation.prev;

        } else {
            // liquidation is in the middle
            auctions_.liquidations[liquidation.prev].next = liquidation.next;
            auctions_.liquidations[liquidation.next].prev = liquidation.prev;
        }
        // delete liquidation
         delete auctions_.liquidations[borrower_];
    }

    /**
     *  @notice Rewards actors of a bucket take action.
     *  @param  deposits_      Deposits state
     *  @param  bucketIndex_   Bucket index.
     *  @param  result_        Struct containing take action result details.
     */
    function _rewardBucketTake(
        DepositsState storage deposits_,
        mapping(uint256 => Bucket) storage buckets_,
        uint256 bucketIndex_,
        bool depositTake_,
        TakeResult memory result_
    ) internal {
        Bucket storage bucket = buckets_[bucketIndex_];

        uint256 bucketExchangeRate = Buckets.getUnscaledExchangeRate(
            bucket.collateral,
            bucket.lps,
            result_.unscaledDeposit,
            result_.bucketScale,
            result_.bucketPrice
        );

        uint256 bankruptcyTime = bucket.bankruptcyTime;
        uint256 totalLPsReward;
        // if arb take - taker is awarded collateral * (bucket price - auction price) worth (in quote token terms) units of LPB in the bucket
        if (!depositTake_) {
            uint256 takerReward = Maths.wmul(result_.collateralAmount, result_.bucketPrice - result_.auctionPrice);
            uint256 takerRewardUnscaledQuoteToken = Maths.wdiv(takerReward, result_.bucketScale);
            totalLPsReward = Maths.wrdivr(takerRewardUnscaledQuoteToken, bucketExchangeRate);
            Buckets.addLenderLPs(bucket, bankruptcyTime, msg.sender, totalLPsReward);
        }

        uint256 kickerLPsReward;
        // the bondholder/kicker is awarded bond change worth of LPB in the bucket
        if (result_.isRewarded) {
            kickerLPsReward = Maths.wrdivr(Maths.wdiv(result_.bondChange, result_.bucketScale), bucketExchangeRate);
            totalLPsReward += kickerLPsReward;
            Buckets.addLenderLPs(bucket, bankruptcyTime, result_.kicker, kickerLPsReward);
        }

        Deposits.unscaledRemove(deposits_, bucketIndex_, result_.unscaledQuoteTokenAmount); // remove quote tokens from bucket’s deposit

        // total rewarded LPs are added to the bucket LP balance
        bucket.lps += totalLPsReward;
        // collateral is added to the bucket’s claimable collateral
        bucket.collateral += result_.collateralAmount;

        emit BucketTakeLPAwarded(
            msg.sender,
            result_.kicker,
            totalLPsReward - kickerLPsReward,
            kickerLPsReward
        );
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
     *  @param debt_         Borrower debt.
     *  @param collateral_   Borrower collateral.
     *  @param neutralPrice_ NP of auction.
     *  @param bondFactor_   Factor used to determine bondSize.
     *  @param price_        Auction price at the time of call.
     *  @return bpf_         Factor used in determining bond Reward (positive) or penalty (negative).
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
     *  @notice Utility function to validate take and calculate take's parameters.
     *  @param  liquidation_ Liquidation struct holding auction details.
     *  @param  t0Debt_       Borrower t0 debt.
     *  @param  collateral_  Borrower collateral.
     *  @param  inflator_    The pool's inflator, used to calculate borrower debt.
     *  @return takeResult_  The result of take action.
     */
    function _prepareTake(
        Liquidation storage liquidation_,
        uint256 t0Debt_,
        uint256 collateral_,
        uint256 inflator_
    ) internal returns (TakeResult memory takeResult_) {

        uint256 kickTime = liquidation_.kickTime;
        if (kickTime == 0) revert NoAuction();
        if (block.timestamp - kickTime <= 1 hours) revert TakeNotPastCooldown();

        takeResult_.t0Debt = t0Debt_;
        // if first take borrower debt is increased by 7% penalty
        if (!liquidation_.alreadyTaken) {
            takeResult_.t0DebtPenalty = Maths.wmul(t0Debt_, 0.07 * 1e18);
            takeResult_.t0Debt += takeResult_.t0DebtPenalty; 
            liquidation_.alreadyTaken = true;
        }

        takeResult_.borrowerDebt = Maths.wmul(takeResult_.t0Debt, inflator_);
        takeResult_.auctionPrice = _auctionPrice(liquidation_.kickMomp, kickTime);
        takeResult_.bpf          = _bpf(
            takeResult_.borrowerDebt,
            collateral_,
            liquidation_.neutralPrice,
            liquidation_.bondFactor,
            takeResult_.auctionPrice
        );
        takeResult_.factor     = uint256(1e18 - Maths.maxInt(0, takeResult_.bpf));
        takeResult_.kicker     = liquidation_.kicker;
        takeResult_.isRewarded = (takeResult_.bpf  >= 0);
    }

    /**********************/
    /*** View Functions ***/
    /**********************/

    /**
     *  @notice Returns true if borrower is in auction.
     *  @dev    Used to accuratley increment and decrement t0DebtInAuction.
     *  @param  borrower_ Borrower address to check auction status for.
     *  @return  active_ Boolean, based on if borrower is in auction.
     */
    function isActive(
        AuctionsState storage auctions_,
        address borrower_
    ) internal view returns (bool) {
        return auctions_.liquidations[borrower_].kickTime != 0;
    }

    /**
     *  @notice Check if head auction is clearable (auction is kicked and 72 hours passed since kick time or auction still has debt but no remaining collateral).
     *  @notice Revert if auction is clearable
     */
    function revertIfAuctionClearable(
        AuctionsState storage auctions_,
        LoansState    storage loans_
    ) internal view {
        address head     = auctions_.head;
        uint256 kickTime = auctions_.liquidations[head].kickTime;
        if (kickTime != 0) {
            if (block.timestamp - kickTime > 72 hours) revert AuctionNotCleared();

            Borrower storage borrower = loans_.borrowers[head];
            if (borrower.t0Debt != 0 && borrower.collateral == 0) revert AuctionNotCleared();
        }
    }

    function _lup(
        DepositsState storage deposits_,
        uint256 debt_
    ) internal view returns (uint256) {
        return _priceAt(Deposits.findIndexOfSum(deposits_, debt_));
    }

}
