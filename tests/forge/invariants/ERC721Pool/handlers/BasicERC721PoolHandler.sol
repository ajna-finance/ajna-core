// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.18;

import { PoolInfoUtils }               from 'src/PoolInfoUtils.sol';
import { Maths }                       from 'src/libraries/internal/Maths.sol';
import { _priceAt, _isCollateralized } from 'src/libraries/helpers/PoolHelper.sol';

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
        address poolInfo_,
        uint256 numOfActors_,
        address testContract_
    ) BaseERC721PoolHandler(pool_, ajna_, poolInfo_, numOfActors_, testContract_) {

    }

    /*****************************/
    /*** Lender Test Functions ***/
    /*****************************/

    function addCollateral(
        uint256 actorIndex_,
        uint256 amountToAdd_,
        uint256 bucketIndex_,
        uint256 skippedTime_
    ) external useRandomActor(actorIndex_) useRandomLenderBucket(bucketIndex_) useTimestamps skipTime(skippedTime_) writeLogs {
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
    ) external useRandomActor(actorIndex_) useRandomLenderBucket(bucketIndex_) useTimestamps skipTime(skippedTime_) writeLogs {
        numberOfCalls['BBasicHandler.removeCollateral']++;

        // Prepare test phase
        uint256 boundedAmount = _preRemoveCollateral(amountToRemove_);

        // Action phase
        _removeCollateral(boundedAmount, _lenderBucketIndex);
    }
    
    function mergeCollateral(
        uint256 actorIndex_,
        uint256 skippedTime_
    ) external useRandomActor(actorIndex_) useTimestamps skipTime(skippedTime_) writeLogs {
        numberOfCalls['BBasicHandler.mergeCollateral']++;

        // Prepare test phase
        (uint256 NFTAmount, uint256[] memory bucketIndexes) = _preMergeCollateral();

        // Action phase
        _mergeCollateral(NFTAmount, bucketIndexes);
    }

    /*******************************/
    /*** Borrower Test Functions ***/
    /*******************************/

    function pledgeCollateral(
        uint256 actorIndex_,
        uint256 amountToPledge_,
        uint256 skippedTime_
    ) external useRandomActor(actorIndex_) useTimestamps skipTime(skippedTime_) writeLogs {
        numberOfCalls['BBasicHandler.pledgeCollateral']++;

        //  borrower cannot make any action when in auction
        (uint256 kickTime,,,,,) = _poolInfo.auctionStatus(address(_pool), _actor);
        if (kickTime != 0) return;

        // Prepare test phase
        uint256 boundedAmount = _prePledgeCollateral(amountToPledge_);

        // Action phase
        _pledgeCollateral(boundedAmount);
    }

    function pullCollateral(
        uint256 actorIndex_,
        uint256 amountToPull_,
        uint256 skippedTime_
    ) external useRandomActor(actorIndex_) useTimestamps skipTime(skippedTime_) writeLogs {
        numberOfCalls['BBasicHandler.pullCollateral']++;

        //  borrower cannot make any action when in auction
        (uint256 kickTime,,,,,) = _poolInfo.auctionStatus(address(_pool), _actor);
        if (kickTime != 0) return;

        // Prepare test phase
        uint256 boundedAmount = _prePullCollateral(amountToPull_);

        // Action phase
        _pullCollateral(boundedAmount);
    }

    function drawDebt(
        uint256 actorIndex_,
        uint256 amountToBorrow_,
        uint256 skippedTime_
    ) external useRandomActor(actorIndex_) useTimestamps skipTime(skippedTime_) writeLogs {
        numberOfCalls['BBasicHandler.drawDebt']++;

        //  borrower cannot make any action when in auction
        (uint256 kickTime,,,,,) = _poolInfo.auctionStatus(address(_pool), _actor);
        if (kickTime != 0) return;

        // Prepare test phase
        uint256 boundedAmount = _preDrawDebt(amountToBorrow_);
        
        // Action phase
        _drawDebt(boundedAmount);
    }

    function repayDebt(
        uint256 actorIndex_,
        uint256 amountToRepay_,
        uint256 skippedTime_
    ) external useRandomActor(actorIndex_) useTimestamps skipTime(skippedTime_) writeLogs {
        numberOfCalls['BBasicHandler.repayDebt']++;

        //  borrower cannot make any action when in auction
        (uint256 kickTime,,,,,) = _poolInfo.auctionStatus(address(_pool), _actor);
        if (kickTime != 0) return;

        // Prepare test phase
        uint256 boundedAmount = _preRepayDebt(amountToRepay_);

        // Action phase
        _repayDebt(boundedAmount);
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

    function _preMergeCollateral() internal returns(uint256 NFTAmount_, uint256[] memory bucketIndexes_) {
        bucketIndexes_ = getBuckets();
        
        for (uint256 i = 0; i < bucketIndexes_.length; i++) {
            uint256 bucketIndex = bucketIndexes_[i];

            // Add Quote token in each bucket such that user has enough lps in each bucket to merge collateral
            uint256 price = _poolInfo.indexToPrice(bucketIndex);
            _addQuoteToken(price, bucketIndex);

            (uint256 lenderLps, )    = _erc721Pool.lenderInfo(bucketIndex, _actor);
            uint256 collateralAmount =_poolInfo.lpToCollateral(address(_erc721Pool), lenderLps, bucketIndex);
            NFTAmount_               += collateralAmount;
        }

        // Round collateral amount
        NFTAmount_ = NFTAmount_ / 1e18;
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
        boundedAmount_ = constrictToRange(amountToBorrow_, MIN_DEBT_AMOUNT, MAX_DEBT_AMOUNT);

        //  borrower cannot make any action when in auction
        (uint256 kickTime, uint256 collateral, uint256 debt,,,) = _poolInfo.auctionStatus(address(_pool), _actor);
        if (kickTime != 0) return boundedAmount_;

        // Pre Condition
        // 1. borrower's debt should exceed minDebt
        // 2. pool needs sufficent quote token to draw debt
        // 3. drawDebt should not make borrower under collateralized

        // 1. borrower's debt should exceed minDebt
        (debt, collateral, ) = _poolInfo.borrowerInfo(address(_pool), _actor);
        (uint256 minDebt, , , ) = _poolInfo.poolUtilizationInfo(address(_pool));

        if (boundedAmount_ < minDebt && minDebt < MAX_DEBT_AMOUNT) boundedAmount_ = minDebt + 1;

        // 2. pool needs sufficent quote token to draw debt
        uint256 normalizedPoolBalance = _quote.balanceOf(address(_pool)) * _pool.quoteTokenScale();

        if (boundedAmount_ > normalizedPoolBalance) {
            _addQuoteToken(boundedAmount_ * 2, LENDER_MAX_BUCKET_INDEX);
        }

        // 3. check if drawing of addition debt will make borrower undercollateralized
        // recalculate lup with new amount to be borrowed and check borrower collateralization at new lup
        (uint256 currentPoolDebt, , , ) = _pool.debtInfo();
        uint256 nextPoolDebt = currentPoolDebt + boundedAmount_;
        uint256 newLup = _priceAt(_pool.depositIndex(nextPoolDebt));
        (debt, collateral, ) = _poolInfo.borrowerInfo(address(_pool), _actor);

        // repay debt if borrower becomes undercollateralized with new debt at new lup
        if (!_isCollateralized(debt + boundedAmount_, collateral, newLup, _pool.poolType())) {
            _repayDebt(type(uint256).max);

            (debt, collateral, ) = _poolInfo.borrowerInfo(address(_pool), _actor);
            _pullCollateral(collateral);

            require(debt == 0, "borrower has debt");
        }
    }

    function _preRepayDebt(
        uint256 amountToRepay_
    ) internal returns (uint256 boundedAmount_) {
        boundedAmount_ = constrictToRange(amountToRepay_, Maths.max(_pool.quoteTokenScale(), MIN_QUOTE_AMOUNT), MAX_QUOTE_AMOUNT);

        // ensure actor has debt to repay
        (uint256 debt, , ) = PoolInfoUtils(_poolInfo).borrowerInfo(address(_pool), _actor);
        if (debt == 0) {
            boundedAmount_ = _preDrawDebt(boundedAmount_);
            _drawDebt(boundedAmount_);
        }
    }
}
