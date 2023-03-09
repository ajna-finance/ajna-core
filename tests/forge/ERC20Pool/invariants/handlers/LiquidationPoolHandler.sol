
// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.14;

import '@std/Vm.sol';
import '@std/console.sol';

import { Maths }             from 'src/libraries/internal/Maths.sol';
import { _priceAt }          from 'src/libraries/helpers/PoolHelper.sol';
import { MAX_FENWICK_INDEX } from 'src/libraries/helpers/PoolHelper.sol';

import { BasicPoolHandler } from './BasicPoolHandler.sol';

import {
    LENDER_MIN_BUCKET_INDEX,
    LENDER_MAX_BUCKET_INDEX,
    BaseHandler
} from './BaseHandler.sol';

abstract contract UnBoundedLiquidationPoolHandler is BaseHandler {

    function kickAuction(
        address borrower_
    ) internal useTimestamps resetAllPreviousLocalState {
        numberOfCalls['UBLiquidationHandler.kickAuction']++;

        _fenwickAccrueInterest();

        _updatePoolState();

        _updatePreviousReserves();

        (uint256 borrowerDebt, , ) = _poolInfo.borrowerInfo(address(_pool), borrower_);
        (uint256 interestRate, )   = _pool.interestRateInfo();

        try _pool.kick(borrower_, 7388) {

            shouldExchangeRateChange = true;
            shouldReserveChange      = true;

            _updateCurrentReserves();

            // reserve increase by 3 months of interest of borrowerDebt
            loanKickIncreaseInReserve = Maths.wmul(borrowerDebt, Maths.wdiv(interestRate, 4 * 1e18));

        } catch {
            _resetReservesAndExchangeRate();
        }
    }

    function kickWithDeposit(uint256 bucketIndex) internal useTimestamps resetAllPreviousLocalState {
        _fenwickAccrueInterest();

        _updatePoolState();

        _updatePreviousReserves();

        try _pool.kickWithDeposit(bucketIndex, 7388) {

            shouldExchangeRateChange = true;
            shouldReserveChange      = true;

        } catch {
            _resetReservesAndExchangeRate();
        }
    }

    function withdrawBonds(
        address kicker_,
        uint256 maxAmount_
    ) internal useTimestamps resetAllPreviousLocalState {
        _fenwickAccrueInterest();

        _updatePoolState();

        _updatePreviousExchangeRate();   
        _updatePreviousReserves();

        try _pool.withdrawBonds(kicker_, maxAmount_) {

            shouldExchangeRateChange = false;
            shouldReserveChange      = false;

            _updateCurrentExchangeRate();
            _updateCurrentReserves();

        } catch {
            _resetReservesAndExchangeRate();
        }
    }

    function takeAuction(
        address borrower_,
        uint256 amount_,
        address taker_
    ) internal useTimestamps resetAllPreviousLocalState {
        numberOfCalls['UBLiquidationHandler.takeAuction']++;

        _fenwickAccrueInterest();

        _updatePoolState();

        _updatePreviousReserves();

        (uint256 borrowerDebt, , )         = _poolInfo.borrowerInfo(address(_pool), borrower_);
        (address kicker, , , , , , , , , ) = _pool.auctionInfo(borrower_);
        (
            uint256 claimableBond,
            uint256 lockedBond
        ) = _pool.kickerInfo(kicker);

        uint256 totalBond = claimableBond + lockedBond;
        
        try _pool.take(borrower_, amount_, taker_, bytes("")) {

            shouldExchangeRateChange = true;
            shouldReserveChange      = true;

            _updateCurrentReserves();

            (claimableBond, lockedBond) = _pool.kickerInfo(kicker);

            // calculate amount of kicker reward/penalty that will decrease/increase reserves
            if (totalBond > claimableBond + lockedBond) {
                kickerBondChange = totalBond - claimableBond - lockedBond;

                isKickerRewarded = false;
            }
            else {
                kickerBondChange = claimableBond + lockedBond - totalBond;

                isKickerRewarded = true;
            }

            (kicker, , , , , , , , , ) = _pool.auctionInfo(borrower_);
            
            if (!alreadyTaken[borrower_]) {
                // reserve increase by 7% of borrower debt on first take
                firstTakeIncreaseInReserve = Maths.wmul(borrowerDebt, 0.07 * 1e18);
                firstTake = true;

                // if auction is settled by take
                if (kicker == address(0))  alreadyTaken[borrower_] = false;
                else                       alreadyTaken[borrower_] = true;
            }
            else firstTake = false;

        } catch {
            _resetReservesAndExchangeRate();
        }
    }

    function bucketTake(
        address taker_,
        address borrower_,
        bool depositTake_,
        uint256 bucketIndex_
    ) internal useTimestamps resetAllPreviousLocalState {
        numberOfCalls['UBLiquidationHandler.bucketTake']++;

        _fenwickAccrueInterest();
        _updatePoolState();

        _updatePreviousReserves();
        _updatePreviousExchangeRate();

        (uint256 borrowerDebt, , ) = _poolInfo.borrowerInfo(address(_pool), borrower_);

        (address kicker, , , , , , , , , ) = _pool.auctionInfo(borrower_);
        (uint256 lpsBeforeTake, )          = _pool.lenderInfo(bucketIndex_, kicker);
        (
            uint256 claimableBond,
            uint256 lockedBond
        ) = _pool.kickerInfo(kicker);

        uint256 totalBond = claimableBond + lockedBond;

        try _pool.bucketTake(borrower_, depositTake_, bucketIndex_) {

            shouldExchangeRateChange = false;
            shouldReserveChange      = true;

            _updateCurrentReserves();
            _updateCurrentExchangeRate();

            (claimableBond, lockedBond) = _pool.kickerInfo(kicker);

            // deposit time of taker change when he gets lps as reward from bucketTake
            lenderDepositTime[taker_][bucketIndex_] = block.timestamp;

            (uint256 lpsAfterTake, ) = _pool.lenderInfo(bucketIndex_, kicker);

            // check if kicker was awarded LPs
            if (lpsAfterTake > lpsBeforeTake) {
                // update kicker deposit time to reflect LPs reward
                lenderDepositTime[kicker][bucketIndex_] = block.timestamp;

                isKickerRewarded = true;
            }
            else {
                kickerBondChange = claimableBond + lockedBond - totalBond;

                isKickerRewarded = false;
            }

            (kicker, , , , , , , , , ) = _pool.auctionInfo(borrower_);
            
            if (!alreadyTaken[borrower_]) {
                // reserve increase by 7% of borrower debt on first take
                firstTakeIncreaseInReserve = Maths.wmul(borrowerDebt, 0.07 * 1e18);
                firstTake = true;

                // if auction is settled by take
                if (kicker == address(0)) alreadyTaken[borrower_] = false;
                else                      alreadyTaken[borrower_] = true;
            }
            else firstTake = false;

        } catch {
            _resetReservesAndExchangeRate();
        }
    }

    function settleAuction(
        address borrower_,
        uint256 maxDepth_
    ) internal useTimestamps resetAllPreviousLocalState {
        _fenwickAccrueInterest();

        _updatePoolState();

        (
            uint256 borrowerDebt,
            uint256 collateral,
        ) = _poolInfo.borrowerInfo(address(_pool), borrower_);

        uint256 noOfBuckets = LENDER_MAX_BUCKET_INDEX - LENDER_MIN_BUCKET_INDEX + 1;

        uint256[] memory changeInDeposit = new uint256[](noOfBuckets);
        uint256 depositUsed;

        uint256 bucketDepth = maxDepth_;

        // settle borrower debt with exchanging borrower collateral with quote tokens starting from hpb
        while (bucketDepth != 0 && borrowerDebt != 0 && collateral != 0) {
            uint256 bucketIndex       = fenwickIndexForSum(1 + depositUsed);
            uint256 bucketUsed        = bucketIndex - LENDER_MIN_BUCKET_INDEX;
            uint256 maxSettleableDebt = Maths.wmul(collateral, _priceAt(bucketIndex));

            if (bucketIndex != MAX_FENWICK_INDEX) {
                // debt is greater than bucket deposit then exchange all deposit with collateral
                if (borrowerDebt > fenwickDeposits[bucketIndex] && maxSettleableDebt >= fenwickDeposits[bucketIndex]) {
                    borrowerDebt                -= fenwickDeposits[bucketIndex];
                    changeInDeposit[bucketUsed] += fenwickDeposits[bucketIndex];
                    collateral                  -= fenwickDeposits[bucketIndex] / _priceAt(bucketIndex);
                    depositUsed                 += fenwickDeposits[bucketIndex];
                }
                // collateral value is greater than borrower debt then exchange collateral with deposit
                else if (maxSettleableDebt >= borrowerDebt) {
                    changeInDeposit[bucketUsed] += borrowerDebt;
                    collateral                  -= borrowerDebt / _priceAt(bucketIndex);
                    depositUsed                 += borrowerDebt;
                    borrowerDebt                = 0;
                }
                // exchange all collateral with deposit
                else {
                    changeInDeposit[bucketUsed] += maxSettleableDebt;
                    depositUsed                 += maxSettleableDebt;
                    collateral                  = 0;
                    borrowerDebt                -= maxSettleableDebt;
                }
            } else collateral = 0;

            bucketDepth -= 1;
        }

        // if collateral becomes 0 and still debt is left, settle debt by reserves and hpb making buckets bankrupt
        if (borrowerDebt != 0 && collateral == 0) {
            (uint256 reserves, , , , )= _poolInfo.poolReservesInfo(address(_pool));

            borrowerDebt -= Maths.min(reserves, borrowerDebt);

            while (bucketDepth != 0 && borrowerDebt != 0) {
                uint256 bucketIndex = fenwickIndexForSum(1 + depositUsed);
                uint256 bucketUsed  = bucketIndex - LENDER_MIN_BUCKET_INDEX;

                if(bucketIndex != MAX_FENWICK_INDEX) {

                    // debt is greater than bucket deposit
                    if (borrowerDebt > (fenwickDeposits[bucketIndex] - changeInDeposit[bucketUsed])) {
                        borrowerDebt                -= (fenwickDeposits[bucketIndex] - changeInDeposit[bucketUsed]);
                        changeInDeposit[bucketUsed] += (fenwickDeposits[bucketIndex] - changeInDeposit[bucketUsed]);
                        depositUsed                 += (fenwickDeposits[bucketIndex] - changeInDeposit[bucketUsed]);
                    }
                    // bucket deposit is greater than debt
                    else {
                        changeInDeposit[bucketUsed] += borrowerDebt;
                        depositUsed                 += borrowerDebt;
                        borrowerDebt                = 0;
                    }
                }

                bucketDepth -= 1;
            }
        }

        try _pool.settle(borrower_, maxDepth_) {

            shouldExchangeRateChange = true;
            shouldReserveChange      = true;

            for (uint256 bucket = 0; bucket <= maxDepth_; bucket++) {
                _fenwickRemove(changeInDeposit[bucket], bucket + LENDER_MIN_BUCKET_INDEX);
            }

        } catch {
            _resetReservesAndExchangeRate();
        }
    }
}

