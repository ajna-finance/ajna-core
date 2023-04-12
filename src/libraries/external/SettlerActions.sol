// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.14;

import { PoolType } from '../../interfaces/pool/IPool.sol';

import {
    AuctionsState,
    Borrower,
    Bucket,
    DepositsState,
    Kicker,
    Liquidation,
    LoansState,
    PoolState,
    ReserveAuctionState
}                       from '../../interfaces/pool/commons/IPoolState.sol';
import {
    SettleParams,
    SettleResult
}                       from '../../interfaces/pool/commons/IPoolInternals.sol';

import {
    _auctionPrice,
    _indexOf,
    _priceAt,
    MAX_FENWICK_INDEX,
    MIN_PRICE
}  from '../helpers/PoolHelper.sol';

import { Buckets }  from '../internal/Buckets.sol';
import { Deposits } from '../internal/Deposits.sol';
import { Loans }    from '../internal/Loans.sol';
import { Maths }    from '../internal/Maths.sol';

/**
    @title  Auction settler library
    @notice External library containing actions involving auctions within pool:
            - settle auctions
 */
library SettlerActions {

    /*************************/
    /*** Local Var Structs ***/
    /*************************/

    struct SettleLocalVars {
        uint256 collateralUsed;     // [WAD] collateral used to settle debt
        uint256 debt;               // [WAD] debt to settle
        uint256 depositToRemove;    // [WAD] deposit used by settle auction
        uint256 hpbCollateral;      // [WAD] amount of collateral in HPB bucket
        uint256 hpbUnscaledDeposit; // [WAD] unscaled amount of of quote tokens in HPB bucket before settle
        uint256 hpbLPs;             // [WAD] amount of LP in HPB bucket
        uint256 index;              // index of settling bucket
        uint256 maxSettleableDebt;  // [WAD] max amount that can be settled with existing collateral
        uint256 price;              // [WAD] price of settling bucket
        uint256 scaledDeposit;      // [WAD] scaled amount of quote tokens in bucket
        uint256 scale;              // [WAD] scale of settling bucket
        uint256 unscaledDeposit;    // [WAD] unscaled amount of quote tokens in bucket
    }

    /**************/
    /*** Events ***/
    /**************/

    // See `IPoolEvents` for descriptions
    event AuctionSettle(address indexed borrower, uint256 collateral);
    event AuctionNFTSettle(address indexed borrower, uint256 collateral, uint256 lps, uint256 index);
    event BucketBankruptcy(uint256 indexed index, uint256 lpForfeited);
    event Settle(address indexed borrower, uint256 settledDebt);

    /**************/
    /*** Errors ***/
    /**************/

    // See `IPoolErrors` for descriptions
    error AuctionNotClearable();
    error NoAuction();

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
     *              - addLenderLP:
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
        ReserveAuctionState storage reserveAuction_,
        PoolState calldata poolState_,
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
                vars.debt              = Maths.wmul(borrower.t0Debt, poolState_.inflator); // current debt to be settled
                vars.maxSettleableDebt = Maths.floorWmul(borrower.collateral, vars.price); // max debt that can be settled with existing collateral
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
                    borrower.t0Debt -= Maths.floorWdiv(vars.scaledDeposit, poolState_.inflator);
                }
                // settle constrained by collateral available
                else {
                    vars.unscaledDeposit = Maths.wdiv(vars.maxSettleableDebt, vars.scale);
                    vars.collateralUsed  = borrower.collateral;

                    borrower.t0Debt -= Maths.floorWdiv(vars.maxSettleableDebt, poolState_.inflator);
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
                    hpb.lps            = 0;
                    hpb.bankruptcyTime = block.timestamp;

                    emit BucketBankruptcy(
                        vars.index,
                        vars.hpbLPs
                    );
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

            uint256 assets      = Maths.wmul(poolState_.t0Debt - result_.t0DebtSettled + borrower.t0Debt, poolState_.inflator) + params_.poolBalance;
            uint256 liabilities = Deposits.treeSum(deposits_) + auctions_.totalBondEscrowed + reserveAuction_.unclaimed;
            uint256 reserves    = (assets > liabilities) ? (assets - liabilities) : 0;

            // settle debt from reserves -- round reserves down however
            borrower.t0Debt -= Maths.min(borrower.t0Debt, Maths.floorWdiv(reserves, poolState_.inflator));

            // if there's still debt after settling from reserves then start to forgive amount from next HPB
            // loop through remaining buckets if there's still debt to settle
            while (params_.bucketDepth != 0 && borrower.t0Debt != 0) {
                SettleLocalVars memory vars;

                (vars.index, , vars.scale) = Deposits.findIndexAndSumOfSum(deposits_, 1);
                vars.unscaledDeposit = Deposits.unscaledValueAt(deposits_, vars.index);
                vars.depositToRemove = Maths.wmul(vars.scale, vars.unscaledDeposit);
                vars.debt            = Maths.wmul(borrower.t0Debt, poolState_.inflator);

                // enough deposit in bucket to settle entire debt
                if (vars.depositToRemove >= vars.debt) {
                    Deposits.unscaledRemove(deposits_, vars.index, Maths.wdiv(vars.debt, vars.scale));
                    borrower.t0Debt  = 0;                                                              // no remaining debt to settle

                // not enough deposit to settle entire debt, we settle only deposit amount
                } else {
                    borrower.t0Debt -= Maths.floorWdiv(vars.depositToRemove, poolState_.inflator);     // subtract from remaining debt the corresponding t0 amount of deposit

                    Deposits.unscaledRemove(deposits_, vars.index, vars.unscaledDeposit);              // Remove all deposit from bucket
                    Bucket storage hpbBucket = buckets_[vars.index];

                    if (hpbBucket.collateral == 0) {                                                   // existing LP for the bucket shall become unclaimable.
                        hpbBucket.lps            = 0;
                        hpbBucket.bankruptcyTime = block.timestamp;

                        emit BucketBankruptcy(
                            vars.index,
                            hpbBucket.lps
                        );
                    }
                }

                --params_.bucketDepth;
            }
        }

        result_.t0DebtSettled -= borrower.t0Debt;

        emit Settle(
            params_.borrower,
            result_.t0DebtSettled
        );

        if (borrower.t0Debt == 0) {
            // settle auction
            (borrower.collateral, ) = _settleAuction(
                auctions_,
                buckets_,
                deposits_,
                params_.borrower,
                borrower.collateral,
                poolState_.poolType
            );
        }

        result_.debtPostAction      = borrower.t0Debt;
        result_.collateralRemaining =  borrower.collateral;
        result_.collateralSettled   -= result_.collateralRemaining;

        // update borrower state
        loans_.borrowers[params_.borrower] = borrower;
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

            // if there's fraction of NFTs remaining then reward difference to borrower as LP in auction price bucket
            if (remainingCollateral_ != borrowerCollateral_) {

                // calculate the amount of collateral that should be compensated with LP
                compensatedCollateral_ = borrowerCollateral_ - remainingCollateral_;

                uint256 auctionPrice = _auctionPrice(
                    auctions_.liquidations[borrowerAddress_].kickMomp,
                    auctions_.liquidations[borrowerAddress_].neutralPrice,
                    auctions_.liquidations[borrowerAddress_].kickTime
                );

                // determine the bucket index to compensate fractional collateral
                bucketIndex = auctionPrice > MIN_PRICE ? _indexOf(auctionPrice) : MAX_FENWICK_INDEX;

                // deposit collateral in bucket and reward LP to compensate fractional collateral
                lps = Buckets.addCollateral(
                    buckets_[bucketIndex],
                    borrowerAddress_,
                    Deposits.valueAt(deposits_, bucketIndex),
                    compensatedCollateral_,
                    _priceAt(bucketIndex)
                );
            }

            emit AuctionNFTSettle(
                borrowerAddress_,
                remainingCollateral_,
                lps,
                bucketIndex
            );

        } else {
            remainingCollateral_ = borrowerCollateral_;

            emit AuctionSettle(
                borrowerAddress_,
                remainingCollateral_
            );
        }

        _removeAuction(auctions_, borrowerAddress_);
    }

    /**
     *  @notice Removes auction and repairs the queue order.
     *  @notice Updates kicker's claimable balance with bond size awarded and subtracts bond size awarded from liquidationBondEscrowed.
     *  @dev    write state:
     *              - decrement kicker locked accumulator, increment kicker claimable accumumlator
     *              - decrement auctions count accumulator
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

}
