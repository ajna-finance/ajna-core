// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.14;

import { Maths } from 'src/libraries/internal/Maths.sol';

import { UnboundedBasicPoolHandler } from './unbounded/UnboundedBasicPoolHandler.sol';

/**
 *  @dev this contract manages multiple actors
 *  @dev methods in this contract are called in random order
 *  @dev randomly selects an actor contract to make a txn
 */ 
abstract contract BasicPoolHandler is UnboundedBasicPoolHandler {

    /*****************************/
    /*** Lender Test Functions ***/
    /*****************************/

    function addQuoteToken(
        uint256 actorIndex_,
        uint256 amountToAdd_,
        uint256 bucketIndex_,
        uint256 skippedTime_
    ) external useRandomActor(actorIndex_) useRandomLenderBucket(bucketIndex_) useTimestamps skipTime(skippedTime_) {
        numberOfCalls['BBasicHandler.addQuoteToken']++;

        // Prepare test phase
        uint256 boundedAmount = _preAddQuoteToken(amountToAdd_);

        // Action phase
        _addQuoteToken(boundedAmount, _lenderBucketIndex);
    }

    function removeQuoteToken(
        uint256 actorIndex_,
        uint256 amountToRemove_,
        uint256 bucketIndex_,
        uint256 skippedTime_
    ) external useRandomActor(actorIndex_) useRandomLenderBucket(bucketIndex_) useTimestamps skipTime(skippedTime_) {
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
        uint256 toIndex_,
        uint256 skippedTime_
    ) external useRandomActor(actorIndex_) useTimestamps skipTime(skippedTime_) {
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

    function transferLps(
        uint256 fromActorIndex_,
        uint256 toActorIndex_,
        uint256 lpsToTransfer_,
        uint256 bucketIndex_,
        uint256 skippedTime_
    ) external useRandomActor(fromActorIndex_) useRandomLenderBucket(bucketIndex_) useTimestamps skipTime(skippedTime_) {
        // Prepare test phase
        (address receiver, uint256 boundedLps) = _preTransferLps(toActorIndex_, lpsToTransfer_);

        // Action phase
        _increaseLPAllowance(receiver, _lenderBucketIndex, boundedLps);
        _transferLps(_actor, receiver, _lenderBucketIndex);
    }

    /*******************************/
    /*** Prepare Tests Functions ***/
    /*******************************/

    function _preAddQuoteToken(
        uint256 amountToAdd_
    ) internal view returns (uint256 boundedAmount_) {
        boundedAmount_ = constrictToRange(amountToAdd_, Maths.max(_pool.quoteTokenDust(), MIN_QUOTE_AMOUNT), MAX_QUOTE_AMOUNT);
    }

    function _preRemoveQuoteToken(
        uint256 amountToRemove_
    ) internal returns (uint256 boundedAmount_) {
        boundedAmount_ = constrictToRange(amountToRemove_, MIN_QUOTE_AMOUNT, MAX_QUOTE_AMOUNT);

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
        boundedAmount_    = constrictToRange(amountToMove_, MIN_QUOTE_AMOUNT, MAX_QUOTE_AMOUNT);

        // ensure actor has LP to move
        (uint256 lpBalance, ) = _pool.lenderInfo(boundedFromIndex_, _actor);
        if (lpBalance == 0) _addQuoteToken(boundedAmount_, boundedToIndex_);

        (uint256 lps, ) = _pool.lenderInfo(boundedFromIndex_, _actor);
        // restrict amount to move by available deposit inside bucket
        uint256 availableDeposit = _poolInfo.lpToQuoteTokens(address(_pool), lps, boundedFromIndex_);
        boundedAmount_ = Maths.min(boundedAmount_, availableDeposit);
    }

    function _preTransferLps(
        uint256 toActorIndex_,
        uint256 lpsToTransfer_
    ) internal returns (address receiver_, uint256 boundedLps_) {
        // ensure actor has LP to transfer
        (uint256 senderLpBalance, ) = _pool.lenderInfo(_lenderBucketIndex, _actor);
        if (senderLpBalance == 0) _addQuoteToken(1e24, _lenderBucketIndex);

        (senderLpBalance, ) = _pool.lenderInfo(_lenderBucketIndex, _actor);

        boundedLps_ = constrictToRange(lpsToTransfer_, 0, senderLpBalance);

        receiver_ = actors[constrictToRange(toActorIndex_, 0, actors.length - 1)];
    }

    function _preDrawDebt(
        uint256 amountToBorrow_
    ) internal virtual returns (uint256 boundedAmount_);
}
