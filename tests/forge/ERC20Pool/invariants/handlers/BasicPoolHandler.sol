// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.14;

import { PoolInfoUtils, _collateralization } from 'src/PoolInfoUtils.sol';

import 'src/libraries/internal/Maths.sol';

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

        // Pre condition
        (uint256 lpBalanceBefore, ) = _pool.lenderInfo(bucketIndex_, _actor);

        if (lpBalanceBefore == 0) {
            amount_ = constrictToRange(amount_, 1, 1e30);
            _addQuoteToken(amount_, bucketIndex_);
        }

        // Action
        _removeQuoteToken(amount_, _lenderBucketIndex);
    }

    function moveQuoteToken(
        uint256 actorIndex_,
        uint256 amount_,
        uint256 fromIndex_,
        uint256 toIndex_
    ) public useRandomActor(actorIndex_) useTimestamps {
        numberOfCalls['BBasicHandler.moveQuoteToken']++;

        fromIndex_ = constrictToRange(
            fromIndex_,
            LENDER_MIN_BUCKET_INDEX,
            LENDER_MAX_BUCKET_INDEX
        );
        toIndex_ = constrictToRange(
            toIndex_,
            LENDER_MIN_BUCKET_INDEX,
            LENDER_MAX_BUCKET_INDEX
        );

        if (fromIndex_ == toIndex_) return;

        amount_ = constrictToRange(amount_, 1, 1e30);

        // ensure actor has LPs to move
        (uint256 lpBalance, ) = _pool.lenderInfo(fromIndex_, _actor);
        if (lpBalance == 0) _addQuoteToken(amount_, toIndex_);

        (uint256 lps, ) = _pool.lenderInfo(fromIndex_, _actor);
        // restrict amount to move by available deposit inside bucket
        uint256 availableDeposit = _poolInfo.lpsToQuoteTokens(address(_pool), lps, fromIndex_);
        amount_ = Maths.min(amount_, availableDeposit);

        _moveQuoteToken(amount_, fromIndex_, toIndex_);
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

        // Pre condition
        (uint256 lpBalanceBefore, ) = _pool.lenderInfo(bucketIndex_, _actor);
        if(lpBalanceBefore == 0) _addCollateral(amount_, bucketIndex_);

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

        // auction settle cleanup
        _auctionSettleStateReset(_actor);
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

        // Pre Condition
        // 1. borrower's debt should exceed minDebt
        // 2. pool needs sufficent quote token to draw debt
        // 3. drawDebt should not make borrower under collateralized

        // 1. borrower's debt should exceed minDebt
        (uint256 debt, uint256 collateral, ) = _poolInfo.borrowerInfo(address(_pool), _actor);
        (uint256 minDebt, , , ) = _poolInfo.poolUtilizationInfo(address(_pool));

        if (amountToBorrow_ < minDebt) amountToBorrow_ = minDebt + 1;

        // TODO: Need to constrain amount so LUP > HTP

        // 2. pool needs sufficent quote token to draw debt
        uint256 poolQuoteBalance = _quote.balanceOf(address(_pool));

        if (amountToBorrow_ > poolQuoteBalance) _addQuoteToken(amountToBorrow_ * 2, LENDER_MAX_BUCKET_INDEX);

        // 3. drawing of addition debt will make them under collateralized
        uint256 lup = _poolInfo.lup(address(_pool));
        (debt, collateral, ) = _poolInfo.borrowerInfo(address(_pool), _actor);

        if (_collateralization(debt, collateral, lup) < 1) {
            _repayDebt(debt);

            (debt, collateral, ) = _poolInfo.borrowerInfo(address(_pool), _actor);

            require(debt == 0, "borrower has debt");
        }
        
        // Action
        _drawDebt(amountToBorrow_);

        // auction settle cleanup
        _auctionSettleStateReset(_actor);
    }

    function repayDebt(
        uint256 actorIndex_,
        uint256 amountToRepay_
    ) public useRandomActor(actorIndex_) useTimestamps {
        numberOfCalls['BBasicHandler.repayDebt']++;

        amountToRepay_ = constrictToRange(amountToRepay_, _pool.quoteTokenDust(), 1e30);

        // Pre condition
        (uint256 debt, , ) = PoolInfoUtils(_poolInfo).borrowerInfo(address(_pool), _actor);
        if (debt == 0) _drawDebt(amountToRepay_);

        // Action
        _repayDebt(amountToRepay_);

        // auction settle cleanup
        _auctionSettleStateReset(_actor);
    }
}
