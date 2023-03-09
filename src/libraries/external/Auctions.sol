// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.14;

import { PRBMathSD59x18 } from "@prb-math/contracts/PRBMathSD59x18.sol";

import { PoolType } from '../../interfaces/pool/IPool.sol';

import {
    AuctionsState,
    Borrower,
    Bucket,
    BurnEvent,
    DepositsState,
    Kicker,
    Lender,
    Liquidation,
    LoansState,
    PoolState,
    ReserveAuctionState
}                                    from '../../interfaces/pool/commons/IPoolState.sol';
import {
    BucketTakeResult,
    KickResult,
    SettleParams,
    SettleResult,
    TakeResult
}                                    from '../../interfaces/pool/commons/IPoolInternals.sol';
import { StartReserveAuctionParams } from '../../interfaces/pool/commons/IPoolReserveAuctionActions.sol';

import {
    _claimableReserves,
    _indexOf,
    _isCollateralized,
    _priceAt,
    _reserveAuctionPrice,
    _roundToScale,
    MAX_FENWICK_INDEX,
    MAX_PRICE,
    MIN_PRICE
}                                   from '../helpers/PoolHelper.sol';
import {
    _revertOnMinDebt,
    _revertIfPriceDroppedBelowLimit
}                                   from '../helpers/RevertsHelper.sol';

import { Buckets }  from '../internal/Buckets.sol';
import { Deposits } from '../internal/Deposits.sol';
import { Loans }    from '../internal/Loans.sol';
import { Maths }    from '../internal/Maths.sol';

/**
    @title  Auctions library
    @notice External library containing actions involving auctions within pool:
            - Kickers: kick undercollateralized loans; settle auctions; claim bond rewards
            - Bidders: take auctioned collateral
            - Reserve purchasers: start auctions; take reserves
 */
