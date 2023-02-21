
// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.14;

import '@std/Vm.sol';

import { BasicPoolHandler } from './BasicPoolHandler.sol';
import { LENDER_MIN_BUCKET_INDEX, LENDER_MAX_BUCKET_INDEX, BaseHandler } from './BaseHandler.sol';
import { Maths } from 'src/libraries/internal/Maths.sol';

abstract contract UnBoundedLiquidationPoolHandler is BaseHandler {
    function kickAuction(address borrower) internal resetAllPreviousLocalState {
        numberOfCalls['UBLiquidationHandler.kickAuction']++;

        (uint256 borrowerDebt, , ) = _poolInfo.borrowerInfo(address(_pool), borrower);
        (uint256 interestRate, )   = _pool.interestRateInfo();

        fenwickAccrueInterest();
        updatePreviousReserves();

        try _pool.kick(borrower) {
            shouldExchangeRateChange = true;
            shouldReserveChange      = true;
            updateCurrentReserves();

            // reserve increase by 3 months of interest of borrowerDebt
            loanKickIncreaseInReserve = Maths.wmul(borrowerDebt, Maths.wdiv(interestRate, 4 * 1e18));
        }
        catch {
            resetFenwickDepositUpdate();
        }
    }

    function takeAuction(address borrower, uint256 amount, address taker) internal resetAllPreviousLocalState {
        numberOfCalls['UBLiquidationHandler.takeAuction']++;

        (uint256 borrowerDebt, , ) = _poolInfo.borrowerInfo(address(_pool), borrower);
        (address kicker, , , , , , , , ) = _pool.auctionInfo(borrower);

        (uint256 claimableBond, uint256 lockedBond) = _pool.kickerInfo(kicker);

        uint256 totalBond = claimableBond + lockedBond;

        fenwickAccrueInterest();
        updatePreviousReserves();
        
        try _pool.take(borrower, amount, taker, bytes("")) {
            shouldExchangeRateChange = true;
            shouldReserveChange      = true;
            updateCurrentReserves();

            (claimableBond, lockedBond) = _pool.kickerInfo(kicker);
            if(totalBond > claimableBond + lockedBond) {
                kickerBondChange = totalBond - claimableBond - lockedBond;
                isKickerRewarded = true;
            }
            else {
                kickerBondChange = claimableBond + lockedBond - totalBond;
                isKickerRewarded = false;
            }
            
            if(!isFirstTakeOnAuction[borrower]) {
                // reserve increase by 7% of borrower debt on first take
                firstTakeIncreaseInReserve = Maths.wmul(borrowerDebt, 0.07 * 1e18);
                firstTake = true;
                isFirstTakeOnAuction[borrower] = true;
            }
            else {
                isFirstTakeOnAuction[borrower] = false;
                firstTake = false;
            }
        }
        catch {
            resetFenwickDepositUpdate();
        }
    }

    function bucketTake(address borrower, bool depositTake, uint256 bucketIndex) internal resetAllPreviousLocalState {
        numberOfCalls['UBLiquidationHandler.bucketTake']++;

        (uint256 borrowerDebt, , ) = _poolInfo.borrowerInfo(address(_pool), borrower);
        (address kicker, , , , , , , , ) = _pool.auctionInfo(borrower);

        (uint256 claimableBond, uint256 lockedBond) = _pool.kickerInfo(kicker);

        uint256 totalBond = claimableBond + lockedBond;

        fenwickAccrueInterest();
        updatePreviousReserves();

        try _pool.bucketTake(borrower, depositTake, bucketIndex) {
            shouldExchangeRateChange = true;
            shouldReserveChange      = true;
            updateCurrentReserves();
            
            if(!isFirstTakeOnAuction[borrower]) {
                // reserve increase by 7% of borrower debt on first take
                firstTakeIncreaseInReserve = Maths.wmul(borrowerDebt, 0.07 * 1e18);
                firstTake = true;
                isFirstTakeOnAuction[borrower] = true;
            }
            else {
                isFirstTakeOnAuction[borrower] = false;
                firstTake = false;
                (claimableBond, lockedBond) = _pool.kickerInfo(kicker);
                if(totalBond > claimableBond + lockedBond) {
                    kickerBondChange = totalBond - claimableBond - lockedBond;
                    isKickerRewarded = true;
                }
                else {
                    kickerBondChange = claimableBond + lockedBond - totalBond;
                    isKickerRewarded = false;
                }
            }
        }
        catch {
            resetFenwickDepositUpdate();
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
        amount           = constrictToRange(amount, 1, 1e36);

        ( , , , uint256 kickTime, , , , , ) = _pool.auctionInfo(borrower);

        if (kickTime == 0) {
            (uint256 debt, , ) = _pool.borrowerInfo(borrower);
            if (debt == 0) {
                changePrank(borrower);
                _actor = borrower;
                super.drawDebt(amount);
                
                // TODO: Check why adding this is increasing reverts many fold
                vm.warp(block.timestamp + 200 days);
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

    function takeAuction(uint256 borrowerIndex, uint256 amount, uint256 actorIndex) external useRandomActor(actorIndex){
        numberOfCalls['BLiquidationHandler.takeAuction']++;

        amount = constrictToRange(amount, 1, 1e36);

        shouldExchangeRateChange = true;

        borrowerIndex = constrictToRange(borrowerIndex, 0, actors.length - 1);

        address borrower = actors[borrowerIndex];
        address taker    = _actor;

        ( , , , uint256 kickTime, , , , , ) = _pool.auctionInfo(borrower);

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

        ( , , , uint256 kickTime, , , , , ) = _pool.auctionInfo(borrower);

        if (kickTime == 0) {
            _kickAuction(borrowerIndex, 1e24, bucketIndex);
        }
        changePrank(taker);
        super.bucketTake(borrower, depositTake, bucketIndex);
    } 
}