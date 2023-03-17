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
 *  @dev this contract manages multiple actors
 *  @dev methods in this contract are called in random order
 *  @dev randomly selects an actor contract to make a txn
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
        uint256 amountToAdd_,
        uint256 bucketIndex_
    ) public useRandomActor(actorIndex_) useRandomLenderBucket(bucketIndex_) useTimestamps {
        numberOfCalls['BBasicHandler.addQuoteToken']++;

        // Prepare test phase
        uint256 boundedAmount = _preAddQuoteToken(amountToAdd_);

        // Action phase
        _addQuoteToken(boundedAmount, _lenderBucketIndex);
    }

    function removeQuoteToken(
        uint256 actorIndex_,
        uint256 amountToRemove_,
        uint256 bucketIndex_
    ) public useRandomActor(actorIndex_) useRandomLenderBucket(bucketIndex_) useTimestamps {
        numberOfCalls['BBasicHandler.removeQuoteToken']++;

        // Prepare test phase
        uint256 boundedAmount = _preRemoveQuoteToken(amountToRemove_);

        // Action phase
        _removeQuoteToken(boundedAmount, _lenderBucketIndex);
    }

    function moveQuoteToken(
        uint256 actorIndex_,
        uint256 amountToMove_,
        uint256 fromIndex_,
        uint256 toIndex_
    ) public useRandomActor(actorIndex_) useTimestamps {
        numberOfCalls['BBasicHandler.moveQuoteToken']++;

        // Prepare test phase
        (
            uint256 boundedFromIndex,
            uint256 boundedToIndex,
            uint256 boundedAmount
        ) = _preMoveQuoteToken(amountToMove_, fromIndex_, toIndex_);

        // Action phase
        _moveQuoteToken(boundedAmount, boundedFromIndex, boundedToIndex);
    }

    function addCollateral(
        uint256 actorIndex_,
        uint256 amountToAdd_,
        uint256 bucketIndex_
    ) public useRandomActor(actorIndex_) useRandomLenderBucket(bucketIndex_) useTimestamps {
        numberOfCalls['BBasicHandler.addCollateral']++;

        // Prepare test phase
        uint256 boundedAmount = _preAddCollateral(amountToAdd_);

        // Action phase
        _addCollateral(boundedAmount, _lenderBucketIndex);
    }

    function removeCollateral(
        uint256 actorIndex_,
        uint256 amountToRemove_,
        uint256 bucketIndex_
    ) public useRandomActor(actorIndex_) useRandomLenderBucket(bucketIndex_) useTimestamps {
        numberOfCalls['BBasicHandler.removeCollateral']++;

        // Prepare test phase
        uint256 boundedAmount = _preRemoveCollateral(amountToRemove_);

        // Action phase
        _removeCollateral(boundedAmount, _lenderBucketIndex);
    }

    function transferLps(
        uint256 fromActorIndex_,
        uint256 toActorIndex_,
        uint256 lpsToTransfer_,
        uint256 bucketIndex_
    ) public useRandomActor(fromActorIndex_) useRandomLenderBucket(bucketIndex_) useTimestamps {
        // Prepare test phase
        (address receiver, uint256 boundedLps) = _preTransferLps(toActorIndex_, lpsToTransfer_);

        // Action phase
        _increaseLPsAllowance(receiver, _lenderBucketIndex, boundedLps);
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

        // Prepare test phase
        uint256 boundedAmount = _prePledgeCollateral(amountToPledge_);

        // Action phase
        _pledgeCollateral(boundedAmount);

        // Cleanup phase
        _auctionSettleStateReset(_actor);
    }

    function pullCollateral(
        uint256 actorIndex_,
        uint256 amountToPull_
    ) public useRandomActor(actorIndex_) useTimestamps {
        numberOfCalls['BBasicHandler.pullCollateral']++;

        // Prepare test phase
        uint256 boundedAmount = _prePullCollateral(amountToPull_);

        // Action phase
        _pullCollateral(boundedAmount);
    } 

    function drawDebt(
        uint256 actorIndex_,
        uint256 amountToBorrow_
    ) public useRandomActor(actorIndex_) useTimestamps {
        numberOfCalls['BBasicHandler.drawDebt']++;

        // Prepare test phase
        uint256 boundedAmount = _preDrawDebt(amountToBorrow_);
        
        // Action phase
        _drawDebt(boundedAmount);

        // Cleanup phase
        _auctionSettleStateReset(_actor);
    }

    function repayDebt(
        uint256 actorIndex_,
        uint256 amountToRepay_
    ) public useRandomActor(actorIndex_) useTimestamps {
        numberOfCalls['BBasicHandler.repayDebt']++;

        // Prepare test phase
        uint256 boundedAmount = _preRepayDebt(amountToRepay_);

        // Action phase
        _repayDebt(boundedAmount);

        // Cleanup phase
        _auctionSettleStateReset(_actor);
    }

    /*******************************/
    /*** Prepare Tests Functions ***/
    /*******************************/

    function _preAddQuoteToken(
        uint256 amountToAdd_
    ) internal view returns (uint256 boundedAmount_) {
        boundedAmount_ = constrictToRange(amountToAdd_, _pool.quoteTokenDust(), 1e30);
    }

    function _preRemoveQuoteToken(
        uint256 amountToRemove_
    ) internal returns (uint256 boundedAmount_) {
        boundedAmount_ = constrictToRange(amountToRemove_, 1, 1e30);

        // ensure actor has quote tokens to remove
        (uint256 lpBalanceBefore, ) = _pool.lenderInfo(_lenderBucketIndex, _actor);
        if (lpBalanceBefore == 0) {
            _addQuoteToken(boundedAmount_, _lenderBucketIndex);
        }
    }

    function _preMoveQuoteToken(
        uint256 amountToMove_,
        uint256 fromIndex_,
        uint256 toIndex_
    ) internal returns (uint256 boundedFromIndex_, uint256 boundedToIndex_, uint256 boundedAmount_) {
        boundedFromIndex_ = constrictToRange(fromIndex_, LENDER_MIN_BUCKET_INDEX, LENDER_MAX_BUCKET_INDEX);
        boundedToIndex_   = constrictToRange(toIndex_,   LENDER_MIN_BUCKET_INDEX, LENDER_MAX_BUCKET_INDEX);
        boundedAmount_    = constrictToRange(amountToMove_, 1, 1e30);

        // ensure actor has LPs to move
        (uint256 lpBalance, ) = _pool.lenderInfo(boundedFromIndex_, _actor);
        if (lpBalance == 0) _addQuoteToken(boundedAmount_, boundedToIndex_);

        (uint256 lps, ) = _pool.lenderInfo(boundedFromIndex_, _actor);
        // restrict amount to move by available deposit inside bucket
        uint256 availableDeposit = _poolInfo.lpsToQuoteTokens(address(_pool), lps, boundedFromIndex_);
        boundedAmount_ = Maths.min(boundedAmount_, availableDeposit);
    }

    function _preAddCollateral(
        uint256 amountToAdd_
    ) internal pure returns (uint256 boundedAmount_) {
        boundedAmount_ = constrictToRange(amountToAdd_, 1e6, 1e30);
    }

    function _preRemoveCollateral(
        uint256 amountToRemove_
    ) internal returns (uint256 boundedAmount_) {
        boundedAmount_ = constrictToRange(amountToRemove_, 1, 1e30);

        // ensure actor has collateral to remove
        (uint256 lpBalanceBefore, ) = _pool.lenderInfo(_lenderBucketIndex, _actor);
        if(lpBalanceBefore == 0) _addCollateral(boundedAmount_, _lenderBucketIndex);
    }

    function _preTransferLps(
        uint256 toActorIndex_,
        uint256 lpsToTransfer_
    ) internal returns (address receiver_, uint256 boundedLps_) {
        // ensure actor has LPs to transfer
        (uint256 senderLpBalance, ) = _pool.lenderInfo(_lenderBucketIndex, _actor);
        if(senderLpBalance == 0) _addQuoteToken(1e24, _lenderBucketIndex);

        (senderLpBalance, ) = _pool.lenderInfo(_lenderBucketIndex, _actor);

        boundedLps_ = constrictToRange(lpsToTransfer_, 1, senderLpBalance);

        receiver_ = actors[constrictToRange(toActorIndex_, 0, actors.length - 1)];
    }

    function _prePledgeCollateral(
        uint256 amountToPledge_
    ) internal view returns (uint256 boundedAmount_) {
        boundedAmount_ =  constrictToRange(amountToPledge_, _pool.collateralScale(), 1e30);
    }

    function _prePullCollateral(
        uint256 amountToPull_
    ) internal pure returns (uint256 boundedAmount_) {
        boundedAmount_ = constrictToRange(amountToPull_, 1, 1e30);
    }

    function _preDrawDebt(
        uint256 amountToBorrow_
    ) internal returns (uint256 boundedAmount_) {
        boundedAmount_ = constrictToRange(amountToBorrow_, 1e6, 1e30);

        // Pre Condition
        // 1. borrower's debt should exceed minDebt
        // 2. pool needs sufficent quote token to draw debt
        // 3. drawDebt should not make borrower under collateralized

        // 1. borrower's debt should exceed minDebt
        (uint256 debt, uint256 collateral, ) = _poolInfo.borrowerInfo(address(_pool), _actor);
        (uint256 minDebt, , , ) = _poolInfo.poolUtilizationInfo(address(_pool));

        if (boundedAmount_ < minDebt) boundedAmount_ = minDebt + 1;

        // TODO: Need to constrain amount so LUP > HTP

        // 2. pool needs sufficent quote token to draw debt
        uint256 poolQuoteBalance = _quote.balanceOf(address(_pool));

        if (boundedAmount_ > poolQuoteBalance) {
            _addQuoteToken(boundedAmount_ * 2, LENDER_MAX_BUCKET_INDEX);
        }

        // 3. drawing of addition debt will make them under collateralized
        uint256 lup = _poolInfo.lup(address(_pool));
        (debt, collateral, ) = _poolInfo.borrowerInfo(address(_pool), _actor);

        if (_collateralization(debt, collateral, lup) < 1) {
            _repayDebt(debt);

            (debt, collateral, ) = _poolInfo.borrowerInfo(address(_pool), _actor);

            require(debt == 0, "borrower has debt");
        }
    }

    function _preRepayDebt(
        uint256 amountToRepay_
    ) internal returns (uint256 boundedAmount_) {
        boundedAmount_ = constrictToRange(amountToRepay_, _pool.quoteTokenDust(), 1e30);

        // ensure actor has debt to repay
        (uint256 debt, , ) = PoolInfoUtils(_poolInfo).borrowerInfo(address(_pool), _actor);
        if (debt == 0) {
            boundedAmount_ = _preDrawDebt(boundedAmount_);
            _drawDebt(boundedAmount_);
        }
    }
}