library Auctions {

    /*******************************/
    /*** Function Params Structs ***/
    /*******************************/

    struct BucketTakeParams {
        address borrower;        // borrower address to take from
        bool    depositTake;     // deposit or arb take, used by bucket take
        uint256 index;           // bucket index, used by bucket take
        uint256 inflator;        // [WAD] current pool inflator
        uint256 collateralScale; // precision of collateral token based on decimals
    }
    struct TakeParams {
        address borrower;        // borrower address to take from
        uint256 takeCollateral;  // [WAD] desired amount to take
        uint256 inflator;        // [WAD] current pool inflator
        uint256 poolType;        // pool type (ERC20 or NFT)
        uint256 collateralScale; // precision of collateral token based on decimals
    }

    /*************************/
    /*** Local Var Structs ***/
    /*************************/

    struct KickLocalVars {
        uint256 borrowerDebt;       // [WAD] the accrued debt of kicked borrower
        uint256 borrowerCollateral; // [WAD] amount of kicked borrower collateral
        uint256 neutralPrice;       // [WAD] neutral price recorded in kick action
        uint256 noOfLoans;          // number of loans and auctions in pool (used to calculate MOMP)
        uint256 momp;               // [WAD] MOMP of kicked auction
        uint256 bondFactor;         // [WAD] bond factor of kicked auction
        uint256 bondSize;           // [WAD] bond size of kicked auction
        uint256 t0KickPenalty;      // [WAD] t0 debt added as kick penalty
        uint256 kickPenalty;        // [WAD] current debt added as kick penalty
    }
    struct KickWithDepositLocalVars {
        uint256 amountToDebitFromDeposit; // [WAD] the amount of quote tokens used to kick and debited from lender deposit
        uint256 bucketCollateral;         // [WAD] amount of collateral in bucket
        uint256 bucketDeposit;            // [WAD] amount of quote tokens in bucket
        uint256 bucketLPs;                // [WAD] LPs of the bucket
        uint256 bucketPrice;              // [WAD] bucket price
        uint256 bucketRate;               // [WAD] bucket exchange rate
        uint256 bucketScale;              // [WAD] bucket scales
        uint256 bucketUnscaledDeposit;    // [WAD] unscaled amount of quote tokens in bucket
        uint256 lenderLPs;                // [WAD] LPs of lender in bucket
        uint256 redeemedLPs;              // [WAD] LPs used by kick action
    }
    struct SettleLocalVars {
        uint256 collateralUsed;     // [WAD] collateral used to settle debt
        uint256 debt;               // [WAD] debt to settle
        uint256 depositToRemove;    // [WAD] deposit used by settle auction
        uint256 hpbCollateral;      // [WAD] amount of collateral in HPB bucket
        uint256 hpbUnscaledDeposit; // [WAD] unscaled amount of of quote tokens in HPB bucket before settle
        uint256 hpbLPs;             // [WAD] amount of LPs in HPB bucket
        uint256 index;              // index of settling bucket
        uint256 maxSettleableDebt;  // [WAD] max amount that can be settled with existing collateral
        uint256 price;              // [WAD] price of settling bucket
        uint256 scaledDeposit;      // [WAD] scaled amount of quote tokens in bucket
        uint256 scale;              // [WAD] scale of settling bucket
        uint256 unscaledDeposit;    // [WAD] unscaled amount of quote tokens in bucket
    }
    struct TakeLocalVars {
        uint256 auctionPrice;             // [WAD] The price of auction.
        uint256 bondChange;               // [WAD] The change made on the bond size (beeing reward or penalty).
        uint256 borrowerDebt;             // [WAD] The accrued debt of auctioned borrower.
        int256  bpf;                      // The bond penalty factor.
        uint256 bucketPrice;              // [WAD] The bucket price.
        uint256 bucketScale;              // [WAD] The bucket scale.
        uint256 collateralAmount;         // [WAD] The amount of collateral taken.
        uint256 excessQuoteToken;         // [WAD] Difference of quote token that borrower receives after take (for fractional NFT only)
        uint256 factor;                   // The take factor, calculated based on bond penalty factor.
        bool    isRewarded;               // True if kicker is rewarded (auction price lower than neutral price), false if penalized (auction price greater than neutral price).
        address kicker;                   // Address of auction kicker.
        uint256 quoteTokenAmount;         // [WAD] Scaled quantity in Fenwick tree and before 1-bpf factor, paid for collateral
        uint256 t0RepayAmount;            // [WAD] The amount of debt (quote tokens) that is recovered / repayed by take t0 terms.
        uint256 t0BorrowerDebt;           // [WAD] Borrower's t0 debt.
        uint256 t0DebtPenalty;            // [WAD] Borrower's t0 penalty - 7% from current debt if intial take, 0 otherwise.
        uint256 unscaledDeposit;          // [WAD] Unscaled bucket quantity
        uint256 unscaledQuoteTokenAmount; // [WAD] The unscaled token amount that taker should pay for collateral taken.
    }

    /**************/
    /*** Events ***/
    /**************/

    // See `IPoolEvents` for descriptions
    event AuctionSettle(address indexed borrower, uint256 collateral);
    event AuctionNFTSettle(address indexed borrower, uint256 collateral, uint256 lps, uint256 index);
    event BucketTake(address indexed borrower, uint256 index, uint256 amount, uint256 collateral, uint256 bondChange, bool isReward);
    event BucketTakeLPAwarded(address indexed taker, address indexed kicker, uint256 lpAwardedTaker, uint256 lpAwardedKicker);
    event Kick(address indexed borrower, uint256 debt, uint256 collateral, uint256 bond);
    event Take(address indexed borrower, uint256 amount, uint256 collateral, uint256 bondChange, bool isReward);
    event RemoveQuoteToken(address indexed lender, uint256 indexed price, uint256 amount, uint256 lpRedeemed, uint256 lup);
    event ReserveAuction(uint256 claimableReservesRemaining, uint256 auctionPrice, uint256 currentBurnEpoch);
    event Settle(address indexed borrower, uint256 settledDebt);

    /**************/
    /*** Errors ***/
    /**************/

    // See `IPoolErrors` for descriptions
    event BucketBankruptcy(uint256 indexed index, uint256 lpForfeited);
    error AuctionActive();
    error AuctionNotClearable();
    error AuctionPriceGtBucketPrice();
    error BorrowerOk();
    error CollateralRoundingNeededButNotPossible();
    error InsufficientLiquidity();
    error InsufficientCollateral();
    error InvalidAmount();
    error NoAuction();
    error NoReserves();
    error NoReservesAuction();
    error PriceBelowLUP();
    error ReserveAuctionTooSoon();
    error TakeNotPastCooldown();

    /***************************/
    /***  External Functions ***/
    /***************************/

    /**
     *  @notice Settles the debt of the given loan / borrower.
     *  @dev    write state:
     *          - Deposits.unscaledRemove() (remove amount in Fenwick tree, from index):
     *              - update values array state
     *          - Buckets.addCollateral:
     *              - increment bucket.collateral and bucket.lps accumulator
     *              - addLenderLPs:
     *                  - increment lender.lps accumulator and lender.depositTime state
     *          - update borrower state
     *  @dev    reverts on:
     *              - loan is not in auction NoAuction()
     *              - 72 hours didn't pass and auction still has collateral AuctionNotClearable()
     *  @dev    emit events:
     *              - Settle
     *              - BucketBankruptcy
     *  @param  params_ Settle params
     *  @return result_ The result of settle action.
     */
    function settlePoolDebt(
        AuctionsState storage auctions_,
        mapping(uint256 => Bucket) storage buckets_,
        DepositsState storage deposits_,
        LoansState storage loans_,
        SettleParams memory params_
    ) external returns (SettleResult memory result_) {
        uint256 kickTime = auctions_.liquidations[params_.borrower].kickTime;
        if (kickTime == 0) revert NoAuction();

        Borrower memory borrower = loans_.borrowers[params_.borrower];
        if ((block.timestamp - kickTime < 72 hours) && (borrower.collateral != 0)) revert AuctionNotClearable();

        result_.debtPreAction       = borrower.t0Debt;
        result_.collateralPreAction = borrower.collateral;
        result_.t0DebtSettled       = borrower.t0Debt;
        result_.collateralSettled   = borrower.collateral;

        // auction has debt to cover with remaining collateral
        while (params_.bucketDepth != 0 && borrower.t0Debt != 0 && borrower.collateral != 0) {
            SettleLocalVars memory vars;

            (vars.index, , vars.scale) = Deposits.findIndexAndSumOfSum(deposits_, 1);
            vars.hpbUnscaledDeposit = Deposits.unscaledValueAt(deposits_, vars.index);
            vars.unscaledDeposit    = vars.hpbUnscaledDeposit;
            vars.price              = _priceAt(vars.index);

            if (vars.unscaledDeposit != 0) {
                vars.debt              = Maths.wmul(borrower.t0Debt, params_.inflator); // current debt to be settled
                vars.maxSettleableDebt = Maths.wmul(borrower.collateral, vars.price);   // max debt that can be settled with existing collateral
                vars.scaledDeposit     = Maths.wmul(vars.scale, vars.unscaledDeposit);

                // enough deposit in bucket and collateral avail to settle entire debt
                if (vars.scaledDeposit >= vars.debt && vars.maxSettleableDebt >= vars.debt) {
                    // remove only what's needed to settle the debt
                    vars.unscaledDeposit = Maths.wdiv(vars.debt, vars.scale);
                    vars.collateralUsed  = Maths.wdiv(vars.debt, vars.price);

                    // settle the entire debt
                    borrower.t0Debt = 0;
                }
                // enough collateral, therefore not enough deposit to settle entire debt, we settle only deposit amount
                else if (vars.maxSettleableDebt >= vars.scaledDeposit) {
                    vars.collateralUsed = Maths.wdiv(vars.scaledDeposit, vars.price);

                    // subtract from debt the corresponding t0 amount of deposit
                    borrower.t0Debt -= Maths.wdiv(vars.scaledDeposit, params_.inflator);
                }
                // settle constrained by collateral available
                else {
                    vars.unscaledDeposit = Maths.wdiv(vars.maxSettleableDebt, vars.scale);
                    vars.collateralUsed  = borrower.collateral;

                    borrower.t0Debt -= Maths.wdiv(vars.maxSettleableDebt, params_.inflator);
                }

                // remove settled collateral from loan
                borrower.collateral -= vars.collateralUsed;

                Bucket storage hpb = buckets_[vars.index];
                vars.hpbLPs        = hpb.lps;
                vars.hpbCollateral = hpb.collateral + vars.collateralUsed;

                // set amount to remove as min of calculated amount and available deposit (to prevent rounding issues)
                vars.unscaledDeposit    = Maths.min(vars.hpbUnscaledDeposit, vars.unscaledDeposit);
                vars.hpbUnscaledDeposit -= vars.unscaledDeposit;

                // remove amount to settle debt from bucket (could be entire deposit or only the settled debt)
                Deposits.unscaledRemove(deposits_, vars.index, vars.unscaledDeposit);

                // check if bucket healthy - set bankruptcy if collateral is 0 and entire deposit was used to settle and there's still LPs
                if (vars.hpbCollateral == 0 && vars.hpbUnscaledDeposit == 0 && vars.hpbLPs != 0) {
                    emit BucketBankruptcy(vars.index, vars.hpbLPs);
                    hpb.lps            = 0;
                    hpb.bankruptcyTime = block.timestamp;
                } else {
                    // add settled collateral into bucket
                    hpb.collateral = vars.hpbCollateral;
                }

            } else {
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

                (vars.index, , vars.scale) = Deposits.findIndexAndSumOfSum(deposits_, 1);
                vars.unscaledDeposit = Deposits.unscaledValueAt(deposits_, vars.index);
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
                    
                    if (hpbBucket.collateral == 0) {                                                   // existing LPs for the bucket shall become unclaimable.
                        emit BucketBankruptcy(vars.index, hpbBucket.lps);
                        hpbBucket.lps            = 0;
                        hpbBucket.bankruptcyTime = block.timestamp;
                    }
                }

                --params_.bucketDepth;
            }
        }

        result_.t0DebtSettled -= borrower.t0Debt;

        emit Settle(params_.borrower, result_.t0DebtSettled);

        if (borrower.t0Debt == 0) {
            // settle auction
            (borrower.collateral, ) = _settleAuction(
                auctions_,
                buckets_,
                deposits_,
                params_.borrower,
                borrower.collateral,
                params_.poolType
            );
        }

        result_.debtPostAction      = borrower.t0Debt;
        result_.collateralRemaining =  borrower.collateral;
        result_.collateralSettled   -= result_.collateralRemaining;

        // update borrower state
        loans_.borrowers[params_.borrower] = borrower;
    }

    /**
     *  @notice Called to start borrower liquidation and to update the auctions queue.
     *  @param  poolState_       Current state of the pool.
     *  @param  borrowerAddress_ Address of the borrower to kick.
     *  @param  limitIndex_      Index of the lower bound of NP tolerated when kicking the auction.
     *  @return kickResult_      The result of the kick action.
     */
    function kick(
        AuctionsState storage auctions_,
        DepositsState storage deposits_,
        LoansState    storage loans_,
        PoolState calldata poolState_,
        address borrowerAddress_,
        uint256 limitIndex_
    ) external returns (
        KickResult memory
    ) {
        return _kick(
            auctions_,
            deposits_,
            loans_,
            poolState_,
            borrowerAddress_,
            limitIndex_,
            0
        );
    }

    /**
     *  @notice Called by lenders to kick loans using their deposits.
     *  @dev    write state:
     *              - Deposits.unscaledRemove (remove amount in Fenwick tree, from index):
     *                  - update values array state
     *              - decrement lender.lps accumulator
     *              - decrement bucket.lps accumulator
     *  @dev    emit events:
     *              - RemoveQuoteToken
     *  @param  poolState_  Current state of the pool.
     *  @param  index_      The deposit index from where lender removes liquidity.
     *  @param  limitIndex_ Index of the lower bound of NP tolerated when kicking the auction.
     *  @return kickResult_ The result of the kick action.
     */
    function kickWithDeposit(
        AuctionsState storage auctions_,
        DepositsState storage deposits_,
        mapping(uint256 => Bucket) storage buckets_,
        LoansState storage loans_,
        PoolState calldata poolState_,
        uint256 index_,
        uint256 limitIndex_
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

        vars.amountToDebitFromDeposit = Maths.wmul(vars.lenderLPs, vars.bucketRate);  // calculate amount to remove based on lender LPs in bucket

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
            limitIndex_,
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
            vars.redeemedLPs = Maths.wdiv(vars.amountToDebitFromDeposit, vars.bucketRate);

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
     *  @dev    reverts on:
     *              - insufficient collateral InsufficientCollateral()
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
        PoolState memory poolState_,
        address borrowerAddress_,
        bool    depositTake_,
        uint256 index_,
        uint256 collateralScale_
    ) external returns (BucketTakeResult memory result_) {
        Borrower memory borrower = loans_.borrowers[borrowerAddress_];

        if (borrower.collateral == 0) revert InsufficientCollateral(); // revert if borrower's collateral is 0

        result_.debtPreAction       = borrower.t0Debt;
        result_.collateralPreAction = borrower.collateral;

        // bucket take auction
        TakeLocalVars memory vars = _takeBucket(
            auctions_,
            buckets_,
            deposits_,
            borrower,
            BucketTakeParams({
                borrower:        borrowerAddress_,
                inflator:        poolState_.inflator,
                depositTake:     depositTake_,
                index:           index_,
                collateralScale: collateralScale_
            })
        );

        // update borrower after take
        borrower.collateral -= vars.collateralAmount;
        borrower.t0Debt     = vars.t0BorrowerDebt - vars.t0RepayAmount;
        // update pool params after take
        poolState_.t0Debt += vars.t0DebtPenalty;
        poolState_.t0Debt -= vars.t0RepayAmount;
        poolState_.debt   = Maths.wmul(poolState_.t0Debt, poolState_.inflator);

        // update loan after take
        (
            result_.newLup,
            result_.settledAuction,
            result_.remainingCollateral,
            result_.compensatedCollateral
        ) = _takeLoan(auctions_, buckets_, deposits_, loans_, poolState_, borrower, borrowerAddress_);

        // complete take result struct
        result_.debtPostAction       = borrower.t0Debt;
        result_.collateralPostAction = borrower.collateral;
        result_.t0PoolDebt           = poolState_.t0Debt;
        result_.poolDebt             = poolState_.debt;
        result_.collateralAmount     = vars.collateralAmount;
        result_.t0DebtPenalty        = vars.t0DebtPenalty;
        // if settled then debt in auction changed is the entire borrower debt, otherwise only repaid amount
        result_.t0DebtInAuctionChange = result_.settledAuction ? vars.t0BorrowerDebt : vars.t0RepayAmount;
    }

    /**
     *  @notice Performs take collateral on an auction, rewards taker and kicker (if case) and updates loan info (settles auction if case).
     *  @dev    reverts on:
     *              - insufficient collateral InsufficientCollateral()
     *  @param  borrowerAddress_ Borrower address to take.
     *  @param  collateral_      Max amount of collateral that will be taken from the auction (max number of NFTs in case of ERC721 pool).
     *  @return result_          TakeResult struct containing details of take.
    */
    function take(
        AuctionsState storage auctions_,
        mapping(uint256 => Bucket) storage buckets_,
        DepositsState storage deposits_,
        LoansState storage loans_,
        PoolState memory poolState_,
        address borrowerAddress_,
        uint256 collateral_,
        uint256 collateralScale_
    ) external returns (TakeResult memory result_) {
        // revert if no amount to take
        if (collateral_ == 0) revert InvalidAmount();

        Borrower memory borrower = loans_.borrowers[borrowerAddress_];

        if (
            (poolState_.poolType == uint8(PoolType.ERC721) && borrower.collateral < 1e18) || // revert in case of NFT take when there isn't a full token to be taken
            (poolState_.poolType == uint8(PoolType.ERC20)  && borrower.collateral == 0)      // revert in case of ERC20 take when no collateral to be taken
        ) {
            revert InsufficientCollateral();
        }

        result_.debtPreAction       = borrower.t0Debt;
        result_.collateralPreAction = borrower.collateral;

        // take auction
        TakeLocalVars memory vars = _take(
            auctions_,
            borrower,
            TakeParams({
                borrower:        borrowerAddress_,
                takeCollateral:  collateral_,
                inflator:        poolState_.inflator,
                poolType:        poolState_.poolType,
                collateralScale: collateralScale_
            })
        );

        // update borrower after take
        borrower.collateral -= vars.collateralAmount;
        borrower.t0Debt     = vars.t0BorrowerDebt - vars.t0RepayAmount;
        // update pool params after take
        poolState_.t0Debt += vars.t0DebtPenalty;
        poolState_.t0Debt -= vars.t0RepayAmount;
        poolState_.debt   = Maths.wmul(poolState_.t0Debt, poolState_.inflator);

        // update loan after take
        (
            result_.newLup,
            result_.settledAuction,
            result_.remainingCollateral,
            result_.compensatedCollateral
        ) = _takeLoan(auctions_, buckets_, deposits_, loans_, poolState_, borrower, borrowerAddress_);

        // complete take result struct
        result_.debtPostAction       = borrower.t0Debt;
        result_.collateralPostAction = borrower.collateral;
        result_.t0PoolDebt           = poolState_.t0Debt;
        result_.poolDebt             = poolState_.debt;
        result_.collateralAmount     = vars.collateralAmount;
        result_.t0DebtPenalty        = vars.t0DebtPenalty;
        result_.quoteTokenAmount     = vars.quoteTokenAmount;
        result_.excessQuoteToken     = vars.excessQuoteToken;
        // if settled then debt in auction changed is the entire borrower debt, otherwise only repaid amount
        result_.t0DebtInAuctionChange = result_.settledAuction ? vars.t0BorrowerDebt : vars.t0RepayAmount;
    }

    /**
     *  @notice See `IPoolReserveAuctionActions` for descriptions.
     *  @dev    write state:
     *              - update reserveAuction.unclaimed accumulator
     *              - update reserveAuction.kicked timestamp state
     *  @dev    reverts on:
     *          - no reserves to claim NoReserves()
     *  @dev    emit events:
     *              - ReserveAuction
     */
    function startClaimableReserveAuction(
        AuctionsState storage auctions_,
        ReserveAuctionState storage reserveAuction_,
        StartReserveAuctionParams calldata params_
    ) external returns (uint256 kickerAward_) {
        // retrieve timestamp of latest burn event and last burn timestamp
        uint256 latestBurnEpoch   = reserveAuction_.latestBurnEventEpoch;
        uint256 lastBurnTimestamp = reserveAuction_.burnEvents[latestBurnEpoch].timestamp;

        // check that at least two weeks have passed since the last reserve auction completed, and that the auction was not kicked within the past 72 hours
        if (block.timestamp < lastBurnTimestamp + 2 weeks || block.timestamp - reserveAuction_.kicked <= 72 hours) {
            revert ReserveAuctionTooSoon();
        }

        uint256 curUnclaimedAuctionReserve = reserveAuction_.unclaimed;

        uint256 claimable = _claimableReserves(
            Maths.wmul(params_.t0PoolDebt, params_.inflator),
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

        // increment latest burn event epoch and update burn event timestamp
        latestBurnEpoch += 1;

        reserveAuction_.latestBurnEventEpoch = latestBurnEpoch;
        reserveAuction_.burnEvents[latestBurnEpoch].timestamp = block.timestamp;

        emit ReserveAuction(
            curUnclaimedAuctionReserve,
            _reserveAuctionPrice(block.timestamp),
            latestBurnEpoch
        );
    }

    /**
     *  @notice See `IPoolReserveAuctionActions` for descriptions.
     *  @dev    write state:
     *              - decrement reserveAuction.unclaimed accumulator
     *  @dev    reverts on:
     *              - not kicked or 72 hours didn't pass NoReservesAuction()
     *  @dev    emit events:
     *              - ReserveAuction
     */
    function takeReserves(
        ReserveAuctionState storage reserveAuction_,
        uint256 maxAmount_
    ) external returns (uint256 amount_, uint256 ajnaRequired_) {
        // revert if no amount to be taken
        if (maxAmount_ == 0) revert InvalidAmount();

        uint256 kicked = reserveAuction_.kicked;

        if (kicked != 0 && block.timestamp - kicked <= 72 hours) {
            uint256 unclaimed = reserveAuction_.unclaimed;
            uint256 price     = _reserveAuctionPrice(kicked);

            amount_       = Maths.min(unclaimed, maxAmount_);
            ajnaRequired_ = Maths.wmul(amount_, price);

            unclaimed -= amount_;

            reserveAuction_.unclaimed = unclaimed;

            uint256 totalBurned = reserveAuction_.totalAjnaBurned + ajnaRequired_;
            
            // accumulate additional ajna burned
            reserveAuction_.totalAjnaBurned = totalBurned;

            uint256 burnEventEpoch = reserveAuction_.latestBurnEventEpoch;

            // record burn event information to enable querying by staking rewards
            BurnEvent storage burnEvent = reserveAuction_.burnEvents[burnEventEpoch];
            burnEvent.totalInterest = reserveAuction_.totalInterestEarned;
            burnEvent.totalBurned   = totalBurned;

            emit ReserveAuction(unclaimed, price, burnEventEpoch);
        } else {
            revert NoReservesAuction();
        }
    }

    /***************************/
    /***  Internal Functions ***/
    /***************************/

    /**
     *  @notice Performs auction settle based on pool type, emits settle event and removes auction from auctions queue.
     *  @dev    emit events:
     *              - AuctionNFTSettle or AuctionSettle
     *  @param  borrowerAddress_       Address of the borrower that exits auction.
     *  @param  borrowerCollateral_    Borrower collateral amount before auction exit (in NFT could be fragmented as result of partial takes).
     *  @param  poolType_              Type of the pool (can be ERC20 or NFT).
     *  @return remainingCollateral_   Collateral remaining after auction is settled (same amount for ERC20 pool, rounded collateral for NFT pool).
     *  @return compensatedCollateral_ Amount of collateral compensated (NFT settle only), to be deducted from pool pledged collateral accumulator. 0 for ERC20 pools.
     */
    function _settleAuction(
        AuctionsState storage auctions_,
        mapping(uint256 => Bucket) storage buckets_,
        DepositsState storage deposits_,
        address borrowerAddress_,
        uint256 borrowerCollateral_,
        uint256 poolType_
    ) internal returns (uint256 remainingCollateral_, uint256 compensatedCollateral_) {

        if (poolType_ == uint8(PoolType.ERC721)) {
            uint256 lps;
            uint256 bucketIndex;

            remainingCollateral_ = (borrowerCollateral_ / Maths.WAD) * Maths.WAD; // floor collateral of borrower

            // if there's fraction of NFTs remaining then reward difference to borrower as LPs in auction price bucket
            if (remainingCollateral_ != borrowerCollateral_) {

                // calculate the amount of collateral that should be compensated with LPs
                compensatedCollateral_ = borrowerCollateral_ - remainingCollateral_;

                uint256 auctionPrice = _auctionPrice(
                    auctions_.liquidations[borrowerAddress_].kickMomp,
                    auctions_.liquidations[borrowerAddress_].neutralPrice,
                    auctions_.liquidations[borrowerAddress_].kickTime
                );

                // determine the bucket index to compensate fractional collateral
                bucketIndex = auctionPrice > MIN_PRICE ? _indexOf(auctionPrice) : MAX_FENWICK_INDEX;

                // deposit collateral in bucket and reward LPs to compensate fractional collateral
                lps = Buckets.addCollateral(
                    buckets_[bucketIndex],
                    borrowerAddress_,
                    Deposits.valueAt(deposits_, bucketIndex),
                    compensatedCollateral_,
                    _priceAt(bucketIndex)
                );
            }

            emit AuctionNFTSettle(borrowerAddress_, remainingCollateral_, lps, bucketIndex);

        } else {
            remainingCollateral_ = borrowerCollateral_;

            emit AuctionSettle(borrowerAddress_, remainingCollateral_);
        }

        _removeAuction(auctions_, borrowerAddress_);
    }

    /**
     *  @notice Called to start borrower liquidation and to update the auctions queue.
     *  @dev    write state:
     *              - _recordAuction:
     *                  - borrower -> liquidation mapping update
     *                  - increment auctions count accumulator
     *                  - increment auctions.totalBondEscrowed accumulator
     *                  - updates auction queue state
     *              - _updateKicker:
     *                  - update locked and claimable kicker accumulators
     *              - Loans.remove:
     *                  - delete borrower from indices => borrower address mapping
     *                  - remove loan from loans array
     *  @dev    emit events:
     *              - Kick
     *  @param  poolState_       Current state of the pool.
     *  @param  borrowerAddress_ Address of the borrower to kick.
     *  @param  limitIndex_      Index of the lower bound of NP tolerated when kicking the auction.
     *  @param  additionalDebt_  Additional debt to be used when calculating proposed LUP.
     *  @return kickResult_      The result of the kick action.
     */
    function _kick(
        AuctionsState storage auctions_,
        DepositsState storage deposits_,
        LoansState    storage loans_,
        PoolState calldata poolState_,
        address borrowerAddress_,
        uint256 limitIndex_,
        uint256 additionalDebt_
    ) internal returns (
        KickResult memory kickResult_
    ) {
        Borrower storage borrower = loans_.borrowers[borrowerAddress_];

        kickResult_.debtPreAction       = borrower.t0Debt;
        kickResult_.collateralPreAction = borrower.collateral;
        kickResult_.t0KickedDebt        = kickResult_.debtPreAction ;
        // add amount to remove to pool debt in order to calculate proposed LUP
        kickResult_.lup          = _lup(deposits_, poolState_.debt + additionalDebt_);

        KickLocalVars memory vars;
        vars.borrowerDebt       = Maths.wmul(kickResult_.t0KickedDebt, poolState_.inflator);
        vars.borrowerCollateral = kickResult_.collateralPreAction;

        // revert if kick on a collateralized borrower
        if (_isCollateralized(vars.borrowerDebt, vars.borrowerCollateral, kickResult_.lup, poolState_.poolType)) {
            revert BorrowerOk();
        }

        // calculate auction params
        vars.neutralPrice = Maths.wmul(borrower.t0Np, poolState_.inflator);
        // check if NP is not less than price at the limit index provided by the kicker - done to prevent frontrunning kick auction call with a large amount of loan
        // which will make it harder for kicker to earn a reward and more likely that the kicker is penalized
        _revertIfPriceDroppedBelowLimit(vars.neutralPrice, limitIndex_);

        vars.noOfLoans = Loans.noOfLoans(loans_) + auctions_.noOfAuctions;

        vars.momp = _priceAt(
            Deposits.findIndexOfSum(
                deposits_,
                Maths.wdiv(poolState_.debt, vars.noOfLoans * 1e18)
            )
        );

        (vars.bondFactor, vars.bondSize) = _bondParams(
            vars.borrowerDebt,
            vars.borrowerCollateral,
            vars.momp
        );

        // record liquidation info
        _recordAuction(
            auctions_,
            borrowerAddress_,
            vars.bondSize,
            vars.bondFactor,
            vars.momp,
            vars.neutralPrice
        );

        // update kicker balances and get the difference needed to cover bond (after using any kick claimable funds if any)
        kickResult_.amountToCoverBond = _updateKicker(auctions_, vars.bondSize);

        // remove kicked loan from heap
        Loans.remove(loans_, borrowerAddress_, loans_.indices[borrowerAddress_]);

        // when loan is kicked, penalty of three months of interest is added
        vars.t0KickPenalty = Maths.wmul(kickResult_.t0KickedDebt, Maths.wdiv(poolState_.rate, 4 * 1e18));
        vars.kickPenalty   = Maths.wmul(vars.t0KickPenalty, poolState_.inflator);

        kickResult_.t0PoolDebt   = poolState_.t0Debt + vars.t0KickPenalty;
        kickResult_.t0KickedDebt += vars.t0KickPenalty;

        // update borrower debt with kicked debt penalty
        borrower.t0Debt = kickResult_.t0KickedDebt;

        emit Kick(
            borrowerAddress_,
            vars.borrowerDebt + vars.kickPenalty,
            vars.borrowerCollateral,
            vars.bondSize
        );
    }

    /**
     *  @notice Performs take collateral on an auction and updates bond size and kicker balance accordingly.
     *  @dev    emit events:
     *              - Take
     *  @param  borrower_ Struct containing auctioned borrower details.
     *  @param  params_   Struct containing take action params details.
     *  @return vars_     Struct containing auction take vars.
    */
    function _take(
        AuctionsState storage auctions_,
        Borrower memory borrower_,
        TakeParams memory params_
    ) internal returns (TakeLocalVars memory vars_) {
        Liquidation storage liquidation = auctions_.liquidations[params_.borrower];

        vars_ = _prepareTake(
            liquidation,
            borrower_.t0Debt,
            borrower_.collateral,
            params_.inflator
        );

        // These are placeholder max values passed to calculateTakeFlows because there is no explicit bound on the
        // quote token amount in take calls (as opposed to bucketTake)
        vars_.unscaledDeposit = type(uint256).max;
        vars_.bucketScale     = Maths.WAD;

        uint256 takeableCollateral = borrower_.collateral;
        // for NFT take make sure the take flow and bond change calculation happens for the rounded collateral that can be taken
        if (params_.poolType == uint8(PoolType.ERC721)) {
            takeableCollateral = (takeableCollateral / 1e18) * 1e18;
        }

        // In the case of take, the taker binds the collateral qty but not the quote token qty
        // ugly to get take work like a bucket take -- this is the max amount of quote token from the take that could go to
        // reduce the debt of the borrower -- analagous to the amount of deposit in the bucket for a bucket take
        vars_ = _calculateTakeFlowsAndBondChange(
            Maths.min(takeableCollateral, params_.takeCollateral),
            params_.inflator,
            params_.collateralScale,
            vars_
        );

        _rewardTake(auctions_, liquidation, vars_);

        emit Take(
            params_.borrower,
            vars_.quoteTokenAmount,
            vars_.collateralAmount,
            vars_.bondChange,
            vars_.isRewarded
        );

        if (params_.poolType == uint8(PoolType.ERC721)) {
            // slither-disable-next-line divide-before-multiply
            uint256 collateralTaken = (vars_.collateralAmount / 1e18) * 1e18; // solidity rounds down, so if 2.5 it will be 2.5 / 1 = 2

            if (collateralTaken != vars_.collateralAmount) { // collateral taken not a round number
                if (Maths.min(borrower_.collateral, params_.takeCollateral) >= collateralTaken + 1e18) {
                    collateralTaken += 1e18; // round up collateral to take
                    // taker should send additional quote tokens to cover difference between collateral needed to be taken and rounded collateral, at auction price
                    // borrower will get quote tokens for the difference between rounded collateral and collateral taken to cover debt
                    vars_.excessQuoteToken = Maths.wmul(collateralTaken - vars_.collateralAmount, vars_.auctionPrice);
                    vars_.collateralAmount = collateralTaken;
                } else {
                    // shouldn't get here, but just in case revert
                    revert CollateralRoundingNeededButNotPossible();
                }
            }
        }
    }

    /**
     *  @notice Performs bucket take collateral on an auction and rewards taker and kicker (if case).
     *  @dev    emit events:
     *              - BucketTake
     *  @param  borrower_ Struct containing auctioned borrower details.
     *  @param  params_   Struct containing take action details.
     *  @return vars_     Struct containing auction take vars.
    */
    function _takeBucket(
        AuctionsState storage auctions_,
        mapping(uint256 => Bucket) storage buckets_,
        DepositsState storage deposits_,
        Borrower memory borrower_,
        BucketTakeParams memory params_
    ) internal returns (TakeLocalVars memory vars_) {
        Liquidation storage liquidation = auctions_.liquidations[params_.borrower];

        vars_= _prepareTake(
            liquidation,
            borrower_.t0Debt,
            borrower_.collateral,
            params_.inflator
        );

        vars_.unscaledDeposit = Deposits.unscaledValueAt(deposits_, params_.index);

        // revert if no quote tokens in arbed bucket
        if (vars_.unscaledDeposit == 0) revert InsufficientLiquidity();

        vars_.bucketPrice  = _priceAt(params_.index);

        // cannot arb with a price lower than the auction price
        if (vars_.auctionPrice > vars_.bucketPrice) revert AuctionPriceGtBucketPrice();
        
        // if deposit take then price to use when calculating take is bucket price
        if (params_.depositTake) vars_.auctionPrice = vars_.bucketPrice;

        vars_.bucketScale = Deposits.scale(deposits_, params_.index);

        vars_ = _calculateTakeFlowsAndBondChange(
            borrower_.collateral,
            params_.inflator,
            params_.collateralScale,
            vars_
        );

        // revert if bucket deposit cannot cover at least one unit of collateral
        if (vars_.collateralAmount == 0) revert InsufficientLiquidity();

        _rewardBucketTake(
            auctions_,
            deposits_,
            buckets_,
            liquidation,
            params_.index,
            params_.depositTake,
            vars_
        );

        emit BucketTake(
            params_.borrower,
            params_.index,
            vars_.quoteTokenAmount,
            vars_.collateralAmount,
            vars_.bondChange,
            vars_.isRewarded
        );
    }

    /**
     *  @notice Performs update of an auctioned loan that was taken (using bucket or regular take).
     *  @notice If borrower becomes recollateralized then auction is settled. Update loan's state.
     *  @dev    reverts on:
     *              - borrower debt less than pool min debt AmountLTMinDebt()
     *  @param  borrower_              Struct containing pool details.
     *  @param  borrower_              The borrower details owning loan that is taken.
     *  @param  borrowerAddress_       The address of the borrower.
     *  @return newLup_                The new LUP of pool (after debt is repaid).
     *  @return settledAuction_        True if auction is settled by the take action. (NFT take: rebalance borrower collateral in pool if true)
     *  @return remainingCollateral_   Borrower collateral remaining after take action. (NFT take: collateral to be rebalanced in case of NFT settlement)
     *  @return compensatedCollateral_ Amount of collateral compensated, to be deducted from pool pledged collateral accumulator.
    */
    function _takeLoan(
        AuctionsState storage auctions_,
        mapping(uint256 => Bucket) storage buckets_,
        DepositsState storage deposits_,
        LoansState storage loans_,
        PoolState memory poolState_,
        Borrower memory borrower_,
        address borrowerAddress_
    ) internal returns (
        uint256 newLup_,
        bool settledAuction_,
        uint256 remainingCollateral_,
        uint256 compensatedCollateral_
    ) {

        uint256 borrowerDebt = Maths.wmul(borrower_.t0Debt, poolState_.inflator);

        // check that taking from loan doesn't leave borrower debt under min debt amount
        _revertOnMinDebt(
            loans_,
            poolState_.debt,
            borrowerDebt,
            poolState_.quoteDustLimit
        );

        // calculate new lup with repaid debt from take
        newLup_ = _lup(deposits_, poolState_.debt);

        remainingCollateral_ = borrower_.collateral;

        if (_isCollateralized(borrowerDebt, borrower_.collateral, newLup_, poolState_.poolType)) {
            settledAuction_ = true;

            // settle auction and update borrower's collateral with value after settlement
            (remainingCollateral_, compensatedCollateral_) = _settleAuction(
                auctions_,
                buckets_,
                deposits_,
                borrowerAddress_,
                borrower_.collateral,
                poolState_.poolType
            );

            borrower_.collateral = remainingCollateral_;
        }

        // update loan state, stamp borrower t0Np only when exiting from auction
        Loans.update(
            loans_,
            auctions_,
            deposits_,
            borrower_,
            borrowerAddress_,
            poolState_.debt,
            poolState_.rate,
            newLup_,
            !settledAuction_,
            settledAuction_ // stamp borrower t0Np if exiting from auction
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
     *  @dev    write state:
     *              - update locked and claimable kicker accumulators
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

            // decrement total bond escrowed by bond size 
            auctions_.totalBondEscrowed -= bondSize_;
        } else {
            bondDifference_  = bondSize_ - kickerClaimable;
            kicker.claimable = 0;

            // decrement total bond escrowed by kicker claimable
            auctions_.totalBondEscrowed -= kickerClaimable;
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
        uint256              collateralScale_,
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
        vars.quoteTokenAmount = (vars.unscaledDeposit != type(uint256).max) ? Maths.wmul(vars.unscaledDeposit, vars.bucketScale) : type(uint256).max;

        uint256 borrowerCollateralValue = Maths.wmul(totalCollateral_, borrowerPrice);
        
        if (vars.quoteTokenAmount <= vars.borrowerDebt && vars.quoteTokenAmount <= borrowerCollateralValue) {
            // quote token used to purchase is constraining factor
            vars.collateralAmount         = _roundToScale(Maths.wdiv(vars.quoteTokenAmount, borrowerPrice), collateralScale_);
            vars.t0RepayAmount            = Maths.wdiv(vars.quoteTokenAmount, inflator_);
            vars.unscaledQuoteTokenAmount = vars.unscaledDeposit;

            vars.quoteTokenAmount         = Maths.wmul(vars.collateralAmount, vars.auctionPrice);

        } else if (vars.borrowerDebt <= borrowerCollateralValue) {
            // borrower debt is constraining factor
            vars.collateralAmount         = _roundToScale(Maths.wdiv(vars.borrowerDebt, borrowerPrice), collateralScale_);
            vars.t0RepayAmount            = vars.t0BorrowerDebt;
            vars.unscaledQuoteTokenAmount = Maths.wdiv(vars.borrowerDebt, vars.bucketScale);

            vars.quoteTokenAmount         = (vars.isRewarded) ? Maths.wdiv(vars.borrowerDebt, borrowerPayoffFactor) : vars.borrowerDebt;

        } else {
            // collateral available is constraint
            vars.collateralAmount         = totalCollateral_;
            vars.t0RepayAmount            = Maths.wdiv(borrowerCollateralValue, inflator_);
            vars.unscaledQuoteTokenAmount = Maths.wdiv(borrowerCollateralValue, vars.bucketScale);

            vars.quoteTokenAmount         = Maths.wmul(vars.collateralAmount, vars.auctionPrice);
        }

        if (vars.isRewarded) {
            // take is below neutralPrice, Kicker is rewarded
            vars.bondChange = Maths.wmul(vars.quoteTokenAmount, uint256(vars.bpf));
        } else {
            // take is above neutralPrice, Kicker is penalized
            vars.bondChange = Maths.wmul(vars.quoteTokenAmount, uint256(-vars.bpf));
        }

        return vars;
    }

    /**
     *  @notice Saves a new liquidation that was kicked.
     *  @dev    write state:
     *              - borrower -> liquidation mapping update
     *              - increment auctions count accumulator
     *              - increment auctions.totalBondEscrowed accumulator
     *              - updates auction queue state
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
     *  @dev    write state:
     *              - decrement kicker locked accumulator, increment kicker claimable accumumlator
     *              - decrement auctions count accumulator
     *              - decrement auctions.totalBondEscrowed accumulator
     *              - update auction queue state
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

    /**
     *  @notice Rewards actors of a regular take action.
     *  @dev    write state:
     *              - update liquidation bond size accumulator
     *              - update kicker's locked balance accumulator
     *              - update auctions.totalBondEscrowed accumulator
     *  @param  vars  Struct containing take action result details.
     */
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
     *  @dev    write state:
     *              - Buckets.addLenderLPs:
     *                  - increment taker lender.lps accumulator and lender.depositTime state
     *                  - increment kicker lender.lps accumulator and lender.depositTime state
     *              - update liquidation bond size accumulator
     *              - update kicker's locked balance accumulator
     *              - update auctions.totalBondEscrowed accumulator
     *              - Deposits.unscaledRemove() (remove amount in Fenwick tree, from index):
     *                  - update values array state
     *              - increment bucket.collateral and bucket.lps accumulator
     *  @dev    emit events:
     *              - BucketTakeLPAwarded
     *  @param  vars Struct containing take action result details.
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

        uint256 scaledDeposit = Maths.wmul(vars.unscaledDeposit, vars.bucketScale);

        uint256 exchangeRate = Buckets.getExchangeRate(
            bucket.collateral,
            bucket.lps,
            scaledDeposit,
            vars.bucketPrice
        );

        uint256 bankruptcyTime = bucket.bankruptcyTime;
        uint256 totalLPsReward;

        // if arb take - taker is awarded collateral * (bucket price - auction price) worth (in quote token terms) units of LPB in the bucket
        if (!depositTake_) {
            uint256 takerReward = Maths.wmul(vars.collateralAmount, vars.bucketPrice - vars.auctionPrice);

            totalLPsReward = Maths.wdiv(takerReward, exchangeRate);

            Buckets.addLenderLPs(bucket, bankruptcyTime, msg.sender, totalLPsReward);
        }

        uint256 kickerLPsReward;

        // the bondholder/kicker is awarded bond change worth of LPB in the bucket
        if (vars.isRewarded) {
            kickerLPsReward = Maths.wdiv(vars.bondChange, exchangeRate);
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

    /**
     *  @notice Calculates auction price.
     *  @param  kickMomp_     MOMP recorded at the time of kick.
     *  @param  neutralPrice_ Neutral Price of the auction.
     *  @param  kickTime_     Time when auction was kicked.
     *  @return price_        Calculated auction price.
     */
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
     *  @dev    Called in kick and take.
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
     *  @dev    write state:
     *              - update liquidation.alreadyTaken state
     *  @dev    reverts on:
     *              - loan is not in auction NoAuction()
     *              - in 1 hour cool down period TakeNotPastCooldown()
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

        vars.t0BorrowerDebt = t0Debt_;

        // if first take borrower debt is increased by 7% penalty
        if (!liquidation_.alreadyTaken) {
            vars.t0DebtPenalty  = Maths.wmul(t0Debt_, 0.07 * 1e18);
            vars.t0BorrowerDebt += vars.t0DebtPenalty;

            liquidation_.alreadyTaken = true;
        }

        vars.borrowerDebt = Maths.wmul(vars.t0BorrowerDebt, inflator_);

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
