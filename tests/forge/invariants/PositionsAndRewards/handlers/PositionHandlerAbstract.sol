// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.14;

import '@openzeppelin/contracts/utils/structs/EnumerableSet.sol';
import '@std/console.sol';

import { Maths } from 'src/libraries/internal/Maths.sol';

import { IPositionManagerOwnerActions } from 'src/interfaces/position/IPositionManagerOwnerActions.sol';
import { PositionManager }              from 'src/PositionManager.sol';
import { ERC20Pool }                    from 'src/ERC20Pool.sol';

import { UnboundedPositionsHandler } from './unbounded/UnboundedPositionsHandler.sol';
import { BaseERC20PoolHandler }     from '../../ERC20Pool/handlers/unbounded/BaseERC20PoolHandler.sol';

abstract contract PositionHandlerAbstract is UnboundedPositionsHandler {

    /*******************************/
    /*** Positions Test Functions ***/
    /*******************************/

    function memorializePositions(
        uint256 actorIndex_,
        uint256 bucketIndex_,
        uint256 amountToAdd_,
        uint256 skippedTime_
    ) external useRandomActor(actorIndex_) useTimestamps skipTime(skippedTime_) {
        numberOfCalls['BPositionHandler.memorialize']++;
        // Pre action //
        (uint256 tokenId, uint256[] memory indexes) = _preMemorializePositions(_lenderBucketIndex, amountToAdd_);

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
        
        // Action phase //
        _moveLiquidity(tokenId, fromIndex, toIndex);
    }

    function _preMemorializePositions(
        uint256 bucketIndex_,
        uint256 amountToAdd_
    ) internal returns (uint256 tokenId_, uint256[] memory indexes_) {

        // ensure actor has a position
        uint256 boundedIndex_   = constrictToRange(bucketIndex_, LENDER_MIN_BUCKET_INDEX, LENDER_MAX_BUCKET_INDEX);
        console.log("premem");
        (uint256 lpBalanceBefore,) = _pool.lenderInfo(boundedIndex_, _actor);
        console.log("aftermem");

        // add quote token if they don't have a position
        if (lpBalanceBefore == 0) {
            // Prepare test phase
            uint256 boundedAmount = constrictToRange(amountToAdd_, MIN_QUOTE_AMOUNT, MAX_QUOTE_AMOUNT);
            try _pool.addQuoteToken(boundedAmount, boundedIndex_, block.timestamp + 1 minutes) {
            } catch (bytes memory err) {
                _ensurePoolError(err);
            }
        }

        //TODO: Check for exisiting nft positions in PositionManager
        //TODO: stake w/ multiple buckets instead of just one
        indexes_ = new uint256[](1);
        indexes_[0] = boundedIndex_;

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
        (tokenId_, indexes_) = _preMemorializePositions(bucketIndex_, amountToAdd_);
        
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
        boundedFromIndex_ = constrictToRange(fromIndex_, LENDER_MIN_BUCKET_INDEX, LENDER_MAX_BUCKET_INDEX);
        boundedToIndex_   = constrictToRange(toIndex_,   LENDER_MIN_BUCKET_INDEX, LENDER_MAX_BUCKET_INDEX);
        uint256 boundedAmount_    = constrictToRange(amountToMove_, MIN_QUOTE_AMOUNT, MAX_QUOTE_AMOUNT);

        // TODO: check if the actor has an existing position and use that one
        // mint a position if the actor doesn't have one
        uint256[] memory indexes;
        (tokenId_, indexes) = _preMemorializePositions(boundedFromIndex_, boundedAmount_);

        _memorializePositions(tokenId_, indexes);

    }
}