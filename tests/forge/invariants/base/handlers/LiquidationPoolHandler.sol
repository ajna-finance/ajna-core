// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.14;

import { UnboundedLiquidationPoolHandler } from './unbounded/UnboundedLiquidationPoolHandler.sol';
import { BasicPoolHandler }                from './BasicPoolHandler.sol';

abstract contract LiquidationPoolHandler is UnboundedLiquidationPoolHandler, BasicPoolHandler {

    /*****************************/
    /*** Kicker Test Functions ***/
    /*****************************/

    function kickAuction(
        uint256 borrowerIndex_,
        uint256 amount_,
        uint256 kickerIndex_,
        uint256 skippedTime_
    ) external useTimestamps skipTime(skippedTime_) {
        _kickAuction(borrowerIndex_, amount_, kickerIndex_);
    }

    function kickWithDeposit(
        uint256 kickerIndex_,
        uint256 bucketIndex_,
        uint256 skippedTime_
    ) external useRandomActor(kickerIndex_) useRandomLenderBucket(bucketIndex_) useTimestamps skipTime(skippedTime_) {
        _kickWithDeposit(_lenderBucketIndex);
    }

    function withdrawBonds(
        uint256 kickerIndex_,
        uint256 maxAmount_,
        uint256 skippedTime_
    ) external useRandomActor(kickerIndex_) useTimestamps skipTime(skippedTime_) {
        _withdrawBonds(_actor, maxAmount_);
    }

    /****************************/
    /*** Taker Test Functions ***/
    /****************************/

    function takeAuction(
        uint256 borrowerIndex_,
        uint256 amount_,
        uint256 takerIndex_,
        uint256 skippedTime_
    ) external useRandomActor(takerIndex_) useTimestamps skipTime(skippedTime_) {
        numberOfCalls['BLiquidationHandler.takeAuction']++;

        // Prepare test phase
        address borrower;
        address taker       = _actor;
        (amount_, borrower) = _preTake(amount_, borrowerIndex_, takerIndex_);

        // Action phase
        changePrank(taker);
        // skip time to make auction takeable
        vm.warp(block.timestamp + 2 hours);
        _takeAuction(borrower, amount_, taker);
    }

    function bucketTake(
        uint256 borrowerIndex_,
        uint256 bucketIndex_,
        bool depositTake_,
        uint256 takerIndex_,
        uint256 skippedTime_
    ) external useRandomActor(takerIndex_) useTimestamps skipTime(skippedTime_) {
        numberOfCalls['BLiquidationHandler.bucketTake']++;

        // Prepare test phase
        address taker                           = _actor;
        (address borrower, uint256 bucketIndex) = _preBucketTake(borrowerIndex_, takerIndex_, bucketIndex_);

        changePrank(taker);
        // skip time to make auction takeable
        vm.warp(block.timestamp + 2 hours);
        _bucketTake(taker, borrower, depositTake_, bucketIndex);
    }

    /******************************/
    /*** Settler Test Functions ***/
    /******************************/

    function settleAuction(
        uint256 actorIndex_,
        uint256 borrowerIndex_,
        uint256 kickerIndex_,
        uint256 skippedTime_
    ) external useRandomActor(actorIndex_) useTimestamps skipTime(skippedTime_) {

        // prepare phase
        address actor                        = _actor;
        (address borrower, uint256 maxDepth) = _preSettleAuction(borrowerIndex_, kickerIndex_);

        // Action phase
        changePrank(actor);
        // skip time to make auction clearable
        vm.warp(block.timestamp + 73 hours);
        _settleAuction(borrower, maxDepth);

        // Cleanup phase
        _auctionSettleStateReset(borrower);
    }

    /*******************************/
    /*** Prepare Tests Functions ***/
    /*******************************/

    function _preKick(uint256 borrowerIndex_, uint256 amount_) internal returns(address borrower_, bool borrowerKicked_) {
        borrowerIndex_ = constrictToRange(borrowerIndex_, 0, actors.length - 1);
        borrower_      = actors[borrowerIndex_];
        amount_        = constrictToRange(amount_, MIN_QUOTE_AMOUNT, MAX_QUOTE_AMOUNT);

        ( , , , uint256 kickTime, , , , , , ) = _pool.auctionInfo(borrower_);

        borrowerKicked_ = kickTime != 0;

        if (!borrowerKicked_) {
            (uint256 debt, , ) = _pool.borrowerInfo(borrower_);

            if (debt == 0) {
                changePrank(borrower_);
                _actor = borrower_;
                uint256 drawDebtAmount = _preDrawDebt(amount_);
                _drawDebt(drawDebtAmount);

                // skip to make borrower undercollateralized
                vm.warp(block.timestamp + 200 days);
            }
        }
    }

    function _preTake(uint256 amount_, uint256 borrowerIndex_, uint256 kickerIndex_) internal returns(uint256 boundedAmount_, address borrower_){
        boundedAmount_ = _constrictTakeAmount(amount_);
        borrower_      = _kickAuction(borrowerIndex_, boundedAmount_ * 100, kickerIndex_);
    }

    function _preBucketTake(uint256 borrowerIndex_, uint256 kickerIndex_, uint256 bucketIndex_) internal returns(address borrower_, uint256 bucket_) {
        bucket_   = constrictToRange(bucketIndex_, LENDER_MIN_BUCKET_INDEX, LENDER_MAX_BUCKET_INDEX);
        borrower_ = _kickAuction(borrowerIndex_, 1e24, kickerIndex_);
    }

    function _preSettleAuction(uint256 borrowerIndex_, uint256 kickerIndex_) internal returns(address borrower_, uint256 maxDepth_) {
        maxDepth_ = LENDER_MAX_BUCKET_INDEX - LENDER_MIN_BUCKET_INDEX;
        borrower_ = _kickAuction(borrowerIndex_, 1e24, kickerIndex_);
    }

    /************************/
    /*** Helper Functions ***/
    /************************/

    function _kickAuction(
        uint256 borrowerIndex_,
        uint256 amount_,
        uint256 kickerIndex_
    ) internal useRandomActor(kickerIndex_) returns(address borrower_) {
        numberOfCalls['BLiquidationHandler.kickAuction']++;

        // Prepare test phase
        address kicker   = _actor;
        bool borrowerKicked;
        (borrower_, borrowerKicked)= _preKick(borrowerIndex_, amount_);

        // Action phase
        _actor = kicker;
        if (!borrowerKicked) _kickAuction(borrower_);
    }

    function _constrictTakeAmount(uint256 amountToTake_) internal view virtual returns(uint256 boundedAmount_);
}