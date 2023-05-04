// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.14;

import '@openzeppelin/contracts/utils/structs/EnumerableSet.sol';

import { Maths } from 'src/libraries/internal/Maths.sol';

import { IPositionManagerOwnerActions } from 'src/interfaces/position/IPositionManagerOwnerActions.sol';
import { PositionManager }              from 'src/PositionManager.sol';

import { UnboundedPositionsHandler } from './unbounded/UnboundedPositionsHandler.sol';
import { BasePositionsHandler }      from './unbounded/BasePositionsHandler.sol';
import { BasicERC20PoolHandler }     from '../../ERC20Pool/handlers/BasicERC20PoolHandler.sol';
import { BaseHandler }               from '../../base/handlers/unbounded/BaseHandler.sol';

contract PositionsHandler is UnboundedPositionsHandler {

    constructor(
        address positions_,
        address pool_,
        address ajna_,
        address quote_,
        address poolInfo_,
        uint256 numOfActors_,
        address testContract_
    ) BaseHandler(pool_, ajna_, quote_, poolInfo_, testContract_) {

        LENDER_MIN_BUCKET_INDEX = vm.envOr("BUCKET_INDEX_ERC20", uint256(2570));
        LENDER_MAX_BUCKET_INDEX = LENDER_MIN_BUCKET_INDEX + vm.envOr("NO_OF_BUCKETS", uint256(3)) - 1;
        
        MIN_QUOTE_AMOUNT = 1e3;
        MAX_QUOTE_AMOUNT = 1e30;

        // Position manager
        _positions = PositionManager(positions_);

        // Actors
        actors = _buildActors(numOfActors_);
    }

    /*******************************/
    /*** Positions Test Functions ***/
    /*******************************/

    function memorializePositions(
        uint256 actorIndex_,
        uint256 bucketIndex_,
        uint256 amountToAdd_,
        uint256 skippedTime_
    ) external useRandomActor(actorIndex_) useRandomLenderBucket(bucketIndex_) useTimestamps skipTime(skippedTime_) {
        numberOfCalls['BPositionHandler.memorialize']++;
        // Pre action //
        (uint256 tokenId, uint256[] memory indexes) = _preMemorializePositions(bucketIndex_, amountToAdd_);

        for(uint256 i=0; i < indexes.length; i++) {

            // store vals in array to check lps -> [poolPreActionLps, posPreActionLps]
            (uint256 poolPreActionActorLps,) = _pool.lenderInfo(indexes[i], address(_actor));
            (uint256 poolPreActionPosManLps,) = _pool.lenderInfo(indexes[i], address(_positions));

            bucketIndexToPreActionActorLps[indexes[i]] = poolPreActionActorLps;
            bucketIndexToPreActionPosLps[indexes[i]] = poolPreActionPosManLps;

            // assert that the underlying LP balance in PositionManager is 0 
            (uint256 posPreActionLps,) = _positions.getPositionInfo(tokenId, indexes[i]);
            assertEq(posPreActionLps, 0);

        }

        // Action phase // 
        _memorializePositions(tokenId, indexes);

        // Post action //
        for(uint256 i=0; i < indexes.length; i++) {
            uint256 bucketIndex = indexes[i];

            // assert that the LP that now exists in the pool contract matches the amount added by the actor 
            (uint256 poolLps,) = _pool.lenderInfo(bucketIndex, address(_positions));
            assertEq(poolLps, bucketIndexToPreActionActorLps[bucketIndex] + bucketIndexToPreActionPosLps[bucketIndex]);

            // assert that the underlying LP balance in PositionManager has increased
            (uint256 posLps, uint256 posDepositTime) = _positions.getPositionInfo(tokenId, bucketIndex);
            assertEq(posLps, bucketIndexToPreActionActorLps[bucketIndex]);
            assertEq(posDepositTime, block.timestamp);

            delete bucketIndexToPreActionActorLps[bucketIndex];
            delete bucketIndexToPreActionPosLps[bucketIndex];
        }


    }

    function redeemPositions(
        uint256 actorIndex_,
        uint256 bucketIndex_,
        uint256 amountToAdd_,
        uint256 skippedTime_
    ) external useRandomActor(actorIndex_) useRandomLenderBucket(bucketIndex_) useTimestamps skipTime(skippedTime_) {
        numberOfCalls['BPositionHandler.redeem']++;
        // Pre action //
        (uint256 tokenId, uint256[] memory indexes) = _preRedeemPositions(bucketIndex_, amountToAdd_);

        for(uint256 i=0; i < indexes.length; i++) {

            // store vals in array to check lps -> [poolPreActionLps, posPreActionLps]
            (uint256 posPreActionActorLps,) = _positions.getPositionInfo(tokenId, indexes[i]);
            (uint256 poolPreActionPosManLps,) = _pool.lenderInfo(indexes[i], address(_positions));

            bucketIndexToPreActionActorLps[indexes[i]] = posPreActionActorLps;
            bucketIndexToPreActionPosLps[indexes[i]] = poolPreActionPosManLps;

            // assert that the underlying LP balance in PositionManager is greater than 0 
            (uint256 posPreActionLps,) = _positions.getPositionInfo(tokenId, indexes[i]);
            assertGt(posPreActionLps, 0);

        }
        
        // Action phase // 
        _redeemPositions(tokenId, indexes);

        // Post action //
        // assert that the minter is still the owner
        assertEq(_positions.ownerOf(tokenId), _actor);

        // assert that poolKey is returns zero address
        address poolAddress = _positions.poolKey(tokenId);
        assertEq(poolAddress, address(0));

        // assert that no positions are associated with this tokenId
        uint256[] memory posIndexes = _positions.getPositionIndexes(tokenId);
        assertEq(posIndexes, new uint256[](0));

        for(uint256 i=0; i < indexes.length; i++) {
            uint256 bucketIndex = indexes[i];

            // assert that the LP that now exists in the pool contract matches the amount removed by the actor 
            (uint256 poolPosLps,) = _pool.lenderInfo(bucketIndex, address(_positions));
            assertEq(poolPosLps, bucketIndexToPreActionPosLps[bucketIndex] - bucketIndexToPreActionActorLps[bucketIndex]);

            // assert that the LP that now exists in the pool contract matches the amount added by the actor 
            (uint256 poolActorLps,) = _pool.lenderInfo(bucketIndex, address(_actor));
            assertEq(poolActorLps, bucketIndexToPreActionPosLps[bucketIndex] - bucketIndexToPreActionActorLps[bucketIndex]);

            // assert that the underlying LP balance in PositionManager is zero
            (uint256 posLps, uint256 posDepositTime) = _positions.getPositionInfo(tokenId, bucketIndex);
            assertEq(posLps, 0);
            assertEq(posDepositTime, block.timestamp);

            delete bucketIndexToPreActionActorLps[bucketIndex];
            delete bucketIndexToPreActionPosLps[bucketIndex];
        }
    }

    function mint(
        uint256 actorIndex_,
        uint256 skippedTime_
    ) external useRandomActor(actorIndex_) useTimestamps skipTime(skippedTime_) {
        numberOfCalls['BPositionHandler.mint']++;        

        // Action phase //
        uint256 tokenId = _mint();
 
        // Post Action //
        // assert that the minter is the owner
        assertEq(_positions.ownerOf(tokenId), _actor);

        // assert that poolKey is returns correct pool address
        address poolAddress = _positions.poolKey(tokenId);
        assertEq(poolAddress, address(_pool));

        // assert that no positions are associated with this tokenId
        uint256[] memory posIndexes = _positions.getPositionIndexes(tokenId);
        assertEq(posIndexes, new uint256[](0));
    }

    function burn(
        uint256 actorIndex_,
        uint256 bucketIndex_,
        uint256 skippedTime_,
        uint256 amountToAdd_
    ) external useRandomActor(actorIndex_) useRandomLenderBucket(bucketIndex_) useTimestamps skipTime(skippedTime_) {
        numberOfCalls['BPositionHandler.burn']++;        
        // Pre action //
        (uint256 tokenId_) = _preBurn(bucketIndex_, amountToAdd_);
        
        // Action phase //
        _burn(tokenId_);

            
        // Post action //
        // assert that no one owns this tokenId
        assertEq(_positions.ownerOf(tokenId_), address(0));

        // assert that poolKey is returns zero address
        address poolAddress = _positions.poolKey(tokenId_);
        assertEq(poolAddress, address(0));

        // assert that no positions are associated with this tokenId
        uint256[] memory posIndexes = _positions.getPositionIndexes(tokenId_);
        assertEq(posIndexes, new uint256[](0));
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

        (uint256 preActionToLps,) = _positions.getPositionInfo(tokenId, toIndex);
        
        // Action phase //
        _moveLiquidity(tokenId, fromIndex, toIndex);

        // Post action //
        // assert that underlying LP balance in PositionManager of fromIndex is 0 and deposit time in PositionManager is 0
        (uint256 fromLps, uint256 fromDepositTime) = _positions.getPositionInfo(tokenId, fromIndex);
        assertGt(fromLps, 0);
        assertEq(fromDepositTime, 0);

        // assert that underlying LP balance in PositionManager of toIndex is increased and deposit time in PositionManager is updated
        (uint256 toLps, uint256 toDepositTime) = _positions.getPositionInfo(tokenId, toIndex);
        assertEq(toLps, preActionToLps); // difficult to estimate LPS, assert that it is greater than
        assertEq(toDepositTime, block.timestamp); 
    }

    function _preMemorializePositions(
        uint256 bucketIndex_,
        uint256 amountToAdd_
    ) internal returns (uint256 tokenId_, uint256[] memory indexes_) {

        // ensure actor has a position
        (uint256 lpBalanceBefore, ) = _pool.lenderInfo(bucketIndex_, _actor);

        // add quote token if they don't have a position
        if (lpBalanceBefore == 0) {
            // Prepare test phase
            uint256 boundedAmount = _preAddQuoteToken(amountToAdd_);
            _addQuoteToken(boundedAmount, bucketIndex_);
        }

        //TODO: Check for exisiting nft positions in PositionManager
        //TODO: stake w/ multiple buckets instead of just one
        indexes_ = new uint256[](1);
        indexes_[0] = bucketIndex_;

        uint256[] memory lpBalances = new uint256[](1);

        // mint position NFT
        tokenId_ = _mint();

        (lpBalances[0], ) = _pool.lenderInfo(bucketIndex_, _actor);
        _pool.increaseLPAllowance(address(_positions), indexes_, lpBalances);
    }

    function _preRedeemPositions(
        uint256 bucketIndex_,
        uint256 amountToAdd_
    ) internal returns (uint256 tokenId_, uint256[] memory indexes_) {
        // Pre action
        (tokenId_, indexes_) = _preMemorializePositions(bucketIndex_, amountToAdd_);
        
        // Action phase
        _memorializePositions(tokenId_, indexes_);
    }

    function _preBurn(
        uint256 bucketIndex_,
        uint256 amountToAdd_
    ) internal returns (uint256 tokenId_) { 
        uint256[] memory indexes;

        // check and create the position
        (tokenId_, indexes) = _preMemorializePositions(bucketIndex_, amountToAdd_);
        //  
        _memorializePositions(tokenId_, indexes);

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