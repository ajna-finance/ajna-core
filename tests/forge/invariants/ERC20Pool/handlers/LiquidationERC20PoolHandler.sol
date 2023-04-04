// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.14;

import {
    LENDER_MIN_BUCKET_INDEX,
    LENDER_MAX_BUCKET_INDEX,
    MIN_AMOUNT,
    MAX_AMOUNT
}                                               from '../../base/handlers/unbounded/BaseHandler.sol';
import { LiquidationPoolHandler }               from '../../base/handlers/LiquidationPoolHandler.sol';
import { UnboundedLiquidationERC20PoolHandler } from './unbounded/UnboundedLiquidationERC20PoolHandler.sol';
import { BasicERC20PoolHandler }                from './BasicERC20PoolHandler.sol';

contract LiquidationERC20PoolHandler is UnboundedLiquidationERC20PoolHandler, LiquidationPoolHandler, BasicERC20PoolHandler {

    constructor(
        address pool_,
        address ajna_,
        address quote_,
        address collateral_,
        address poolInfo_,
        uint256 numOfActors_,
        address testContract_
    ) BasicERC20PoolHandler(pool_, ajna_, quote_, collateral_, poolInfo_, numOfActors_, testContract_) {

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

        amount_ = constrictToRange(amount_, MIN_AMOUNT, MAX_AMOUNT);

        borrowerIndex_ = constrictToRange(borrowerIndex_, 0, actors.length - 1);

        address borrower = actors[borrowerIndex_];
        address taker    = _actor;

        ( , , , uint256 kickTime, , , , , , ) = _pool.auctionInfo(borrower);

        if (kickTime == 0) _kickAuction(borrowerIndex_, amount_ * 100, actorIndex_);

        changePrank(taker);
        // skip time to make auction takeable
        vm.warp(block.timestamp + 2 hours);
        _takeAuction(borrower, amount_, taker);
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

}