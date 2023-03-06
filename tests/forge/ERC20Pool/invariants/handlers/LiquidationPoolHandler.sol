
// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.14;

import '@std/Vm.sol';

import { BasicPoolHandler } from './BasicPoolHandler.sol';
import { LENDER_MIN_BUCKET_INDEX, LENDER_MAX_BUCKET_INDEX, BaseHandler } from './BaseHandler.sol';
import { Maths } from 'src/libraries/internal/Maths.sol';
import { _priceAt } from 'src/libraries/helpers/PoolHelper.sol';
import '@std/console.sol';

abstract contract UnBoundedLiquidationPoolHandler is BaseHandler {
    function kickAuction(address borrower) internal resetAllPreviousLocalState {
        numberOfCalls['UBLiquidationHandler.kickAuction']++;

        fenwickAccrueInterest();
        updatePoolState();
        updatePreviousReserves();

        (uint256 borrowerDebt, , ) = _poolInfo.borrowerInfo(address(_pool), borrower);
        (uint256 interestRate, )   = _pool.interestRateInfo();

        try _pool.kick(borrower, 7388) {
            shouldExchangeRateChange = true;
            shouldReserveChange      = true;
            updateCurrentReserves();

            // reserve increase by 3 months of interest of borrowerDebt
            loanKickIncreaseInReserve = Maths.wmul(borrowerDebt, Maths.wdiv(interestRate, 4 * 1e18));
        }
        catch {
            resetReservesAndExchangeRate();
        }
    }

    function kickWithDeposit(uint256 bucketIndex) internal resetAllPreviousLocalState {

        fenwickAccrueInterest();
        updatePoolState();
        updatePreviousReserves();

        try _pool.kickWithDeposit(bucketIndex, 7388) {
            shouldExchangeRateChange = true;
            shouldReserveChange      = true;
        } catch {
            resetReservesAndExchangeRate();
        }
    }

    function withdrawBonds(address kicker) internal resetAllPreviousLocalState {

        fenwickAccrueInterest();
        updatePoolState();
        updatePreviousExchangeRate();   
        updatePreviousReserves();

        try _pool.withdrawBonds(kicker) {
            shouldExchangeRateChange = false;
            shouldReserveChange      = false;

            updateCurrentExchangeRate();
            updateCurrentReserves();
        } catch {
            resetReservesAndExchangeRate();
        }
    }

    function takeAuction(address borrower, uint256 amount, address taker) internal resetAllPreviousLocalState {
        numberOfCalls['UBLiquidationHandler.takeAuction']++;

        fenwickAccrueInterest();
        updatePoolState();
        updatePreviousReserves();

        (uint256 borrowerDebt, , ) = _poolInfo.borrowerInfo(address(_pool), borrower);
        (address kicker, , , , , , , , , ) = _pool.auctionInfo(borrower);

        (uint256 claimableBond, uint256 lockedBond) = _pool.kickerInfo(kicker);

        uint256 totalBond = claimableBond + lockedBond;
        
        try _pool.take(borrower, amount, taker, bytes("")) {
            shouldExchangeRateChange = true;
            shouldReserveChange      = true;
            updateCurrentReserves();

            (claimableBond, lockedBond) = _pool.kickerInfo(kicker);

            // calculate amount of kicker reward/penalty that will decrease/increase reserves
            if(totalBond > claimableBond + lockedBond) {
                kickerBondChange = totalBond - claimableBond - lockedBond;
                isKickerRewarded = false;
            }
            else {
                kickerBondChange = claimableBond + lockedBond - totalBond;
                isKickerRewarded = true;
            }

            (kicker, , , , , , , , , ) = _pool.auctionInfo(borrower);
            
            if(!alreadyTaken[borrower]) {
                // reserve increase by 7% of borrower debt on first take
                firstTakeIncreaseInReserve = Maths.wmul(borrowerDebt, 0.07 * 1e18);
                firstTake = true;

                // if auction is settled by take
                if(kicker == address(0)) {
                    alreadyTaken[borrower] = false;
                } else {
                    alreadyTaken[borrower] = true;
                }
            }
            else {
                firstTake = false;
            }
        }
        catch {
            resetReservesAndExchangeRate();
        }
    }

    function bucketTake(address borrower, bool depositTake, uint256 bucketIndex) internal resetAllPreviousLocalState {
        numberOfCalls['UBLiquidationHandler.bucketTake']++;

        fenwickAccrueInterest();
        updatePoolState();
        updatePreviousReserves();
        updatePreviousExchangeRate();

        (uint256 borrowerDebt, , ) = _poolInfo.borrowerInfo(address(_pool), borrower);
        (address kicker, , , , , , , , , ) = _pool.auctionInfo(borrower);

        (uint256 claimableBond, uint256 lockedBond) = _pool.kickerInfo(kicker);

        uint256 totalBond = claimableBond + lockedBond;

        try _pool.bucketTake(borrower, depositTake, bucketIndex) {
            shouldExchangeRateChange = false;
            shouldReserveChange      = true;
            updateCurrentReserves();
            updateCurrentExchangeRate();

            (claimableBond, lockedBond) = _pool.kickerInfo(kicker);

            // deposit time of taker change when he gets lps as reward from bucketTake
            lenderDepositTime[_actor][bucketIndex] = block.timestamp;

            // calculate amount of kicker reward/penalty that will decrease/increase reserves
            if(totalBond > claimableBond + lockedBond) {
                kickerBondChange = totalBond - claimableBond - lockedBond;
                isKickerRewarded = true;
            }
            else {
                kickerBondChange = claimableBond + lockedBond - totalBond;
                isKickerRewarded = false;
            }

            (kicker, , , , , , , , , ) = _pool.auctionInfo(borrower);
            
            if(!alreadyTaken[borrower]) {
                // reserve increase by 7% of borrower debt on first take
                firstTakeIncreaseInReserve = Maths.wmul(borrowerDebt, 0.07 * 1e18);
                firstTake = true;

                // if auction is settled by take
                if(kicker == address(0)) {
                    alreadyTaken[borrower] = false;
                } else {
                    alreadyTaken[borrower] = true;
                }
            }
            else {
                firstTake = false;
            }
        }
        catch {
            resetReservesAndExchangeRate();
        }
    }

    function settleAuction(address borrower, uint256 maxDepth) internal resetAllPreviousLocalState {
        
        fenwickAccrueInterest();
        updatePoolState();

        (uint256 borrowerDebt, uint256 collateral, ) = _poolInfo.borrowerInfo(address(_pool), borrower);

        uint256 noOfBuckets = LENDER_MAX_BUCKET_INDEX - LENDER_MIN_BUCKET_INDEX + 1;

        uint256[] memory changeInDeposit = new uint256[](noOfBuckets);
        uint256 depositUsed;

        uint256 bucketDepth = maxDepth;

        // settle borrower debt with exchanging borrower collateral with quote tokens starting from hpb
        while(bucketDepth != 0 && borrowerDebt != 0 && collateral != 0) {
            uint256 bucketIndex = fenwickIndexForSum(1 + depositUsed);
            uint256 bucketUsed = bucketIndex - LENDER_MIN_BUCKET_INDEX;
            uint256 maxSettleableDebt = Maths.wmul(collateral, _priceAt(bucketIndex));

            if(bucketIndex != 7388) {

                // debt is greater than bucket deposit then exchange all deposit with collateral
                if(borrowerDebt > fenwickDeposits[bucketIndex] && maxSettleableDebt >= fenwickDeposits[bucketIndex]) {
                    borrowerDebt -= fenwickDeposits[bucketIndex];
                    changeInDeposit[bucketUsed] += fenwickDeposits[bucketIndex];
                    collateral -= fenwickDeposits[bucketIndex] / _priceAt(bucketIndex);
                    depositUsed += fenwickDeposits[bucketIndex];
                }
                // collateral value is greater than borrower debt then exchange collateral with deposit
                else if(maxSettleableDebt >= borrowerDebt) {
                    changeInDeposit[bucketUsed] += borrowerDebt;
                    collateral -= borrowerDebt / _priceAt(bucketIndex);
                    depositUsed += borrowerDebt;
                    borrowerDebt = 0;
                }
                // exchange all collateral with deposit
                else {
                    changeInDeposit[bucketUsed] += maxSettleableDebt;
                    depositUsed += maxSettleableDebt;
                    collateral = 0;
                    borrowerDebt -= maxSettleableDebt;
                }
            } else {
                collateral = 0;
            }
            bucketDepth -= 1;
        }

        // if collateral becomes 0 and still debt is left, settle debt by reserves and hpb making buckets bankrupt
        if(borrowerDebt != 0 && collateral == 0) {
            (uint256 reserves, , , , )= _poolInfo.poolReservesInfo(address(_pool));
            borrowerDebt -= Maths.min(reserves, borrowerDebt);
            while(bucketDepth != 0 && borrowerDebt != 0) {
                uint256 bucketIndex = fenwickIndexForSum(1 + depositUsed);
                uint256 bucketUsed = bucketIndex - LENDER_MIN_BUCKET_INDEX;

                if(bucketIndex != 7388) {

                    // debt is greater than bucket deposit
                    if(borrowerDebt > (fenwickDeposits[bucketIndex] - changeInDeposit[bucketUsed])) {
                        borrowerDebt -= (fenwickDeposits[bucketIndex] - changeInDeposit[bucketUsed]);
                        changeInDeposit[bucketUsed] += (fenwickDeposits[bucketIndex] - changeInDeposit[bucketUsed]);
                        depositUsed += (fenwickDeposits[bucketIndex] - changeInDeposit[bucketUsed]);
                    }

                    // bucket deposit is greater than debt
                    else {
                        changeInDeposit[bucketUsed] += borrowerDebt;
                        depositUsed += borrowerDebt;
                        borrowerDebt = 0;
                    }
                }
                bucketDepth -= 1;
            }
        }

        try _pool.settle(borrower, maxDepth) {
            shouldExchangeRateChange = true;
            shouldReserveChange      = true;
            for(uint256 bucket = 0; bucket <= maxDepth; bucket++) {
                fenwickRemove(changeInDeposit[bucket], bucket + LENDER_MIN_BUCKET_INDEX);
            }
        } catch {
            resetReservesAndExchangeRate();
        }
    }
}

