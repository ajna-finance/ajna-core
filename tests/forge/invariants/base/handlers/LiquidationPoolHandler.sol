// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.18;

import { _isCollateralized } from 'src/libraries/helpers/PoolHelper.sol';

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
    ) external useTimestamps skipTime(skippedTime_) writeLogs {
        numberOfCalls['BLiquidationHandler.kickAuction']++;

        _kickAuction(
            borrowerIndex_,
            amount_,
            kickerIndex_
        );
    }

    function lenderKickAuction(
        uint256 kickerIndex_,
        uint256 bucketIndex_,
        uint256 skippedTime_
    ) external useRandomActor(kickerIndex_) useRandomLenderBucket(bucketIndex_) useTimestamps skipTime(skippedTime_) writeLogs {
        numberOfCalls['BLiquidationHandler.lenderKickAuction']++;

        _lenderKickAuction(_lenderBucketIndex);
    }

    function withdrawBonds(
        uint256 kickerIndex_,
        uint256 maxAmount_,
        uint256 skippedTime_
    ) external useRandomActor(kickerIndex_) useTimestamps skipTime(skippedTime_) writeLogs {
        numberOfCalls['BLiquidationHandler.withdrawBonds']++;

        _withdrawBonds(
            _actor,
            maxAmount_
        );
    }

    /****************************/
    /*** Taker Test Functions ***/
    /****************************/

    function takeAuction(
        uint256 borrowerIndex_,
        uint256 amount_,
        uint256 takerIndex_,
        uint256 skippedTime_
    ) external useRandomActor(takerIndex_) useTimestamps skipTime(skippedTime_) writeLogs {
        numberOfCalls['BLiquidationHandler.takeAuction']++;

        // try to take from head auction if any
        AuctionInfo memory auctionInfo = _getAuctionInfo(address(0));

        address borrower;
        if (auctionInfo.head != address(0)) {
            borrower = auctionInfo.head;

            BorrowerInfo memory borrowerInfo = _getBorrowerInfo(borrower);
            amount_ = borrowerInfo.collateral / 2;

            auctionInfo = _getAuctionInfo(borrower);
            // TODO: eliminate this unnecessary skip, perhaps advance by single block instead
            if (block.timestamp - auctionInfo.kickTime < 1 hours) {
                vm.warp(block.timestamp + 61 minutes);
            }
        } else {
            address taker = _actor;
            // no head auction, prepare take action
            (
                amount_,
                borrower
            ) = _preTake(amount_, borrowerIndex_, takerIndex_);

            _actor = taker;
            changePrank(taker);
        }

        _takeAuction(
            borrower,
            amount_,
            _actor
        );
    }

    function bucketTake(
        uint256 borrowerIndex_,
        uint256 bucketIndex_,
        bool depositTake_,
        uint256 takerIndex_,
        uint256 skippedTime_
    ) external useRandomActor(takerIndex_) useTimestamps skipTime(skippedTime_) writeLogs {
        numberOfCalls['BLiquidationHandler.bucketTake']++;

        bucketIndex_ = constrictToRange(
            bucketIndex_, LENDER_MIN_BUCKET_INDEX, LENDER_MAX_BUCKET_INDEX
        );

        // try to take from head auction if any
        AuctionInfo memory auctionInfo = _getAuctionInfo(address(0));

        address borrower;
        if (auctionInfo.head != address(0)) {
            borrower = auctionInfo.head;

            auctionInfo = _getAuctionInfo(borrower);
            // skip to make auction takeable
            if (block.timestamp - auctionInfo.kickTime < 1 hours) {
                vm.warp(block.timestamp + 61 minutes);
            }
        } else {
            address taker = _actor;
            // no head auction, prepare take action
            borrower = _preBucketTake(borrowerIndex_, takerIndex_);
            _actor = taker;
            changePrank(taker);
        }

        _bucketTake(
            _actor,
            borrower,
            depositTake_,
            bucketIndex_
        );
    }

    /******************************/
    /*** Settler Test Functions ***/
    /******************************/

    function settleAuction(
        uint256 actorIndex_,
        uint256 borrowerIndex_,
        uint256 kickerIndex_,
        uint256 skippedTime_
    ) external useRandomActor(actorIndex_) useTimestamps skipTime(skippedTime_) writeLogs {
        numberOfCalls['BLiquidationHandler.settleAuction']++;

        // try to settle head auction if any
        AuctionInfo memory auctionInfo = _getAuctionInfo(address(0));

        address borrower;
        if (auctionInfo.head != address(0)) {
            borrower = auctionInfo.head;
        } else {
            address settler = _actor;
            // no head auction, prepare take action
            borrower = _preSettleAuction(borrowerIndex_, kickerIndex_);
            _actor = settler;
            changePrank(settler);
        }

        _settleAuction(
            borrower,
            LENDER_MAX_BUCKET_INDEX - LENDER_MIN_BUCKET_INDEX
        );

    }

    /*******************************/
    /*** Prepare Tests Functions ***/
    /*******************************/

    function _preKick(uint256 borrowerIndex_, uint256 amount_) internal returns(address borrower_, bool borrowerKicked_) {
        amount_ = constrictToRange(
            amount_, MIN_QUOTE_AMOUNT, MAX_QUOTE_AMOUNT
        );
        borrowerIndex_ = constrictToRange(
            borrowerIndex_, 0, actors.length - 1
        );

        borrower_ = actors[borrowerIndex_];

        AuctionInfo memory auctionInfo = _getAuctionInfo(borrower_);
        borrowerKicked_ = auctionInfo.kickTime != 0;

        if (!borrowerKicked_) {
            // if borrower not kicked then check if it is undercollateralized / kickable
            BorrowerInfo memory borrowerInfo = _getBorrowerInfo(borrower_);

            if (_isBorrowerCollateralized(borrowerInfo)) {
                changePrank(borrower_);
                _actor = borrower_;
                uint256 drawDebtAmount = _preDrawDebt(amount_);
                _drawDebt(drawDebtAmount);

                // skip to make borrower undercollateralized
                borrowerInfo = _getBorrowerInfo(borrower_);
                if (borrowerInfo.debt != 0) vm.warp(block.timestamp + _getKickSkipTime());
            }
        }
    }

    function _preTake(uint256 amount_, uint256 borrowerIndex_, uint256 kickerIndex_) internal returns(uint256 boundedAmount_, address borrower_){
        boundedAmount_ = _constrictTakeAmount(amount_);

        borrower_ = _kickAuction(
            borrowerIndex_,
            boundedAmount_ * 100,
            kickerIndex_
        );

        // skip time to make auction takeable
        vm.warp(block.timestamp + 61 minutes);
    }

    function _preBucketTake(uint256 borrowerIndex_, uint256 kickerIndex_) internal returns(address borrower_) {
        borrower_ = _kickAuction(
            borrowerIndex_,
            1e24,
            kickerIndex_
        );

        // skip time to make auction takeable
        vm.warp(block.timestamp + 61 minutes);
    }

    function _preSettleAuction(uint256 borrowerIndex_, uint256 kickerIndex_) internal returns(address borrower_) {
        borrower_ = _kickAuction(
            borrowerIndex_,
            1e24,
            kickerIndex_
        );

        // skip time to make auction clearable
        vm.warp(block.timestamp + 73 hours);
    }

    /************************/
    /*** Helper Functions ***/
    /************************/

    function _kickAuction(
        uint256 borrowerIndex_,
        uint256 amount_,
        uint256 kickerIndex_
    ) internal useRandomActor(kickerIndex_) returns(address borrower_) {

        // Prepare test phase
        address kicker   = _actor;
        bool borrowerKicked;
        (
            borrower_,
            borrowerKicked
        )= _preKick(borrowerIndex_, amount_);

        // Action phase
        _actor = kicker;
        changePrank(kicker);
        if (!borrowerKicked) _kickAuction(borrower_);
    }

    function _constrictTakeAmount(uint256 amountToTake_) internal view virtual returns(uint256 boundedAmount_);
}