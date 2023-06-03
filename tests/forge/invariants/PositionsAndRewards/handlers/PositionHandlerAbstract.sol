// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.18;

import '@openzeppelin/contracts/utils/structs/EnumerableSet.sol';
import '@std/console.sol';

import { Maths } from 'src/libraries/internal/Maths.sol';

import { _priceAt }                     from 'src/libraries/helpers/PoolHelper.sol';

import { IPositionManagerOwnerActions } from 'src/interfaces/position/IPositionManagerOwnerActions.sol';
import { PositionManager }              from 'src/PositionManager.sol';
import { ERC20Pool }                    from 'src/ERC20Pool.sol';

import { UnboundedPositionsHandler } from './unbounded/UnboundedPositionsHandler.sol';
import { BaseERC20PoolHandler }     from '../../ERC20Pool/handlers/unbounded/BaseERC20PoolHandler.sol';

abstract contract PositionHandlerAbstract is UnboundedPositionsHandler {

    using EnumerableSet for EnumerableSet.UintSet;

    /********************************/
    /*** Positions Test Functions ***/
    /********************************/

    function memorializePositions(
        uint256 actorIndex_,
        uint256 bucketIndex_,
        uint256 amountToAdd_,
        uint256 skippedTime_
    ) external useRandomActor(actorIndex_) useRandomLenderBucket(bucketIndex_) useTimestamps skipTime(skippedTime_) {
        numberOfCalls['BPositionHandler.memorialize']++;
        // Pre action //
        (uint256 tokenId, uint256[] memory indexes,) = _preMemorializePositions(_lenderBucketIndex, amountToAdd_);

        // Action phase // 
        _memorializePositions(tokenId, indexes);
    }

    function redeemPositions(
        uint256 actorIndex_,
        uint256 bucketIndex_,
        uint256 amountToAdd_,
        uint256 skippedTime_
    ) external useRandomActor(actorIndex_) useRandomLenderBucket(bucketIndex_) useTimestamps skipTime(skippedTime_) {
        numberOfCalls['BPositionHandler.redeem']++;
        // Pre action //
        (uint256 tokenId, uint256[] memory indexes) = _preRedeemPositions(_lenderBucketIndex, amountToAdd_);
        
        // Action phase // 
        _redeemPositions(tokenId, indexes);
    }

    function mint(
        uint256 actorIndex_,
        uint256 skippedTime_
    ) external useRandomActor(actorIndex_) useTimestamps skipTime(skippedTime_) {
        numberOfCalls['BPositionHandler.mint']++;        

        // Action phase //
        _mint();
    }

    function burn(
        uint256 actorIndex_,
        uint256 bucketIndex_,
        uint256 skippedTime_,
        uint256 amountToAdd_
    ) external useRandomActor(actorIndex_) useRandomLenderBucket(bucketIndex_) useTimestamps skipTime(skippedTime_) {
        numberOfCalls['BPositionHandler.burn']++;        
        // Pre action //
        (uint256 tokenId_) = _preBurn(_lenderBucketIndex, amountToAdd_);
        
        // Action phase //
        _burn(tokenId_);
    }

    function moveLiquidity(
        uint256 actorIndex_,
        uint256 skippedTime_,
        uint256 amountToMove_,
        uint256 fromIndex_,
        uint256 toIndex_
    ) external useRandomActor(actorIndex_) useTimestamps skipTime(skippedTime_) {
        numberOfCalls['BPositionHandler.moveLiquidity']++;        
        // Pre action //
        (
            uint256 tokenId,
            uint256 fromIndex,
            uint256 toIndex
        ) = _preMoveLiquidity(amountToMove_, fromIndex_, toIndex_);

        // retrieve info of bucket from pool
        (
            ,
            uint256 bucketCollateral,
            ,
            ,
        ) = _pool.bucketInfo(fromIndex);

        // to avoid LP mismatch revert return if bucket has collateral or exchangeRate < 1e18
        if (bucketCollateral != 0) return;
        if (_pool.bucketExchangeRate(fromIndex) < 1e18) return;
        
        // Action phase //
        _moveLiquidity(tokenId, fromIndex, toIndex);
    }

    function _preMemorializePositions(
        uint256 bucketIndex_,
        uint256 amountToAdd_
    ) internal returns (uint256 tokenId_, uint256[] memory indexes_, uint256 boundedAmount_) {

        // ensure actor has a position
        (uint256 lpBalanceBefore,) = _pool.lenderInfo(bucketIndex_, _actor);

        // add quote token if they don't have a position
        if (lpBalanceBefore == 0) {
            // Prepare test phase
            boundedAmount_ = constrictToRange(amountToAdd_, MIN_QUOTE_AMOUNT, MAX_QUOTE_AMOUNT);
            _ensureQuoteAmount(_actor, boundedAmount_);
            try _pool.addQuoteToken(boundedAmount_, bucketIndex_, block.timestamp + 1 minutes) {
            } catch (bytes memory err) {
                _ensurePoolError(err);
            }
        }

        // TODO: set bounded amount to what lender has in bucket in QT

        // TODO: Check for exisiting nft positions in PositionManager
        // TODO: stake w/ multiple buckets instead of just one
        indexes_ = new uint256[](1);
        indexes_[0] = bucketIndex_;

        uint256[] memory lpBalances = new uint256[](1);

        // mint position NFT
        tokenId_ = _mint();

        (lpBalances[0], ) = _pool.lenderInfo(bucketIndex_, _actor);
        _pool.increaseLPAllowance(address(_position), indexes_, lpBalances);
    }

    function _preRedeemPositions(
        uint256 bucketIndex_,
        uint256 amountToAdd_
    ) internal returns (uint256 tokenId_, uint256[] memory indexes_) {
        // Pre action
        (tokenId_, indexes_,) = _preMemorializePositions(bucketIndex_, amountToAdd_);
        
        // Action phase
        _memorializePositions(tokenId_, indexes_);

        address[] memory transferors = new address[](1);
        transferors[0] = address(_position);

        _pool.approveLPTransferors(transferors);
    }

    function _preBurn(
        uint256 bucketIndex_,
        uint256 amountToAdd_
    ) internal returns (uint256 tokenId_) { 
        uint256[] memory indexes;

        // check and create the position
        (tokenId_, indexes) = _preRedeemPositions(bucketIndex_, amountToAdd_);

        _redeemPositions(tokenId_, indexes);
    }

    function _preMoveLiquidity(
        uint256 amountToMove_,
        uint256 fromIndex_,
        uint256 toIndex_
    ) internal returns (uint256 tokenId_, uint256 boundedFromIndex_, uint256 boundedToIndex_) {
        boundedFromIndex_      = constrictToRange(fromIndex_, LENDER_MIN_BUCKET_INDEX, LENDER_MAX_BUCKET_INDEX);
        boundedToIndex_        = constrictToRange(toIndex_,   LENDER_MIN_BUCKET_INDEX, LENDER_MAX_BUCKET_INDEX);

        // TODO: check if the actor has an existing position and use that one

        // mint a position to move
        changePrank(_actor);
        uint256[] memory indexes;
        (tokenId_, indexes,) = _preMemorializePositions(boundedFromIndex_, amountToMove_);
        _memorializePositions(tokenId_, indexes); 
    }
}