contract LiquidationPoolHandler is UnBoundedLiquidationPoolHandler, BasicPoolHandler {

    constructor(address pool, address quote, address collateral, address poolInfo, uint256 numOfActors) BasicPoolHandler(pool, quote, collateral, poolInfo, numOfActors) {}

    function _kickAuction(uint256 borrowerIndex, uint256 amount, uint256 kickerIndex) internal useRandomActor(kickerIndex) {
        numberOfCalls['BLiquidationHandler.kickAuction']++;

        shouldExchangeRateChange = true;

        borrowerIndex    = constrictToRange(borrowerIndex, 0, actors.length - 1);
        address borrower = actors[borrowerIndex];
        address kicker   = _actor;
        amount           = constrictToRange(amount, 1, 1e30);

        ( , , , uint256 kickTime, , , , , , ) = _pool.auctionInfo(borrower);

        if (kickTime == 0) {
            (uint256 debt, , ) = _pool.borrowerInfo(borrower);
            if (debt == 0) {
                changePrank(borrower);
                _actor = borrower;
                super.drawDebt(amount);
            }
            changePrank(kicker);
            _actor = kicker;
            super.kickAuction(borrower);
        }

        // skip some time for more interest
        vm.warp(block.timestamp + 2 hours);
    }

    function kickAuction(uint256 borrowerIndex, uint256 amount, uint256 kickerIndex) external {
        _kickAuction(borrowerIndex, amount, kickerIndex);
    }

    function kickWithDeposit(uint256 kickerIndex, uint256 bucketIndex) external useRandomActor(kickerIndex) useRandomLenderBucket(bucketIndex) {
        super.kickWithDeposit(_lenderBucketIndex);
    }

    function withdrawBonds(uint256 kickerIndex) external useRandomActor(kickerIndex) {
        super.withdrawBonds(_actor);
    }

    function takeAuction(uint256 borrowerIndex, uint256 amount, uint256 actorIndex) external useRandomActor(actorIndex){
        numberOfCalls['BLiquidationHandler.takeAuction']++;

        amount = constrictToRange(amount, 1, 1e30);

        shouldExchangeRateChange = true;

        borrowerIndex = constrictToRange(borrowerIndex, 0, actors.length - 1);

        address borrower = actors[borrowerIndex];
        address taker    = _actor;

        ( , , , uint256 kickTime, , , , , , ) = _pool.auctionInfo(borrower);

        if (kickTime == 0) {
            _kickAuction(borrowerIndex, amount * 100, actorIndex);
        }
        changePrank(taker);
        super.takeAuction(borrower, amount, taker);
    }

    function bucketTake(uint256 borrowerIndex, uint256 bucketIndex, bool depositTake, uint256 takerIndex) external useRandomActor(takerIndex) {
        numberOfCalls['BLiquidationHandler.bucketTake']++;

        shouldExchangeRateChange = true;

        borrowerIndex = constrictToRange(borrowerIndex, 0, actors.length - 1);

        bucketIndex = constrictToRange(bucketIndex, LENDER_MIN_BUCKET_INDEX, LENDER_MAX_BUCKET_INDEX);

        address borrower = actors[borrowerIndex];
        address taker    = _actor;

        ( , , , uint256 kickTime, , , , , , ) = _pool.auctionInfo(borrower);

        if (kickTime == 0) {
            _kickAuction(borrowerIndex, 1e24, bucketIndex);
        }
        changePrank(taker);
        super.bucketTake(borrower, depositTake, bucketIndex);
    }

    function settleAuction(uint256 actorIndex, uint256 borrowerIndex, uint256 bucketIndex) external useRandomActor(actorIndex) {

        borrowerIndex = constrictToRange(borrowerIndex, 0, actors.length - 1);
        bucketIndex = constrictToRange(bucketIndex, LENDER_MIN_BUCKET_INDEX, LENDER_MAX_BUCKET_INDEX);
        address borrower = actors[borrowerIndex];
        uint256 maxDepth = LENDER_MAX_BUCKET_INDEX - LENDER_MIN_BUCKET_INDEX;

        address actor = _actor;
        
        ( , , , uint256 kickTime, , , , , , ) = _pool.auctionInfo(borrower);
        if (kickTime == 0) {
            _kickAuction(borrowerIndex, 1e24, bucketIndex);
        }
        changePrank(actor);

        // skip time to make auction clearable
        vm.warp(block.timestamp + 73 hours);
        super.settleAuction(borrower, maxDepth);
    }
}