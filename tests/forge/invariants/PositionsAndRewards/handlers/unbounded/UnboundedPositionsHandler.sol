// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.18;

import '@openzeppelin/contracts/utils/structs/EnumerableSet.sol';

import { IPositionManagerOwnerActions } from 'src/interfaces/position/IPositionManagerOwnerActions.sol';
import { 
    _depositFeeRate,
    _lpToQuoteToken,
    _priceAt
    }                                   from 'src/libraries/helpers/PoolHelper.sol';
import { Maths }                        from "src/libraries/internal/Maths.sol";

import '@std/console.sol';

import { BaseERC20PoolHandler }         from '../../../ERC20Pool/handlers/unbounded/BaseERC20PoolHandler.sol';
import { BasePositionsHandler }         from './BasePositionsHandler.sol';

/**
 *  @dev this contract manages multiple lenders
 *  @dev methods in this contract are called in random order
 *  @dev randomly selects a lender contract to make a txn
 */ 
abstract contract UnboundedPositionsHandler is BasePositionsHandler {

    using EnumerableSet for EnumerableSet.UintSet;

    function _memorializePositions(
        uint256 tokenId_,
        uint256[] memory indexes_
    ) internal {
        numberOfCalls['UBPositionHandler.memorialize']++;

        for(uint256 i=0; i < indexes_.length; i++) {

            // store vals pre action to check after memorializing:
            (uint256 actorLps, uint256 actorDepositTime)   = _pool.lenderInfo(indexes_[i], address(_actor));
            (uint256 posManLps, uint256 posManDepositTime) = _pool.lenderInfo(indexes_[i], address(_position));

            bucketIndexToActorPoolLps[indexes_[i]] = actorLps;
            bucketIndexToPositionManPoolLps[indexes_[i]]   = posManLps;

            // positionManager is assigned the most recent depositTime
            bucketIndexToDepositTime[indexes_[i]] = (actorDepositTime >= posManDepositTime) ? actorDepositTime : posManDepositTime;

            // assert that the underlying LP balance in PositionManager is 0 
            (uint256 posPreActionLps,) = _position.getPositionInfo(tokenId_, indexes_[i]);
            require(posPreActionLps == 0);

        }

        try _position.memorializePositions(address(_pool), tokenId_, indexes_) {
            
            // track created positions
            for ( uint256 i = 0; i < indexes_.length; i++) {
                // PM1_PM2_PM3 tracking
                bucketIndexesWithPosition.add(indexes_[i]);
                tokenIdsByBucketIndex[indexes_[i]].add(tokenId_);

                // info used to tearDown buckets
                bucketIndexesByTokenId[tokenId_].add(indexes_[i]);
            }

            // info used track actors positions
            actorByTokenId[tokenId_] = address(_actor);
            tokenIdsByActor[address(_actor)].add(tokenId_);

            // Post action Checks //
            for(uint256 i=0; i < indexes_.length; i++) {
                uint256 bucketIndex = indexes_[i];

                // assert that the LP that now exists in the pool contract matches the amount added by the actor 
                (uint256 poolLps, uint256 poolDepositTime) = _pool.lenderInfo(bucketIndex, address(_position));
                require(poolLps == bucketIndexToActorPoolLps[bucketIndex] + bucketIndexToPositionManPoolLps[bucketIndex]);
                require(poolDepositTime == bucketIndexToDepositTime[bucketIndex]);

                // assert that the underlying LP balance in PositionManager has increased
                (uint256 posLps,) = _position.getPositionInfo(tokenId_, bucketIndex);
                require(posLps == bucketIndexToActorPoolLps[bucketIndex]);

                delete bucketIndexToActorPoolLps[bucketIndex];
                delete bucketIndexToPositionManPoolLps[bucketIndex];
                delete bucketIndexToDepositTime[bucketIndex];
            }

        } catch (bytes memory err) {
            _ensurePoolError(err);
        }
    }

    function _mint() internal returns (uint256 tokenIdResult) {
        numberOfCalls['UBPositionHandler.mint']++;
        try _position.mint(address(_pool), _actor, keccak256("ERC20_NON_SUBSET_HASH")) returns (uint256 tokenId) {

            tokenIdResult = tokenId;

            // Post Action Checks //
            // assert that the minter is the owner
            require(_position.ownerOf(tokenId) == _actor);

            // assert that poolKey is returns correct pool address
            address poolAddress = _position.poolKey(tokenId);
            require(poolAddress == address(_pool));

            // assert that no positions are associated with this tokenId
            uint256[] memory posIndexes = _position.getPositionIndexes(tokenId);
            require(posIndexes.length == 0);

        } catch (bytes memory err) {
            _ensurePoolError(err);
        }
    }

    function _redeemPositions(
        uint256 tokenId_,
        uint256[] memory indexes_
    ) internal {
        numberOfCalls['UBPositionHandler.redeem']++;

        address preActionOwner = _position.ownerOf(tokenId_);

        for (uint256 i=0; i < indexes_.length; i++) {

            // store vals in mappings to check lps
            (uint256 poolPreActionActorLps,)  = _pool.lenderInfo(indexes_[i], preActionOwner);
            (uint256 poolPreActionPosManLps,) = _pool.lenderInfo(indexes_[i], address(_position));

            bucketIndexToActorPoolLps[indexes_[i]]       = poolPreActionActorLps;
            bucketIndexToPositionManPoolLps[indexes_[i]] = poolPreActionPosManLps;

            // assert that the underlying LP balance in PositionManager is greater than 0 
            (uint256 posPreActionLps,) = _position.getPositionInfo(tokenId_, indexes_[i]);
            require(posPreActionLps > 0);
        } 

        try _position.redeemPositions(address(_pool), tokenId_, indexes_) {
            // remove tracked positions
            for ( uint256 i = 0; i < indexes_.length; i++) {
                bucketIndexesWithPosition.remove(indexes_[i]); 
                tokenIdsByBucketIndex[indexes_[i]].remove(tokenId_);
            }

            // info for tear down
            delete actorByTokenId[tokenId_];
            delete bucketIndexesByTokenId[tokenId_];
            tokenIdsByActor[address(_actor)].remove(tokenId_);

            // Post action Checks //
            // assert that the minter is still the owner
            require(_position.ownerOf(tokenId_) == preActionOwner, 'owner is no longer minter on redemption');

            // assert that poolKey is still same
            address poolAddress = _position.poolKey(tokenId_);
            require(poolAddress == address(_pool), 'poolKey has changed on redemption');

            // assert that no positions are associated with this tokenId
            uint256[] memory posIndexes = _position.getPositionIndexes(tokenId_);
            require(posIndexes.length == 0, 'positions still exist after redemption');

            for(uint256 i=0; i < indexes_.length; i++) {
                uint256 bucketIndex = indexes_[i];

                uint256 actorPoolLps        = bucketIndexToActorPoolLps[bucketIndex];
                uint256 positionManPoolLps  = bucketIndexToPositionManPoolLps[bucketIndex];

                (uint256 poolActorLps,) = _pool.lenderInfo(bucketIndex, preActionOwner);
                (uint256 poolPosLps,) = _pool.lenderInfo(bucketIndex, address(_position));

                // assert PositionsMan LP in pool matches the amount redeemed by actor 
                // positionMan has now == positionMan pre - actor's LP change
                require(poolPosLps == positionManPoolLps - (poolActorLps - actorPoolLps));

                // assert actor LP in pool matches amount removed from the posMan's position 
                // assert actor LP in pool = what actor LP had pre + what LP positionManager redeemed to actor
                require(poolActorLps == actorPoolLps + (positionManPoolLps - poolPosLps));

                // assert that the underlying LP balance in PositionManager is zero
                (uint256 posLps, uint256 posDepositTime) = _position.getPositionInfo(tokenId_, bucketIndex);
                require(posLps == 0);
                require(posDepositTime == 0);

                // delete mappings for reuse
                delete bucketIndexToActorPoolLps[bucketIndex];
                delete bucketIndexToPositionManPoolLps[bucketIndex];
            }

        } catch (bytes memory err) {
            _ensurePoolError(err);
        }

    }

    function _getQuoteAtIndex(
        uint256 lp,
        uint256 index
    ) internal view returns (uint256 quoteAtIndex_) {
        // retrieve info of bucket from pool
        (
            uint256 bucketLP,
            uint256 bucketCollateral,
            ,
            uint256 bucketDeposit,
        ) = _pool.bucketInfo(index);

        // calculate the max amount of quote tokens that can be moved, given the tracked LP
        quoteAtIndex_ = _lpToQuoteToken(
            bucketLP,
            bucketCollateral,
            bucketDeposit,
            lp,
            bucketDeposit,
            _priceAt(index)
        );
    }

    function _moveLiquidity(
        uint256 tokenId_,
        uint256 fromIndex_,
        uint256 toIndex_
    ) internal {
        numberOfCalls['UBPositionHandler.moveLiquidity']++;

        // update interest so pre and post token amounts are equal
        _pool.updateInterest();

        // fromIndex values
        (uint256 preActionFromLps,) = _position.getPositionInfo(tokenId_, fromIndex_);
        uint256 preActionFromIndexQuote = _getQuoteAtIndex(preActionFromLps, fromIndex_);

        // toIndex values
        (uint256 preActionToLps,) = _position.getPositionInfo(tokenId_, toIndex_);
        uint256 preActionToIndexQuote = _getQuoteAtIndex(preActionToLps, toIndex_);

        /**
        *  @notice Struct holding parameters for moving the liquidity of a position.
        */

        try _position.moveLiquidity(address(_pool), tokenId_, fromIndex_, toIndex_, block.timestamp + 30) {

            bucketIndexesByTokenId[tokenId_].add(toIndex_);
            bucketIndexesByTokenId[tokenId_].remove(fromIndex_);

            // Post Action Checks //
            // remove tracked positios
            bucketIndexesWithPosition.remove(fromIndex_); 
            tokenIdsByBucketIndex[fromIndex_].remove(tokenId_);

            // track created positions
            bucketIndexesWithPosition.add(toIndex_);
            tokenIdsByBucketIndex[toIndex_].add(tokenId_);

            // assert that underlying LP balance in PositionManager of fromIndex is less than or equal to preAction and deposit time in PositionManager is 0
            (uint256 fromLps, uint256 fromDepositTime) = _position.getPositionInfo(tokenId_, fromIndex_);
            require(fromLps == 0); // difficult to estimate LPS, assert that it is less than
            require(fromDepositTime == 0);

            // assert that underlying LP balance in PositionManager of toIndex is increased and deposit time in PositionManager is updated
            (uint256 toLps, uint256 toDepositTime) = _position.getPositionInfo(tokenId_, toIndex_);
            require(toLps >= preActionToLps); // difficult to estimate LPS, assert that it is greater than
            (,uint256 postActionDepositTime)= _pool.lenderInfo(toIndex_, address(_position));
            require(toDepositTime == postActionDepositTime); 

            // get post action QT represented in positionManager for tokenID
            uint256 postActionFromIndexQuote = _getQuoteAtIndex(fromLps, fromIndex_);
            uint256 postActionToIndexQuote   = _getQuoteAtIndex(toLps, toIndex_);

            // assert total QT represented in positionManager for tokenID postAction is the same as preAction
            // can be less than or equal due to fee on movements above -> below LUP
            assert (preActionFromIndexQuote + preActionToIndexQuote >= postActionFromIndexQuote + postActionToIndexQuote);

        } catch (bytes memory err) {
            _ensurePoolError(err);
        }
    }


    function _burn(
        uint256 tokenId_
    ) internal {
        numberOfCalls['UBPositionHandler.burn']++;
        try _position.burn(address(_pool), tokenId_) {
            // Post Action Checks //
            // should revert if token id is burned
            vm.expectRevert("ERC721: invalid token ID");
            _position.ownerOf(tokenId_);

            // assert that poolKey is returns zero address
            address poolAddress = _position.poolKey(tokenId_);
            require(poolAddress == address(0));

            // assert that no positions are associated with this tokenId
            uint256[] memory posIndexes = _position.getPositionIndexes(tokenId_);
            require(posIndexes.length == 0);
        } catch (bytes memory err) {
            _ensurePoolError(err);
        }
    }
}