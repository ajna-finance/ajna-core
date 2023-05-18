// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.14;

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

            bucketIndexToPreActionActorLps[indexes_[i]] = actorLps;
            bucketIndexToPreActionPosLps[indexes_[i]]   = posManLps;

            // positionManager is assigned the most recent depositTime
            bucketIndexToPreActionDepositTime[indexes_[i]] = (actorDepositTime >= posManDepositTime) ? actorDepositTime : posManDepositTime;

            // assert that the underlying LP balance in PositionManager is 0 
            (uint256 posPreActionLps,) = _position.getPositionInfo(tokenId_, indexes_[i]);
            require(posPreActionLps == 0);

        }

        try _position.memorializePositions(IPositionManagerOwnerActions.MemorializePositionsParams(tokenId_, address(_pool), indexes_)) {

            // TODO: store memorialized position's tokenIds in mapping, for reuse in unstake and redeem calls

            // track created positions
            for ( uint256 i = 0; i < indexes_.length; i++) {
                bucketIndexesWithPosition.add(indexes_[i]);
                tokenIdsByBucketIndex[indexes_[i]].add(tokenId_);
            }

            // Post action Checks //
            for(uint256 i=0; i < indexes_.length; i++) {
                uint256 bucketIndex = indexes_[i];

                // assert that the LP that now exists in the pool contract matches the amount added by the actor 
                (uint256 poolLps, uint256 poolDepositTime) = _pool.lenderInfo(bucketIndex, address(_position));
                require(poolLps == bucketIndexToPreActionActorLps[bucketIndex] + bucketIndexToPreActionPosLps[bucketIndex]);
                require(poolDepositTime == bucketIndexToPreActionDepositTime[bucketIndex]);

                // assert that the underlying LP balance in PositionManager has increased
                (uint256 posLps,) = _position.getPositionInfo(tokenId_, bucketIndex);
                require(posLps == bucketIndexToPreActionActorLps[bucketIndex]);

                delete bucketIndexToPreActionActorLps[bucketIndex];
                delete bucketIndexToPreActionPosLps[bucketIndex];
                delete bucketIndexToPreActionDepositTime[bucketIndex];
            }

        } catch (bytes memory err) {
            _ensurePoolError(err);
        }
    }

    function _mint() internal returns (uint256 tokenIdResult) {
        numberOfCalls['UBPositionHandler.mint']++;
        try _position.mint(IPositionManagerOwnerActions.MintParams(_actor, address(_pool), keccak256("ERC20_NON_SUBSET_HASH"))) returns (uint256 tokenId) {

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

        for(uint256 i=0; i < indexes_.length; i++) {

            // store vals in mappings to check lps -> [poolPreActionLps, posPreActionLps]
            (uint256 posPreActionActorLps,) = _position.getPositionInfo(tokenId_, indexes_[i]);
            (uint256 poolPreActionPosManLps,) = _pool.lenderInfo(indexes_[i], address(_position));

            bucketIndexToPreActionActorLps[indexes_[i]] = posPreActionActorLps;
            bucketIndexToPreActionPosLps[indexes_[i]]   = poolPreActionPosManLps;

            // assert that the underlying LP balance in PositionManager is greater than 0 
            (uint256 posPreActionLps,) = _position.getPositionInfo(tokenId_, indexes_[i]);
            require(posPreActionLps > 0);

        }

        try _position.redeemPositions(IPositionManagerOwnerActions.RedeemPositionsParams(tokenId_, address(_pool), indexes_)) {

            // remove tracked positions
            for ( uint256 i = 0; i < indexes_.length; i++) {
                bucketIndexesWithPosition.remove(indexes_[i]); 
                tokenIdsByBucketIndex[indexes_[i]].remove(tokenId_);
            }

            // Post action Checks //
            // assert that the minter is still the owner
            require(_position.ownerOf(tokenId_) == _actor, 'owner is no longer minter on redemption');

            // assert that poolKey is still same
            address poolAddress = _position.poolKey(tokenId_);
            require(poolAddress == address(_pool), 'poolKey has changed on redemption');

            // assert that no positions are associated with this tokenId
            uint256[] memory posIndexes = _position.getPositionIndexes(tokenId_);
            require(posIndexes.length == 0, 'positions still exist after redemption');

            for(uint256 i=0; i < indexes_.length; i++) {
                uint256 bucketIndex = indexes_[i];

                // assert PositionsMan LP in pool matches the amount redeemed by actor 
                (uint256 poolPosLps,) = _pool.lenderInfo(bucketIndex, address(_position));
                require(poolPosLps == bucketIndexToPreActionPosLps[bucketIndex] - bucketIndexToPreActionActorLps[bucketIndex]);

                // assert actor LP in pool matches the amount amount of LP redeemed by actor
                (uint256 poolActorLps,) = _pool.lenderInfo(bucketIndex, address(_actor));
                require(poolActorLps == bucketIndexToPreActionActorLps[bucketIndex]);

                // assert that the underlying LP balance in PositionManager is zero
                (uint256 posLps, uint256 posDepositTime) = _position.getPositionInfo(tokenId_, bucketIndex);
                require(posLps == 0);
                require(posDepositTime == 0);

                // delete mappings for reuse
                delete bucketIndexToPreActionActorLps[bucketIndex];
                delete bucketIndexToPreActionPosLps[bucketIndex];
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

        // fromIndex values
        (uint256 preActionFromLps, uint256 preActionDepositTime) = _position.getPositionInfo(tokenId_, fromIndex_);
        uint256 preActionFromIndexQuote = _getQuoteAtIndex(preActionFromLps, fromIndex_);

        // toIndex values
        (uint256 preActionToLps,) = _position.getPositionInfo(tokenId_, toIndex_);
        uint256 preActionToIndexQuote = _getQuoteAtIndex(preActionToLps, toIndex_);

        /**
        *  @notice Struct holding parameters for moving the liquidity of a position.
        */

        try _position.moveLiquidity(IPositionManagerOwnerActions.MoveLiquidityParams(tokenId_, address(_pool), fromIndex_, toIndex_, block.timestamp + 30)) {

            // TODO: store memorialized position's tokenIds in mapping, for reuse in unstake and redeem calls

            // Post Action Checks //
            // track created positions
            bucketIndexesWithPosition.add(toIndex_);
            tokenIdsByBucketIndex[toIndex_].add(tokenId_);

            // assert that underlying LP balance in PositionManager of fromIndex is 0 and deposit time in PositionManager is 0
            (uint256 fromLps, uint256 fromDepositTime) = _position.getPositionInfo(tokenId_, fromIndex_);
            require(fromLps <= preActionFromLps); // difficult to estimate LPS, assert that it is less than
            require(fromDepositTime == preActionDepositTime);

            // assert that underlying LP balance in PositionManager of toIndex is increased and deposit time in PositionManager is updated
            (uint256 toLps, uint256 toDepositTime) = _position.getPositionInfo(tokenId_, toIndex_);
            require(toLps >= preActionToLps); // difficult to estimate LPS, assert that it is greater than
            (,uint256 postActionDepositTime)= _pool.lenderInfo(toIndex_, address(_position));
            require(toDepositTime == postActionDepositTime); 

            // get post action QT represented in positionManager for tokenID
            uint256 postActionFromIndexQuote = _getQuoteAtIndex(fromLps, fromIndex_);
            uint256 postActionToIndexQuote   = _getQuoteAtIndex(toLps, toIndex_);

            // assert total QT represented in positionManager for tokenID postAction is the same as preAction
            assert (preActionFromIndexQuote + preActionToIndexQuote == postActionFromIndexQuote + postActionToIndexQuote);

        } catch (bytes memory err) {
            _ensurePoolError(err);
        }
    }


    function _burn(
        uint256 tokenId_
    ) internal {
        numberOfCalls['UBPositionHandler.burn']++;
        try _position.burn(IPositionManagerOwnerActions.BurnParams(tokenId_, address(_pool))) {
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