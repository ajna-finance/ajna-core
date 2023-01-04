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
    BucketTakeResult,
    TakeResult,
    StartReserveAuctionParams
} from 'src/base/interfaces/IPool.sol';

import { _revertOnMinDebt } from 'src/base/RevertsHelper.sol';

import 'src/libraries/Buckets.sol';
import 'src/libraries/Deposits.sol';
import 'src/libraries/Loans.sol';

import 'src/base/PoolHelper.sol';

library Auctions {

    struct BucketTakeParams {
        address borrower;    // borrower address to take from
        uint256 collateral;  // borrower available collateral to take
        bool    depositTake; // deposit or arb take, used by bucket take
        uint256 index;       // bucket index, used by bucket take
        uint256 inflator;    // current pool inflator
        uint256 t0Debt;      // borrower t0 debt
    }

    struct KickWithDepositLocalVars {
        uint256 amountToDebitFromDeposit; // the amount of quote tokens used to kick and debited from lender deposit
        uint256 bucketCollateral;         // amount of collateral in bucket
        uint256 bucketDeposit;            // amount of quote tokens in bucket
        uint256 bucketLPs;                // LPs of the bucket
        uint256 bucketPrice;              // bucket price
        uint256 bucketRate;               // bucket exchange rate
        uint256 bucketScale;              // bucket scales
        uint256 bucketUnscaledDeposit;    // unscaled amount of quote tokens in bucket
        uint256 lenderLPs;                // LPs of lender in bucket
        uint256 redeemedLPs;              // LPs used by kick action
    }

    struct SettleLocalVars {
        uint256 collateralUsed;    // collateral used to settle debt
        uint256 debt;              // debt to settle
        uint256 depositToRemove;   // deposit used by settle auction
        uint256 index;             // index of settling bucket
        uint256 maxSettleableDebt; // max amount that can be settled with existing collateral
        uint256 price;             // price of settling bucket
        uint256 scaledDeposit;     // scaled amount of quote tokens in bucket
        uint256 scale;             // scale of settling bucket
        uint256 unscaledDeposit;   // unscaled amount of quote tokens in bucket
    }

    struct TakeLocalVars {
        uint256 auctionPrice;             // The price of auction.
        uint256 bondChange;               // The change made on the bond size (beeing reward or penalty).
        uint256 borrowerDebt;             // The accrued debt of auctioned borrower.
        int256  bpf;                      // The bond penalty factor.
        uint256 bucketPrice;              // The bucket price.
        uint256 bucketScale;              // The bucket scale.
        uint256 collateralAmount;         // The amount of collateral taken.
        uint256 excessQuoteToken;         // Difference of quote token that borrower receives after take (for fractional NFT only)
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

    struct TakeFromLoanResult {
        uint256 newLup;                // LUP after auction is taken and loan info updated
        uint256 poolDebt;              // accrued pool debt after auction is taken
        uint256 remainingCollateral;   // borrower remaining collateral after auction is taken
        bool    settledAuction;        // true if auction was settled by take auction
        uint256 t0DebtInAuctionChange; // t0 change amount of debt after auction is taken
    }

    struct TakeFromLoanLocalVars {
        uint256 borrowerDebt;          // borrower's accrued debt
        bool    inAuction;             // true if loan still in auction after auction is taken, false otherwise
        uint256 newLup;                // LUP after auction is taken
        uint256 repaidDebt;            // debt repaid when auction is taken
        uint256 t0DebtInAuction;       // t0 pool debt in auction
        uint256 t0DebtInAuctionChange; // t0 change amount of debt after auction is taken
        uint256 t0PoolDebt;            // t0 pool debt
    }

    struct TakeParams {
        address borrower;       // borrower address to take from
        uint256 collateral;     // borrower available collateral to take
        uint256 t0Debt;         // borrower t0 debt
        uint256 takeCollateral; // desired amount to take
        uint256 inflator;       // current pool inflator
        uint256 poolType;       // pool type (ERC20 or NFT)
    }

    /**
     *  @notice Emitted when auction is completed.
     *  @param  borrower   Address of borrower that exits auction.
     *  @param  collateral Borrower's remaining collateral when auction completed.
     */
    event AuctionSettle(
        address indexed borrower,
        uint256 collateral
    );

    /**
     *  @notice Emitted when NFT auction is completed.
     *  @param  borrower   Address of borrower that exits auction.
     *  @param  collateral Borrower's remaining collateral when auction completed.
     *  @param  lps        Amount of LPs given to the borrower to compensate fractional collateral (if any).
     *  @param  index      Index of the bucket with LPs to compensate fractional collateral.
     */
    event AuctionNFTSettle(
        address indexed borrower,
        uint256 collateral,
        uint256 lps,
        uint256 index
    );

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

    /**
     *  @notice Emitted when a Claimaible Reserve Auction is started or taken.
     *  @return claimableReservesRemaining Amount of claimable reserves which has not yet been taken.
     *  @return auctionPrice               Current price at which 1 quote token may be purchased, denominated in Ajna.
     */
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
     *  @return collateralRemaining_ The amount of borrower collateral left after settle.
     *  @return t0DebtRemaining_     The amount of t0 debt left after settle.
     *  @return collateralSettled_   The amount of collateral settled.
     *  @return t0DebtSettled_       The amount of t0 debt settled.
     */
    function settlePoolDebt(
        AuctionsState storage auctions_,
        mapping(uint256 => Bucket) storage buckets_,
        DepositsState storage deposits_,
        LoansState storage loans_,
        SettleParams memory params_
    ) external returns (
        uint256 collateralRemaining_,
        uint256 t0DebtRemaining_,
        uint256 collateralSettled_,
        uint256 t0DebtSettled_
    ) {
        uint256 kickTime = auctions_.liquidations[params_.borrower].kickTime;
        if (kickTime == 0) revert NoAuction();

        Borrower memory borrower = loans_.borrowers[params_.borrower];
        if ((block.timestamp - kickTime < 72 hours) && (borrower.collateral != 0)) revert AuctionNotClearable();

        t0DebtSettled_     = borrower.t0Debt;
        collateralSettled_ = borrower.collateral;

        // auction has debt to cover with remaining collateral
        while (params_.bucketDepth != 0 && borrower.t0Debt != 0 && borrower.collateral != 0) {
            SettleLocalVars memory vars;

            vars.index           = Deposits.findIndexOfSum(deposits_, 1);
            vars.unscaledDeposit = Deposits.unscaledValueAt(deposits_, vars.index);
            vars.scale           = Deposits.scale(deposits_, vars.index);
            vars.price           = _priceAt(vars.index);

            if (vars.unscaledDeposit != 0) {
                vars.debt              = Maths.wmul(borrower.t0Debt, params_.inflator);       // current debt to be settled
                vars.maxSettleableDebt = Maths.wmul(borrower.collateral, vars.price);         // max debt that can be settled with existing collateral
                vars.scaledDeposit     = Maths.wmul(vars.scale, vars.unscaledDeposit);

                // enough deposit in bucket and collateral avail to settle entire debt
                if (vars.scaledDeposit >= vars.debt && vars.maxSettleableDebt >= vars.debt) {
                    borrower.t0Debt      = 0;                                                 // no remaining debt to settle

                    vars.unscaledDeposit = Maths.wdiv(vars.debt, vars.scale);                 // remove only what's needed to settle the debt
                    vars.collateralUsed  = Maths.wdiv(vars.debt, vars.price);
                }

                // enough collateral, therefore not enough deposit to settle entire debt, we settle only deposit amount
                else if (vars.maxSettleableDebt >= vars.scaledDeposit) {
                    borrower.t0Debt     -= Maths.wdiv(vars.scaledDeposit, params_.inflator);  // subtract from debt the corresponding t0 amount of deposit

                    vars.collateralUsed = Maths.wdiv(vars.scaledDeposit, vars.price);
                } 

                // settle constrained by collateral available
                else {
                    borrower.t0Debt      -= Maths.wdiv(vars.maxSettleableDebt, params_.inflator);

                    vars.unscaledDeposit = Maths.wdiv(vars.maxSettleableDebt, vars.scale);
                    vars.collateralUsed  = borrower.collateral;
                }

                borrower.collateral             -= vars.collateralUsed;               // move settled collateral from loan into bucket
                buckets_[vars.index].collateral += vars.collateralUsed;

                Deposits.unscaledRemove(deposits_, vars.index, vars.unscaledDeposit); // remove amount to settle debt from bucket (could be entire deposit or only the settled debt)
            }

            else {
                // Deposits in the tree is zero, insert entire collateral into lowest bucket 7388
                Buckets.addCollateral(
                    buckets_[vars.index],
                    params_.borrower,
                    0,  // zero deposit in bucket
                    borrower.collateral,
                    vars.price
                );
                borrower.collateral = 0; // entire collateral added into bucket
            }

            --params_.bucketDepth;
        }

        // if there's still debt and no collateral
        if (borrower.t0Debt != 0 && borrower.collateral == 0) {
            // settle debt from reserves -- round reserves down however
            borrower.t0Debt -= Maths.min(borrower.t0Debt, (params_.reserves / params_.inflator) * 1e18);

            // if there's still debt after settling from reserves then start to forgive amount from next HPB
            // loop through remaining buckets if there's still debt to settle
            while (params_.bucketDepth != 0 && borrower.t0Debt != 0) {
                SettleLocalVars memory vars;

                vars.index           = Deposits.findIndexOfSum(deposits_, 1);
                vars.unscaledDeposit = Deposits.unscaledValueAt(deposits_, vars.index);
                vars.scale           = Deposits.scale(deposits_, vars.index);
                vars.depositToRemove = Maths.wmul(vars.scale, vars.unscaledDeposit);
                vars.debt            = Maths.wmul(borrower.t0Debt, params_.inflator);

                // enough deposit in bucket to settle entire debt
                if (vars.depositToRemove >= vars.debt) {
                    Deposits.unscaledRemove(deposits_, vars.index, Maths.wdiv(vars.debt, vars.scale));
                    borrower.t0Debt  = 0;                                                              // no remaining debt to settle

                // not enough deposit to settle entire debt, we settle only deposit amount
                } else {
                    borrower.t0Debt -= Maths.wdiv(vars.depositToRemove, params_.inflator);             // subtract from remaining debt the corresponding t0 amount of deposit

                    Deposits.unscaledRemove(deposits_, vars.index, vars.unscaledDeposit);              // Remove all deposit from bucket
                    Bucket storage hpbBucket = buckets_[vars.index];
                    
                    if (hpbBucket.collateral == 0) {                                                   // existing LPB and LP tokens for the bucket shall become unclaimable.
                        hpbBucket.lps            = 0;
                        hpbBucket.bankruptcyTime = block.timestamp;
                    }
                }

                --params_.bucketDepth;
            }
        }

        t0DebtRemaining_ =  borrower.t0Debt;
        t0DebtSettled_   -= t0DebtRemaining_;

        emit Settle(params_.borrower, t0DebtSettled_);

        if (borrower.t0Debt == 0) {
            // settle auction
            borrower.collateral = _settleAuction(
                auctions_,
                buckets_,
                deposits_,
                params_.borrower,
                borrower.collateral,
                params_.poolType
            );
        }

        collateralRemaining_ =  borrower.collateral;
        collateralSettled_   -= collateralRemaining_;

        // update borrower state
        loans_.borrowers[params_.borrower] = borrower;
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
        LoansState storage loans_,
        PoolState memory poolState_,
        uint256 index_
    ) external returns (
        KickResult memory kickResult_
    ) {
        Bucket storage bucket = buckets_[index_];
        Lender storage lender = bucket.lenders[msg.sender];

        KickWithDepositLocalVars memory vars;

        if (bucket.bankruptcyTime < lender.depositTime) vars.lenderLPs = lender.lps;

        vars.bucketLPs             = bucket.lps;
        vars.bucketCollateral      = bucket.collateral;
        vars.bucketPrice           = _priceAt(index_);
        vars.bucketUnscaledDeposit = Deposits.unscaledValueAt(deposits_, index_);
        vars.bucketScale           = Deposits.scale(deposits_, index_);
        vars.bucketDeposit         = Maths.wmul(vars.bucketUnscaledDeposit, vars.bucketScale);

        // calculate max amount that can be removed (constrained by lender LPs in bucket, bucket deposit and the amount lender wants to remove)
        vars.bucketRate = Buckets.getExchangeRate(
            vars.bucketCollateral,
            vars.bucketLPs,
            vars.bucketDeposit,
            vars.bucketPrice
        );

        vars.amountToDebitFromDeposit = Maths.rayToWad(Maths.rmul(vars.lenderLPs, vars.bucketRate));  // calculate amount to remove based on lender LPs in bucket

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
     *  @notice Performs bucket take collateral on an auction, rewards taker and kicker (if case) and updates loan info (settles auction if case).
     *  @param  borrowerAddress_ Borrower address to take.
     *  @param  depositTake_     If true then the take will happen at an auction price equal with bucket price. Auction price is used otherwise.
     *  @param  index_           Index of a bucket, likely the HPB, in which collateral will be deposited.
     *  @return result_          BucketTakeResult struct containing details of take.
    */
    function bucketTake(
        AuctionsState storage auctions_,
        mapping(uint256 => Bucket) storage buckets_,
        DepositsState storage deposits_,
        LoansState storage loans_,
        PoolState calldata poolState_,
        address borrowerAddress_,
        bool    depositTake_,
        uint256 index_
    ) external returns (BucketTakeResult memory result_) {
        Borrower memory borrower = loans_.borrowers[borrowerAddress_];

        (
            result_.collateralAmount,
            result_.t0RepayAmount,
            borrower.t0Debt,
            result_.t0DebtPenalty 
        ) = _takeBucket(
            auctions_,
            buckets_,
            deposits_,
            BucketTakeParams({
                borrower:    borrowerAddress_,
                collateral:  borrower.collateral,
                t0Debt:      borrower.t0Debt,
                inflator:    poolState_.inflator,
                depositTake: depositTake_,
                index:       index_
            })
        );

        borrower.collateral -= result_.collateralAmount;

        TakeFromLoanResult memory loanTakeResult = _takeLoan(
            auctions_,
            buckets_,
            deposits_,
            loans_,
            poolState_,
            borrower,
            borrowerAddress_,
            result_.t0RepayAmount,
            result_.t0DebtPenalty
        );

        result_.poolDebt              = loanTakeResult.poolDebt;
        result_.newLup                = loanTakeResult.newLup;
        result_.t0DebtInAuctionChange = loanTakeResult.t0DebtInAuctionChange;
        result_.settledAuction        = loanTakeResult.settledAuction;
    }

    /**
     *  @notice Performs take collateral on an auction, rewards taker and kicker (if case) and updates loan info (settles auction if case).
     *  @param  borrowerAddress_ Borrower address to take.
     *  @param  collateral_      Max amount of collateral that will be taken from the auction (max number of NFTs in case of ERC721 pool).
     *  @return result_          TakeResult struct containing details of take.
    */
    function take(
        AuctionsState storage auctions_,
        mapping(uint256 => Bucket) storage buckets_,
        DepositsState storage deposits_,
        LoansState storage loans_,
        PoolState calldata poolState_,
        address borrowerAddress_,
        uint256 collateral_
    ) external returns (TakeResult memory result_) {
        Borrower memory borrower = loans_.borrowers[borrowerAddress_];

        // revert if borrower's collateral is 0 or if maxCollateral to be taken is 0
        if (borrower.collateral == 0 || collateral_ == 0) revert InsufficientCollateral();

        (
            result_.collateralAmount,
            result_.quoteTokenAmount,
            result_.t0RepayAmount,
            borrower.t0Debt,
            result_.t0DebtPenalty,
            result_.excessQuoteToken
        ) = _take(
            auctions_,
            TakeParams({
                borrower:       borrowerAddress_,
                collateral:     borrower.collateral,
                t0Debt:         borrower.t0Debt,
                takeCollateral: collateral_,
                inflator:       poolState_.inflator,
                poolType:       poolState_.poolType
            })
        );

        borrower.collateral -= result_.collateralAmount;

        TakeFromLoanResult memory loanTakeResult = _takeLoan(
            auctions_,
            buckets_,
            deposits_,
            loans_,
            poolState_,
            borrower,
            borrowerAddress_,
            result_.t0RepayAmount,
            result_.t0DebtPenalty
        );

        result_.poolDebt              = loanTakeResult.poolDebt;
        result_.newLup                = loanTakeResult.newLup;
        result_.t0DebtInAuctionChange = loanTakeResult.t0DebtInAuctionChange;
        result_.settledAuction        = loanTakeResult.settledAuction;
    }

    function _settleAuction(
        AuctionsState storage auctions_,
        mapping(uint256 => Bucket) storage buckets_,
        DepositsState storage deposits_,
        address borrowerAddress_,
        uint256 borrowerCollateral_,
        uint256 poolType_
    ) internal returns (uint256 remainingCollateral_) {
        if (poolType_ == uint8(PoolType.ERC721)) {
            uint256 lps;
            uint256 bucketIndex;

            (remainingCollateral_, lps, bucketIndex) = _settleNFTCollateral(
                auctions_,
                buckets_,
                deposits_,
                borrowerAddress_,
                borrowerCollateral_
            );

            emit AuctionNFTSettle(borrowerAddress_, remainingCollateral_, lps, bucketIndex);

        } else {
            remainingCollateral_ = borrowerCollateral_;

            emit AuctionSettle(borrowerAddress_, remainingCollateral_);
        }

        _removeAuction(auctions_, borrowerAddress_);
    }

    /**
     *  @notice Performs NFT collateral settlement by rounding down borrower's collateral amount and by moving borrower's token ids to pool claimable array.
     *  @param borrowerAddress_    Address of the borrower that exits auction.
     *  @param borrowerCollateral_ Borrower collateral amount before auction exit (could be fragmented as result of partial takes).
     *  @return floorCollateral_   Rounded down collateral, the number of NFT tokens borrower can pull after auction exit.
     *  @return lps_               LPs given to the borrower to compensate fractional collateral (if any).
     *  @return bucketIndex_       Index of the bucket with LPs to compensate.
     */
    function _settleNFTCollateral(
        AuctionsState storage auctions_,
        mapping(uint256 => Bucket) storage buckets_,
        DepositsState storage deposits_,
        address borrowerAddress_,
        uint256 borrowerCollateral_
    ) internal returns (uint256 floorCollateral_, uint256 lps_, uint256 bucketIndex_) {
        floorCollateral_ = (borrowerCollateral_ / Maths.WAD) * Maths.WAD; // floor collateral of borrower

        // if there's fraction of NFTs remaining then reward difference to borrower as LPs in auction price bucket
        if (floorCollateral_ != borrowerCollateral_) {
            // cover borrower's fractional amount with LPs in auction price bucket
            uint256 fractionalCollateral = borrowerCollateral_ - floorCollateral_;

            uint256 auctionPrice = _auctionPrice(
                auctions_.liquidations[borrowerAddress_].kickMomp,
                auctions_.liquidations[borrowerAddress_].neutralPrice,
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
        } else {
            revert NoReservesAuction();
        }
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

        if (_isCollateralized(borrowerDebt , borrowerCollateral, kickResult_.lup, poolState_.poolType)) {
            revert BorrowerOk();
        }

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

        borrower.t0Debt = kickResult_.t0KickedDebt;

        emit Kick(
            borrowerAddress_,
            borrowerDebt + kickResult_.kickPenalty,
            borrower.collateral,
            bondSize
        );
    }

    /**
     *  @notice Performs take collateral on an auction and updates bond size and kicker balance accordingly.
     *  @param  params_ Struct containing take action params details.
     *  @return Collateral amount taken.
     *  @return Quote token to be received from taker.
     *  @return T0 debt amount repaid.
     *  @return T0 borrower debt (including penalty).
     *  @return T0 penalty debt.
     *  @return Excess quote token that can result after a take (NFT case).
    */
    function _take(
        AuctionsState storage auctions_,
        TakeParams memory params_
    ) internal returns (uint256, uint256, uint256, uint256, uint256, uint256) {
        Liquidation storage liquidation = auctions_.liquidations[params_.borrower];

        TakeLocalVars memory vars = _prepareTake(liquidation, params_.t0Debt, params_.collateral, params_.inflator);

        // These are placeholder max values passed to calculateTakeFlows because there is no explicit bound on the
        // quote token amount in take calls (as opposed to bucketTake)
        vars.unscaledDeposit = type(uint256).max;
        vars.bucketScale     = Maths.WAD;

        // In the case of take, the taker binds the collateral qty but not the quote token qty
        // ugly to get take work like a bucket take -- this is the max amount of quote token from the take that could go to
        // reduce the debt of the borrower -- analagous to the amount of deposit in the bucket for a bucket take
        vars = _calculateTakeFlowsAndBondChange(
            Maths.min(params_.collateral, params_.takeCollateral),
            params_.inflator,
            vars
        );

        _rewardTake(auctions_, liquidation, vars);

        emit Take(
            params_.borrower,
            vars.scaledQuoteTokenAmount,
            vars.collateralAmount,
            vars.bondChange,
            vars.isRewarded
        );

        if (params_.poolType == uint8(PoolType.ERC721)) {
            // slither-disable-next-line divide-before-multiply
            uint256 collateralTaken = (vars.collateralAmount / 1e18) * 1e18; // solidity rounds down, so if 2.5 it will be 2.5 / 1 = 2

            if (collateralTaken != vars.collateralAmount && params_.collateral >= collateralTaken + 1e18) { // collateral taken not a round number
                collateralTaken += 1e18; // round up collateral to take
                // taker should send additional quote tokens to cover difference between collateral needed to be taken and rounded collateral, at auction price
                // borrower will get quote tokens for the difference between rounded collateral and collateral taken to cover debt
                vars.excessQuoteToken = Maths.wmul(collateralTaken - vars.collateralAmount, vars.auctionPrice);
            }

            vars.collateralAmount = collateralTaken;
        }

        return (
            vars.collateralAmount,
            vars.scaledQuoteTokenAmount,
            vars.t0RepayAmount,
            vars.t0Debt,
            vars.t0DebtPenalty,
            vars.excessQuoteToken
        );
    }

    /**
     *  @notice Performs bucket take collateral on an auction and rewards taker and kicker (if case).
     *  @param  params_ Struct containing take action details.
     *  @return Collateral amount taken.
     *  @return T0 debt amount repaid.
     *  @return T0 borrower debt (including penalty).
     *  @return T0 penalty debt.
    */
    function _takeBucket(
        AuctionsState storage auctions_,
        mapping(uint256 => Bucket) storage buckets_,
        DepositsState storage deposits_,
        BucketTakeParams memory params_
    ) internal returns (uint256, uint256, uint256, uint256) {
        if (params_.collateral == 0) revert InsufficientCollateral(); // revert if borrower's collateral is 0

        Liquidation storage liquidation = auctions_.liquidations[params_.borrower];

        TakeLocalVars memory vars = _prepareTake(liquidation, params_.t0Debt, params_.collateral, params_.inflator);

        vars.unscaledDeposit = Deposits.unscaledValueAt(deposits_, params_.index);

        if (vars.unscaledDeposit == 0) revert InsufficientLiquidity(); // revert if no quote tokens in arbed bucket

        vars.bucketPrice  = _priceAt(params_.index);

        // cannot arb with a price lower than the auction price
        if (vars.auctionPrice > vars.bucketPrice) revert AuctionPriceGtBucketPrice();
        
        // if deposit take then price to use when calculating take is bucket price
        if (params_.depositTake) vars.auctionPrice = vars.bucketPrice;

        vars.bucketScale = Deposits.scale(deposits_, params_.index);

        vars = _calculateTakeFlowsAndBondChange(
            params_.collateral,
            params_.inflator,
            vars
        );

        _rewardBucketTake(
            auctions_,
            deposits_,
            buckets_,
            liquidation,
            params_.index,
            params_.depositTake,
            vars
        );

        emit BucketTake(
            params_.borrower,
            params_.index,
            vars.scaledQuoteTokenAmount,
            vars.collateralAmount,
            vars.bondChange,
            vars.isRewarded
        );

        return (
            vars.collateralAmount,
            vars.t0RepayAmount,
            vars.t0Debt,
            vars.t0DebtPenalty
        );
    }

    function _takeLoan(
        AuctionsState storage auctions_,
        mapping(uint256 => Bucket) storage buckets_,
        DepositsState storage deposits_,
        LoansState storage loans_,
        PoolState memory poolState_,
        Borrower memory borrower_,
        address borrowerAddress_,
        uint256 t0RepaidDebt_,
        uint256 t0DebtPenalty_
    ) internal returns (TakeFromLoanResult memory result_) {

        TakeFromLoanLocalVars memory vars;

        vars.borrowerDebt =  Maths.wmul(borrower_.t0Debt, poolState_.inflator);
        vars.repaidDebt   =  Maths.wmul(t0RepaidDebt_,    poolState_.inflator);
        vars.borrowerDebt -= vars.repaidDebt;

        result_.poolDebt = poolState_.debt - vars.repaidDebt;

        if (t0DebtPenalty_ != 0) result_.poolDebt += Maths.wmul(t0DebtPenalty_, poolState_.inflator);

        // check that taking from loan doesn't leave borrower debt under min debt amount
        _revertOnMinDebt(loans_, result_.poolDebt, vars.borrowerDebt);

        result_.newLup = _lup(deposits_, result_.poolDebt);

        vars.inAuction = true;

        if (_isCollateralized(vars.borrowerDebt, borrower_.collateral, result_.newLup, poolState_.poolType)) {
            // borrower becomes re-collateralized
            vars.inAuction = false;

            result_.settledAuction = true;

            // remove entire borrower debt from pool auctions debt accumulator
            result_.t0DebtInAuctionChange = borrower_.t0Debt;

            // settle auction and update borrower's collateral with value after settlement
            result_.remainingCollateral = _settleAuction(
                auctions_,
                buckets_,
                deposits_,
                borrowerAddress_,
                borrower_.collateral,
                poolState_.poolType
            );

            borrower_.collateral = result_.remainingCollateral;
        } else {
            // partial repay, remove only the paid debt from pool auctions debt accumulator
            result_.t0DebtInAuctionChange = t0RepaidDebt_;
        }

        borrower_.t0Debt -= t0RepaidDebt_;

        // update loan state, stamp borrower t0Np only when exiting from auction
        Loans.update(
            loans_,
            auctions_,
            deposits_,
            borrower_,
            borrowerAddress_,
            vars.borrowerDebt,
            poolState_.rate,
            result_.newLup,
            vars.inAuction,
            !vars.inAuction // stamp borrower t0Np if exiting from auction
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
     *  @param  inflator_               Current pool inflator.
     *  @param  vars                    TakeParams for the take/buckettake
     */
    function _calculateTakeFlowsAndBondChange(
        uint256              totalCollateral_,
        uint256              inflator_,
        TakeLocalVars memory vars
    ) internal pure returns (
        TakeLocalVars memory
    ) {
        // price is the current auction price, which is the price paid by the LENDER for collateral
        // from the borrower point of view, the price is actually (1-bpf) * price, as the rewards to the
        // bond holder are effectively paid for by the borrower.
        uint256 borrowerPayoffFactor = (vars.isRewarded) ? Maths.WAD - uint256(vars.bpf)                       : Maths.WAD;
        uint256 borrowerPrice        = (vars.isRewarded) ? Maths.wmul(borrowerPayoffFactor, vars.auctionPrice) : vars.auctionPrice;

        // If there is no unscaled quote token bound, then we pass in max, but that cannot be scaled without an overflow.  So we check in the line below.
        vars.scaledQuoteTokenAmount = (vars.unscaledDeposit != type(uint256).max) ? Maths.wmul(vars.unscaledDeposit, vars.bucketScale) : type(uint256).max;

        uint256 borrowerCollateralValue = Maths.wmul(totalCollateral_, borrowerPrice);
        
        if (vars.scaledQuoteTokenAmount <= vars.borrowerDebt && vars.scaledQuoteTokenAmount <= borrowerCollateralValue) {
            // quote token used to purchase is constraining factor
            vars.collateralAmount         = Maths.wdiv(vars.scaledQuoteTokenAmount, borrowerPrice);
            vars.t0RepayAmount            = Maths.wdiv(vars.scaledQuoteTokenAmount, inflator_);
            vars.unscaledQuoteTokenAmount = vars.unscaledDeposit;

        } else if (vars.borrowerDebt <= borrowerCollateralValue) {
            // borrower debt is constraining factor
            vars.collateralAmount = Maths.wdiv(vars.borrowerDebt, borrowerPrice);
            vars.t0RepayAmount            = vars.t0Debt;
            vars.unscaledQuoteTokenAmount = Maths.wdiv(vars.borrowerDebt, vars.bucketScale);

            vars.scaledQuoteTokenAmount   = (vars.isRewarded) ? Maths.wdiv(vars.borrowerDebt, borrowerPayoffFactor) : vars.borrowerDebt;

        } else {
            // collateral available is constraint
            vars.collateralAmount         = totalCollateral_;
            vars.t0RepayAmount            = Maths.wdiv(borrowerCollateralValue, inflator_);
            vars.unscaledQuoteTokenAmount = Maths.wdiv(borrowerCollateralValue, vars.bucketScale);

            vars.scaledQuoteTokenAmount   = Maths.wmul(vars.collateralAmount, vars.auctionPrice);
        }

        if (vars.isRewarded) {
            // take is above neutralPrice, Kicker is rewarded
            vars.bondChange = Maths.wmul(vars.scaledQuoteTokenAmount, uint256(vars.bpf));
        } else {
            // take is above neutralPrice, Kicker is penalized
            vars.bondChange = Maths.wmul(vars.scaledQuoteTokenAmount, uint256(-vars.bpf));
        }

        return vars;
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
        liquidation.kicker       = msg.sender;
        liquidation.kickTime     = uint96(block.timestamp);
        liquidation.kickMomp     = uint96(momp_);
        liquidation.bondSize     = uint160(bondSize_);
        liquidation.bondFactor   = uint96(bondFactor_);
        liquidation.neutralPrice = uint96(neutralPrice_);

        // increment number of active auctions
        ++auctions_.noOfAuctions;

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
        }
        else if(auctions_.head == borrower_) {
            // liquidation is the head
            auctions_.liquidations[liquidation.next].prev = address(0);
            auctions_.head = liquidation.next;
        }
        else if(auctions_.tail == borrower_) {
            // liquidation is the tail
            auctions_.liquidations[liquidation.prev].next = address(0);
            auctions_.tail = liquidation.prev;
        }
        else {
            // liquidation is in the middle
            auctions_.liquidations[liquidation.prev].next = liquidation.next;
            auctions_.liquidations[liquidation.next].prev = liquidation.prev;
        }
        // delete liquidation
        delete auctions_.liquidations[borrower_];
    }

    function _rewardTake(
        AuctionsState storage auctions_,
        Liquidation storage liquidation_,
        TakeLocalVars memory vars
    ) internal {
        if (vars.isRewarded) {
            // take is below neutralPrice, Kicker is rewarded
            liquidation_.bondSize                 += uint160(vars.bondChange);
            auctions_.kickers[vars.kicker].locked += vars.bondChange;
            auctions_.totalBondEscrowed           += vars.bondChange;
        } else {
            // take is above neutralPrice, Kicker is penalized
            vars.bondChange = Maths.min(liquidation_.bondSize, vars.bondChange);

            liquidation_.bondSize                 -= uint160(vars.bondChange);
            auctions_.kickers[vars.kicker].locked -= vars.bondChange;
            auctions_.totalBondEscrowed           -= vars.bondChange;
        }
    }

    /**
     *  @notice Rewards actors of a bucket take action.
     *  @param  deposits_    Deposits state
     *  @param  bucketIndex_ Bucket index.
     *  @param  vars         Struct containing take action result details.
     */
    function _rewardBucketTake(
        AuctionsState storage auctions_,
        DepositsState storage deposits_,
        mapping(uint256 => Bucket) storage buckets_,
        Liquidation storage liquidation_,
        uint256 bucketIndex_,
        bool depositTake_,
        TakeLocalVars memory vars
    ) internal {
        Bucket storage bucket = buckets_[bucketIndex_];

        uint256 bucketExchangeRate = Buckets.getUnscaledExchangeRate(
            bucket.collateral,
            bucket.lps,
            vars.unscaledDeposit,
            vars.bucketScale,
            vars.bucketPrice
        );

        uint256 bankruptcyTime = bucket.bankruptcyTime;
        uint256 totalLPsReward;

        // if arb take - taker is awarded collateral * (bucket price - auction price) worth (in quote token terms) units of LPB in the bucket
        if (!depositTake_) {
            uint256 takerReward                   = Maths.wmul(vars.collateralAmount, vars.bucketPrice - vars.auctionPrice);
            uint256 takerRewardUnscaledQuoteToken = Maths.wdiv(takerReward,           vars.bucketScale);

            totalLPsReward = Maths.wrdivr(takerRewardUnscaledQuoteToken, bucketExchangeRate);

            Buckets.addLenderLPs(bucket, bankruptcyTime, msg.sender, totalLPsReward);
        }

        uint256 kickerLPsReward;

        // the bondholder/kicker is awarded bond change worth of LPB in the bucket
        if (vars.isRewarded) {
            kickerLPsReward = Maths.wrdivr(Maths.wdiv(vars.bondChange, vars.bucketScale), bucketExchangeRate);
            totalLPsReward  += kickerLPsReward;

            Buckets.addLenderLPs(bucket, bankruptcyTime, vars.kicker, kickerLPsReward);
        } else {
            // take is above neutralPrice, Kicker is penalized
            vars.bondChange = Maths.min(liquidation_.bondSize, vars.bondChange);

            liquidation_.bondSize                 -= uint160(vars.bondChange);

            auctions_.kickers[vars.kicker].locked -= vars.bondChange;
            auctions_.totalBondEscrowed           -= vars.bondChange;
        }

        Deposits.unscaledRemove(deposits_, bucketIndex_, vars.unscaledQuoteTokenAmount); // remove quote tokens from bucket’s deposit

        // total rewarded LPs are added to the bucket LP balance
        bucket.lps += totalLPsReward;

        // collateral is added to the bucket’s claimable collateral
        bucket.collateral += vars.collateralAmount;

        emit BucketTakeLPAwarded(
            msg.sender,
            vars.kicker,
            totalLPsReward - kickerLPsReward,
            kickerLPsReward
        );
    }

    function _auctionPrice(
        uint256 kickMomp_,
        uint256 neutralPrice_,
        uint256 kickTime_
    ) internal view returns (uint256 price_) {
        uint256 elapsedHours = Maths.wdiv((block.timestamp - kickTime_) * 1e18, 1 hours * 1e18);

        elapsedHours -= Maths.min(elapsedHours, 1e18);  // price locked during cure period

        int256 timeAdjustment  = PRBMathSD59x18.mul(-1 * 1e18, int256(elapsedHours)); 
        uint256 referencePrice = Maths.max(kickMomp_, neutralPrice_); 

        price_ = 32 * Maths.wmul(referencePrice, uint256(PRBMathSD59x18.exp2(timeAdjustment)));
    }

    /**
     *  @notice Calculates bond penalty factor.
     *  @dev Called in kick and take.
     *  @param debt_         Borrower debt.
     *  @param collateral_   Borrower collateral.
     *  @param neutralPrice_ NP of auction.
     *  @param bondFactor_   Factor used to determine bondSize.
     *  @param auctionPrice_ Auction price at the time of call.
     *  @return bpf_         Factor used in determining bond Reward (positive) or penalty (negative).
     */
    function _bpf(
        uint256 debt_,
        uint256 collateral_,
        uint256 neutralPrice_,
        uint256 bondFactor_,
        uint256 auctionPrice_
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
                        int256(neutralPrice_) - int256(auctionPrice_),
                        int256(neutralPrice_) - thresholdPrice
                    )
                )
            );
        } else {
            int256 val = int256(neutralPrice_) - int256(auctionPrice_);
            if (val < 0 )      sign = -1e18;
            else if (val != 0) sign = 1e18;
        }

        return PRBMathSD59x18.mul(int256(bondFactor_), sign);
    }

    /**
     *  @notice Utility function to validate take and calculate take's parameters.
     *  @param  liquidation_ Liquidation struct holding auction details.
     *  @param  t0Debt_      Borrower t0 debt.
     *  @param  collateral_  Borrower collateral.
     *  @param  inflator_    The pool's inflator, used to calculate borrower debt.
     *  @return vars         The prepared vars for take action.
     */
    function _prepareTake(
        Liquidation storage liquidation_,
        uint256 t0Debt_,
        uint256 collateral_,
        uint256 inflator_
    ) internal returns (TakeLocalVars memory vars) {

        uint256 kickTime = liquidation_.kickTime;
        if (kickTime == 0) revert NoAuction();
        if (block.timestamp - kickTime <= 1 hours) revert TakeNotPastCooldown();

        vars.t0Debt = t0Debt_;

        // if first take borrower debt is increased by 7% penalty
        if (!liquidation_.alreadyTaken) {
            vars.t0DebtPenalty = Maths.wmul(t0Debt_, 0.07 * 1e18);
            vars.t0Debt        += vars.t0DebtPenalty;

            liquidation_.alreadyTaken = true;
        }

        vars.borrowerDebt = Maths.wmul(vars.t0Debt, inflator_);

        uint256 neutralPrice = liquidation_.neutralPrice;

        vars.auctionPrice = _auctionPrice(liquidation_.kickMomp, neutralPrice, kickTime);
        vars.bpf          = _bpf(
            vars.borrowerDebt,
            collateral_,
            neutralPrice,
            liquidation_.bondFactor,
            vars.auctionPrice
        );
        vars.factor       = uint256(1e18 - Maths.maxInt(0, vars.bpf));
        vars.kicker       = liquidation_.kicker;
        vars.isRewarded   = (vars.bpf  >= 0);
    }

    /**********************/
    /*** View Functions ***/
    /**********************/

    function _lup(
        DepositsState storage deposits_,
        uint256 debt_
    ) internal view returns (uint256) {
        return _priceAt(Deposits.findIndexOfSum(deposits_, debt_));
    }

}
