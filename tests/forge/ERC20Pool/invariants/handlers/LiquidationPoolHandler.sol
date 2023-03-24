// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.14;

import {
    LENDER_MIN_BUCKET_INDEX,
    LENDER_MAX_BUCKET_INDEX,
    BORROWER_MIN_BUCKET_INDEX,
    BaseHandler
}                                          from '../base/BaseHandler.sol';
import { UnboundedLiquidationPoolHandler } from '../base/UnboundedLiquidationPoolHandler.sol';

import { BasicPoolHandler } from './BasicPoolHandler.sol';

contract LiquidationPoolHandler is UnboundedLiquidationPoolHandler, BasicPoolHandler {

    constructor(
        address pool_,
        address ajna_,
        address quote_,
        address collateral_,
        address poolInfo_,
        uint256 numOfActors_,
        address testContract_
    ) BasicPoolHandler(pool_, ajna_, quote_, collateral_, poolInfo_, numOfActors_, testContract_) {

    }

    /*****************************/
    /*** Kicker Test Functions ***/
    /*****************************/

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
        _kickWithDeposit(_lenderBucketIndex);
    }

    function withdrawBonds(
        uint256 kickerIndex_,
        uint256 maxAmount_
    ) external useRandomActor(kickerIndex_) useTimestamps {
        _withdrawBonds(_actor, maxAmount_);
    }

    /****************************/
    /*** Taker Test Functions ***/
    /****************************/

    function takeAuction(
        uint256 borrowerIndex_,
        uint256 amount_,
        uint256 actorIndex_
    ) external useRandomActor(actorIndex_) useTimestamps {
        numberOfCalls['BLiquidationHandler.takeAuction']++;

        amount_ = constrictToRange(amount_, 1, 1e30);

        borrowerIndex_ = constrictToRange(borrowerIndex_, 0, actors.length - 1);

        address borrower = actors[borrowerIndex_];
        address taker    = _actor;

        ( , , , uint256 kickTime, , , , , , ) = _pool.auctionInfo(borrower);

        if (kickTime == 0) _kickAuction(borrowerIndex_, amount_ * 100, actorIndex_);

        changePrank(taker);
        _takeAuction(borrower, amount_, taker);
    }

    function bucketTake(
        uint256 borrowerIndex_,
        uint256 bucketIndex_,
        bool depositTake_,
        uint256 takerIndex_
    ) external useRandomActor(takerIndex_) useTimestamps {
        numberOfCalls['BLiquidationHandler.bucketTake']++;

        borrowerIndex_ = constrictToRange(borrowerIndex_, 0, actors.length - 1);
        bucketIndex_   = constrictToRange(bucketIndex_, LENDER_MIN_BUCKET_INDEX, LENDER_MAX_BUCKET_INDEX);

        address borrower = actors[borrowerIndex_];
        address taker    = _actor;

        ( , , , uint256 kickTime, , , , , , ) = _pool.auctionInfo(borrower);

        if (kickTime == 0) _kickAuction(borrowerIndex_, 1e24, bucketIndex_);

        changePrank(taker);
        _bucketTake(taker, borrower, depositTake_, bucketIndex_);
    }

    /******************************/
    /*** Settler Test Functions ***/
    /******************************/

    function settleAuction(
        uint256 actorIndex_,
        uint256 borrowerIndex_,
        uint256 bucketIndex_
    ) external useRandomActor(actorIndex_) useTimestamps {
        borrowerIndex_ = constrictToRange(borrowerIndex_, 0, actors.length - 1);
        bucketIndex_   = constrictToRange(bucketIndex_, LENDER_MIN_BUCKET_INDEX, LENDER_MAX_BUCKET_INDEX);

        address borrower = actors[borrowerIndex_];
        uint256 maxDepth = LENDER_MAX_BUCKET_INDEX - LENDER_MIN_BUCKET_INDEX;

        address actor = _actor;

        ( , , , uint256 kickTime, , , , , , ) = _pool.auctionInfo(borrower);

        if (kickTime == 0) _kickAuction(borrowerIndex_, 1e24, bucketIndex_);

        changePrank(actor);
        // skip time to make auction clearable
        vm.warp(block.timestamp + 73 hours);
        _settleAuction(borrower, maxDepth);

        _auctionSettleStateReset(borrower);
    }

    /************************/
    /*** Helper Functions ***/
    /************************/

    function _kickAuction(
        uint256 borrowerIndex_,
        uint256 amount_,
        uint256 kickerIndex_
    ) internal useTimestamps useRandomActor(kickerIndex_) {
        numberOfCalls['BLiquidationHandler.kickAuction']++;

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
                uint256 drawDebtAmount = _preDrawDebt(amount_);
                _drawDebt(drawDebtAmount);
            }

            changePrank(kicker);
            _actor = kicker;
            _kickAuction(borrower);
        }

        // skip some time for more interest
        vm.warp(block.timestamp + 2 hours);
    }
}