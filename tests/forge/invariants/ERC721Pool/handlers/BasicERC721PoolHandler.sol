// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.14;

import { PoolInfoUtils, _collateralization } from 'src/PoolInfoUtils.sol';
import { Maths }                             from 'src/libraries/internal/Maths.sol';

import { BORROWER_MIN_BUCKET_INDEX }       from '../../base/handlers/unbounded/BaseHandler.sol';
import { BasicPoolHandler }                from '../../base/handlers/BasicPoolHandler.sol';
import { UnboundedBasicPoolHandler }       from '../../base/handlers/unbounded/UnboundedBasicPoolHandler.sol';
import { UnboundedBasicERC721PoolHandler } from './unbounded/UnboundedBasicERC721PoolHandler.sol';
import { BaseERC721PoolHandler }           from './unbounded/BaseERC721PoolHandler.sol';

/**
 *  @dev this contract manages multiple actors
 *  @dev methods in this contract are called in random order
 *  @dev randomly selects an actor contract to make a txn
 */ 
contract BasicERC721PoolHandler is UnboundedBasicERC721PoolHandler, BasicPoolHandler {

    constructor(
        address pool_,
        address ajna_,
        address quote_,
        address collateral_,
        address poolInfo_,
        uint256 numOfActors_,
        address testContract_
    ) BaseERC721PoolHandler(pool_, ajna_, quote_, collateral_, poolInfo_, numOfActors_, testContract_) {

    }

    /*****************************/
    /*** Lender Test Functions ***/
    /*****************************/

    function addCollateral(
        uint256 actorIndex_,
        uint256 amountToAdd_,
        uint256 bucketIndex_,
        uint256 skippedTime_
    ) external useRandomActor(actorIndex_) useRandomLenderBucket(bucketIndex_) useTimestamps skipTime(skippedTime_) {
        numberOfCalls['BBasicHandler.addCollateral']++;

        // Prepare test phase
        uint256 boundedAmount = _preAddCollateral(amountToAdd_);

        // Action phase
        _addCollateral(boundedAmount, _lenderBucketIndex);
    }

    function removeCollateral(
        uint256 actorIndex_,
        uint256 amountToRemove_,
        uint256 bucketIndex_,
        uint256 skippedTime_
    ) external useRandomActor(actorIndex_) useRandomLenderBucket(bucketIndex_) useTimestamps skipTime(skippedTime_) {
        numberOfCalls['BBasicHandler.removeCollateral']++;

        // Prepare test phase
        uint256 boundedAmount = _preRemoveCollateral(amountToRemove_);

        // Action phase
        _removeCollateral(boundedAmount, _lenderBucketIndex);
    }

    /*******************************/
    /*** Borrower Test Functions ***/
    /*******************************/

    function pledgeCollateral(
        uint256 actorIndex_,
        uint256 amountToPledge_,
        uint256 skippedTime_
    ) external useRandomActor(actorIndex_) useTimestamps skipTime(skippedTime_) {
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
        uint256 amountToPull_,
        uint256 skippedTime_
    ) external useRandomActor(actorIndex_) useTimestamps skipTime(skippedTime_) {
        numberOfCalls['BBasicHandler.pullCollateral']++;

        // Prepare test phase
        uint256 boundedAmount = _prePullCollateral(amountToPull_);

        // Action phase
        _pullCollateral(boundedAmount);
    }

    function drawDebt(
        uint256 actorIndex_,
        uint256 amountToBorrow_,
        uint256 skippedTime_
    ) external useRandomActor(actorIndex_) useTimestamps skipTime(skippedTime_) {
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
        uint256 amountToRepay_,
        uint256 skippedTime_
    ) external useRandomActor(actorIndex_) useTimestamps skipTime(skippedTime_) {
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

    function _preAddCollateral(
        uint256 amountToAdd_
    ) internal view returns (uint256 boundedAmount_) {
        boundedAmount_ = constrictToRange(amountToAdd_, MIN_COLLATERAL_AMOUNT, MAX_COLLATERAL_AMOUNT);
    }

    function _preRemoveCollateral(
        uint256 amountToRemove_
    ) internal returns (uint256 boundedAmount_) {
        boundedAmount_ = constrictToRange(amountToRemove_, MIN_COLLATERAL_AMOUNT, MAX_COLLATERAL_AMOUNT);

        // ensure actor has collateral to remove
        (uint256 lpBalanceBefore, ) = _pool.lenderInfo(_lenderBucketIndex, _actor);
        if (lpBalanceBefore == 0) _addCollateral(boundedAmount_, _lenderBucketIndex);
    }

    function _prePledgeCollateral(
        uint256 amountToPledge_
    ) internal view returns (uint256 boundedAmount_) {
        boundedAmount_ =  constrictToRange(amountToPledge_, MIN_COLLATERAL_AMOUNT, MAX_COLLATERAL_AMOUNT);
    }

    function _prePullCollateral(
        uint256 amountToPull_
    ) internal view returns (uint256 boundedAmount_) {
        boundedAmount_ = constrictToRange(amountToPull_, 0, MAX_COLLATERAL_AMOUNT);
    }

    function _preDrawDebt(
        uint256 amountToBorrow_
    ) internal override returns (uint256 boundedAmount_) {
        boundedAmount_ = constrictToRange(amountToBorrow_, MIN_QUOTE_AMOUNT, MAX_QUOTE_AMOUNT);

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
        boundedAmount_ = constrictToRange(amountToRepay_, Maths.max(_pool.quoteTokenDust(), MIN_QUOTE_AMOUNT), MAX_QUOTE_AMOUNT);

        // ensure actor has debt to repay
        (uint256 debt, , ) = PoolInfoUtils(_poolInfo).borrowerInfo(address(_pool), _actor);
        if (debt == 0) {
            boundedAmount_ = _preDrawDebt(boundedAmount_);
            _drawDebt(boundedAmount_);
        }
    }
}
