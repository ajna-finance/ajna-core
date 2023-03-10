// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.14;

import {
    LENDER_MIN_BUCKET_INDEX,
    LENDER_MAX_BUCKET_INDEX,
    BORROWER_MIN_BUCKET_INDEX,
    BaseHandler
}                                    from '../base/BaseHandler.sol';
import { UnboundedBasicPoolHandler } from '../base/UnboundedBasicPoolHandler.sol';

/**
 *  @dev this contract manages multiple lenders
 *  @dev methods in this contract are called in random order
 *  @dev randomly selects a lender contract to make a txn
 */ 
contract BasicPoolHandler is UnboundedBasicPoolHandler {

    constructor(
        address pool_,
        address quote_,
        address collateral_,
        address poolInfo_,
        uint256 numOfActors_,
        address testContract_
    ) BaseHandler(pool_, quote_, collateral_, poolInfo_, numOfActors_, testContract_) {

    }

    /*****************************/
    /*** Lender Test Functions ***/
    /*****************************/

    function addQuoteToken(
        uint256 actorIndex_,
        uint256 amount_,
        uint256 bucketIndex_
    ) public useRandomActor(actorIndex_) useRandomLenderBucket(bucketIndex_) useTimestamps {
        numberOfCalls['BBasicHandler.addQuoteToken']++;

        amount_ = constrictToRange(amount_, _pool.quoteTokenDust(), 1e30);

        // Action
        _addQuoteToken(amount_, _lenderBucketIndex);
    }

    function removeQuoteToken(
        uint256 actorIndex_,
        uint256 amount_,
        uint256 bucketIndex_
    ) public useRandomActor(actorIndex_) useRandomLenderBucket(bucketIndex_) useTimestamps {
        numberOfCalls['BBasicHandler.removeQuoteToken']++;

        uint256 poolBalance = _quote.balanceOf(address(_pool));

        if (poolBalance < amount_) return; // (not enough quote token to withdraw / quote tokens are borrowed)

        // Action
        _removeQuoteToken(amount_, _lenderBucketIndex);
    }

    function moveQuoteToken(
        uint256 actorIndex_,
        uint256 amount_,
        uint256 fromBucketIndex_,
        uint256 toBucketIndex_
    ) public useRandomActor(actorIndex_) useTimestamps {
        numberOfCalls['BBasicHandler.moveQuoteToken']++;

        fromBucketIndex_ = constrictToRange(
            fromBucketIndex_,
            LENDER_MIN_BUCKET_INDEX,
            LENDER_MAX_BUCKET_INDEX
        );
        toBucketIndex_ = constrictToRange(
            toBucketIndex_,
            LENDER_MIN_BUCKET_INDEX,
            LENDER_MAX_BUCKET_INDEX
        );

        amount_ = constrictToRange(amount_, 1, 1e30);
        
        _moveQuoteToken(amount_, fromBucketIndex_, toBucketIndex_);
    }

    function addCollateral(
        uint256 actorIndex_,
        uint256 amount_,
        uint256 bucketIndex_
    ) public useRandomActor(actorIndex_) useRandomLenderBucket(bucketIndex_) useTimestamps {
        numberOfCalls['BBasicHandler.addCollateral']++;

        amount_ = constrictToRange(amount_, 1e6, 1e30);

        // Action
        _addCollateral(amount_, _lenderBucketIndex);
    }

    function removeCollateral(
        uint256 actorIndex_,
        uint256 amount_,
        uint256 bucketIndex_
    ) public useRandomActor(actorIndex_) useRandomLenderBucket(bucketIndex_) useTimestamps {
        numberOfCalls['BBasicHandler.removeCollateral']++;

        (uint256 lpBalance, ) = _pool.lenderInfo(_lenderBucketIndex, _actor);

        ( , uint256 bucketCollateral, , , ) = _pool.bucketInfo(_lenderBucketIndex);

        if (lpBalance == 0 || bucketCollateral == 0) return; // no value in bucket

        amount_ = constrictToRange(amount_, 1, 1e30);

        // Action
        _removeCollateral(amount_, _lenderBucketIndex);
    }

    function transferLps(
        uint256 fromActorIndex_,
        uint256 toActorIndex_,
        uint256 lpsToTransfer_,
        uint256 bucketIndex_
    ) public useRandomActor(fromActorIndex_) useRandomLenderBucket(bucketIndex_) useTimestamps {
        (uint256 senderLpBalance, ) = _pool.lenderInfo(_lenderBucketIndex, _actor);

        address receiver = actors[constrictToRange(toActorIndex_, 0, actors.length - 1)];

        if(senderLpBalance == 0) _addQuoteToken(1e24, _lenderBucketIndex);

        (senderLpBalance, ) = _pool.lenderInfo(_lenderBucketIndex, _actor);

        lpsToTransfer_ = constrictToRange(lpsToTransfer_, 1, senderLpBalance);

        _increaseLPsAllowance(receiver, _lenderBucketIndex, lpsToTransfer_);
        _transferLps(_actor, receiver, _lenderBucketIndex);
    }

    /*******************************/
    /*** Borrower Test Functions ***/
    /*******************************/

    function pledgeCollateral(
        uint256 actorIndex_,
        uint256 amountToPledge_
    ) public useRandomActor(actorIndex_) useTimestamps {
        numberOfCalls['BBasicHandler.pledgeCollateral']++;

        uint256 collateralScale = _pool.collateralScale();

        amountToPledge_ = constrictToRange(amountToPledge_, collateralScale, 1e30);

        // Action
        _pledgeCollateral(amountToPledge_);
    }

    function pullCollateral(
        uint256 actorIndex_,
        uint256 amountToPull_
    ) public useRandomActor(actorIndex_) useTimestamps {
        numberOfCalls['BBasicHandler.pullCollateral']++;

        amountToPull_ = constrictToRange(amountToPull_, 1, 1e30);

        // Action
        _pullCollateral(amountToPull_);
    } 

    function drawDebt(
        uint256 actorIndex_,
        uint256 amountToBorrow_
    ) public useRandomActor(actorIndex_) useTimestamps {
        numberOfCalls['BBasicHandler.drawDebt']++;

        amountToBorrow_ = constrictToRange(amountToBorrow_, 1e6, 1e30);
        
        // Action
        _drawDebt(amountToBorrow_);
    }

    function repayDebt(
        uint256 actorIndex_,
        uint256 amountToRepay_
    ) public useRandomActor(actorIndex_) useTimestamps {
        numberOfCalls['BBasicHandler.repayDebt']++;

        amountToRepay_ = constrictToRange(amountToRepay_, _pool.quoteTokenDust(), 1e30);

        // Action
        _repayDebt(amountToRepay_);
    }
}