contract LiquidationPoolHandler is UnBoundedLiquidationPoolHandler, BasicPoolHandler {

    constructor(
        address pool_,
        address quote_,
        address collateral_,
        address poolInfo_,
        uint256 numOfActors_,
        address testContract_
    ) BasicPoolHandler(pool_, quote_, collateral_, poolInfo_, numOfActors_, testContract_) {

    }

    function _kickAuction(
        uint256 borrowerIndex_,
        uint256 amount_,
        uint256 kickerIndex_
    ) internal useRandomActor(kickerIndex_) {
        numberOfCalls['BLiquidationHandler.kickAuction']++;

        shouldExchangeRateChange = true;

        borrowerIndex_   = constrictToRange(borrowerIndex_, 0, actors.length - 1);
        address borrower = actors[borrowerIndex_];
        address kicker   = _actor;
        amount_          = constrictToRange(amount_, 1, 1e30);

        ( , , , uint256 kickTime, , , , , , ) = _pool.auctionInfo(borrower);

        if (kickTime == 0) {
            (uint256 debt, , ) = _pool.borrowerInfo(borrower);

            if (debt == 0) {
                changePrank(borrower);
                _actor = borrower;
                super.drawDebt(amount_);
            }

            changePrank(kicker);
            _actor = kicker;
            super.kickAuction(borrower);
        }

        // skip some time for more interest
        vm.warp(block.timestamp + 2 hours);
    }

    function kickAuction(
        uint256 borrowerIndex_,
        uint256 amount_,
        uint256 kickerIndex_
    ) external useTimestamps {
        _kickAuction(borrowerIndex_, amount_, kickerIndex_);
    }

    function kickWithDeposit(
        uint256 kickerIndex_,
        uint256 bucketIndex_
    ) external useRandomActor(kickerIndex_) useRandomLenderBucket(bucketIndex_) useTimestamps {
        super.kickWithDeposit(_lenderBucketIndex);
    }

    function withdrawBonds(
        uint256 kickerIndex_,
        uint256 maxAmount_
    ) external useRandomActor(kickerIndex_) useTimestamps {
        super.withdrawBonds(_actor, maxAmount_);
    }

    function takeAuction(
        uint256 borrowerIndex_,
        uint256 amount_,
        uint256 actorIndex_
    ) external useRandomActor(actorIndex_) useTimestamps {
        numberOfCalls['BLiquidationHandler.takeAuction']++;

        amount_ = constrictToRange(amount_, 1, 1e30);

        shouldExchangeRateChange = true;

        borrowerIndex_ = constrictToRange(borrowerIndex_, 0, actors.length - 1);

        address borrower = actors[borrowerIndex_];
        address taker    = _actor;

        ( , , , uint256 kickTime, , , , , , ) = _pool.auctionInfo(borrower);

        if (kickTime == 0)_kickAuction(borrowerIndex_, amount_ * 100, actorIndex_);

        changePrank(taker);
        super.takeAuction(borrower, amount_, taker);
    }

    function bucketTake(
        uint256 borrowerIndex_,
        uint256 bucketIndex_,
        bool depositTake_,
        uint256 takerIndex_
    ) external useRandomActor(takerIndex_) useTimestamps {
        numberOfCalls['BLiquidationHandler.bucketTake']++;

        shouldExchangeRateChange = true;

        borrowerIndex_ = constrictToRange(borrowerIndex_, 0, actors.length - 1);
        bucketIndex_   = constrictToRange(bucketIndex_, LENDER_MIN_BUCKET_INDEX, LENDER_MAX_BUCKET_INDEX);

        address borrower = actors[borrowerIndex_];
        address taker    = _actor;

        ( , , , uint256 kickTime, , , , , , ) = _pool.auctionInfo(borrower);

        if (kickTime == 0) _kickAuction(borrowerIndex_, 1e24, bucketIndex_);

        changePrank(taker);
        super.bucketTake(taker, borrower, depositTake_, bucketIndex_);
    }

    function settleAuction(uint256 actorIndex, uint256 borrowerIndex, uint256 bucketIndex) external useRandomActor(actorIndex) useTimestamps {
        borrowerIndex = constrictToRange(borrowerIndex, 0, actors.length - 1);
        bucketIndex = constrictToRange(bucketIndex, LENDER_MIN_BUCKET_INDEX, LENDER_MAX_BUCKET_INDEX);

        address borrower = actors[borrowerIndex];
        uint256 maxDepth = LENDER_MAX_BUCKET_INDEX - LENDER_MIN_BUCKET_INDEX;

        address actor = _actor;

        ( , , , uint256 kickTime, , , , , , ) = _pool.auctionInfo(borrower);

        if (kickTime == 0) _kickAuction(borrowerIndex, 1e24, bucketIndex);

        changePrank(actor);
        // skip time to make auction clearable
        vm.warp(block.timestamp + 73 hours);
        super.settleAuction(borrower, maxDepth);
    }
}