// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.18;

import '../../../../utils/DSTestPlus.sol';
import '@openzeppelin/contracts/utils/structs/EnumerableSet.sol';

import { IPositionManagerOwnerActions } from 'src/interfaces/position/IPositionManagerOwnerActions.sol';
import { 
    _depositFeeRate,
    _lpToQuoteToken,
    _priceAt
    }                                   from 'src/libraries/helpers/PoolHelper.sol';
import { Maths }                        from "src/libraries/internal/Maths.sol";

import { BaseERC20PoolHandler }         from '../../../ERC20Pool/handlers/unbounded/BaseERC20PoolHandler.sol';
import { UnboundedBasePositionHandler } from './UnboundedBasePositionHandler.sol';

import { BaseHandler } from '../../../base/handlers/unbounded/BaseHandler.sol';

/**
 *  @dev this contract manages multiple lenders
 *  @dev methods in this contract are called in random order
 *  @dev randomly selects a lender contract to make a txn
 */ 
abstract contract UnboundedPositionPoolHandler is UnboundedBasePositionHandler, BaseHandler {

    modifier useRandomPool(uint256 poolIndex) virtual;

    using EnumerableSet for EnumerableSet.UintSet;

    /*********************************/
    /*** Position Helper Functions ***/
    /*********************************/

    function _memorializePositions(
        uint256 tokenId_,
        uint256[] memory indexes_
    ) internal {
        numberOfCalls['UBPositionHandler.memorialize']++;

        for(uint256 i = 0; i < indexes_.length; i++) {

            // store vals pre action to check after memorializing:
            (uint256 poolPreActionActorLps, uint256 actorDepositTime)   = _pool.lenderInfo(indexes_[i], address(_actor));
            (uint256 poolPreActionPosManLps, uint256 posManDepositTime) = _pool.lenderInfo(indexes_[i], address(_positionManager));

            actorLpsBefore[address(_pool)][indexes_[i]]  = poolPreActionActorLps;
            posManLpsBefore[address(_pool)][indexes_[i]] = poolPreActionPosManLps;

            // positionManager is assigned the most recent depositTime
            bucketIndexToDepositTime[address(_pool)][indexes_[i]] = (actorDepositTime >= posManDepositTime) ? actorDepositTime : posManDepositTime;
        }

        try _positionManager.memorializePositions(address(_pool), tokenId_, indexes_) {
            
            // track created positions
            for ( uint256 i = 0; i < indexes_.length; i++) {
                uint256 bucketIndex = indexes_[i];

                bucketIndexesWithPosition[address(_pool)].add(bucketIndex);
                tokenIdsByBucketIndex[address(_pool)][bucketIndex].add(tokenId_);

                // info used to tearDown buckets
                bucketIndexesByTokenId[tokenId_].add(bucketIndex);

                (uint256 poolLps, uint256 poolDepositTime) = _pool.lenderInfo(bucketIndex, address(_positionManager));

                require(poolDepositTime == bucketIndexToDepositTime[address(_pool)][bucketIndex],
                "PM7: positionManager depositTime does not match most recent depositTime");

                // assert that the LP that now exists in the pool contract matches the amount added by the actor 
                require(poolLps == actorLpsBefore[address(_pool)][bucketIndex] + posManLpsBefore[address(_pool)][bucketIndex],
                "PM7: pool contract lps do not match amount added by actor");

                // assert that the positionManager LP balance of the actor has increased
                (uint256 posLps,) = _positionManager.getPositionInfo(tokenId_, bucketIndex);
                require(posLps == actorLpsBefore[address(_pool)][bucketIndex],
                "PM7: positionManager lps do not match amount added by actor");

                delete actorLpsBefore[address(_pool)][bucketIndex];
                delete posManLpsBefore[address(_pool)][bucketIndex];
                delete bucketIndexToDepositTime[address(_pool)][bucketIndex];
            }

            // info used track actors positions
            tokenIdsByActor[address(_actor)].add(tokenId_);

        } catch (bytes memory err) {

            // cleanup buckets so they don't interfere with future calls
            for ( uint256 i = 0; i < indexes_.length; i++) {
                uint256 bucketIndex = indexes_[i];

                delete actorLpsBefore[address(_pool)][bucketIndex];
                delete posManLpsBefore[address(_pool)][bucketIndex];
                delete bucketIndexToDepositTime[address(_pool)][bucketIndex];
            }
            _ensurePositionsManagerError(err);
        }
    }

    function _mint() internal returns (uint256 tokenIdResult) {
        numberOfCalls['UBPositionHandler.mint']++;

        try _positionManager.mint(address(_pool), _actor, _poolHash) returns (uint256 tokenId) {

            tokenIdResult = tokenId;

            // Post Action Checks //
            // assert that the minter is the owner
            require(_positionManager.ownerOf(tokenId) == _actor, "PM4: minter is not owner");

            // assert that poolKey is returns correct pool address
            address poolAddress = _positionManager.poolKey(tokenId);
            require(poolAddress == address(_pool), "PM4: poolKey does not match pool address");

            // assert that no positions are associated with this tokenId
            uint256[] memory posIndexes = _positionManager.getPositionIndexes(tokenId);
            require(posIndexes.length == 0, "PM4: positions are associated with tokenId");

        } catch (bytes memory err) {
            _ensurePositionsManagerError(err);
        }
    }

    function _redeemPositions(
        uint256 tokenId_,
        uint256[] memory indexes_
    ) internal {
        numberOfCalls['UBPositionHandler.redeem']++;

        address preActionOwner       = _positionManager.ownerOf(tokenId_);
        uint256 totalPositionIndexes = _positionManager.getPositionIndexes(tokenId_).length;

        for (uint256 i = 0; i < indexes_.length; i++) {

            (uint256 poolPreActionActorLps,)  = _pool.lenderInfo(indexes_[i], preActionOwner);
            (uint256 poolPreActionPosManLps,) = _pool.lenderInfo(indexes_[i], address(_positionManager));

            // store vals in mappings to check lps
            actorLpsBefore[address(_pool)][indexes_[i]]  = poolPreActionActorLps;
            posManLpsBefore[address(_pool)][indexes_[i]] = poolPreActionPosManLps;
        } 

        try _positionManager.redeemPositions(address(_pool), tokenId_, indexes_) {

            // remove tracked positions
            for ( uint256 i = 0; i < indexes_.length; i++) {
                uint256 bucketIndex = indexes_[i];

                tokenIdsByBucketIndex[address(_pool)][bucketIndex].remove(tokenId_);

                // if no other positions exist for this bucketIndex, remove from bucketIndexesWithPosition
                if (getTokenIdsByBucketIndex(address(_pool), bucketIndex).length == 0) {

                    bucketIndexesWithPosition[address(_pool)].remove(bucketIndex); 
                }

                (uint256 poolActorLps,) = _pool.lenderInfo(bucketIndex, preActionOwner);
                (uint256 poolPosLps,)   = _pool.lenderInfo(bucketIndex, address(_positionManager));

                // assert PositionsMan LP in pool matches the amount redeemed by actor 
                // positionMan has now == positionMan pre - actor's LP change
                require(poolPosLps == posManLpsBefore[address(_pool)][bucketIndex] - (poolActorLps - actorLpsBefore[address(_pool)][bucketIndex]),
                "PM8: positionManager's pool contract lps do not match amount redeemed by actor");

                // assert actor LP in pool matches amount removed from the posMan's position 
                // assert actor LP in pool = what actor LP had pre + what LP positionManager redeemed to actor
                require(poolActorLps == actorLpsBefore[address(_pool)][bucketIndex] + (posManLpsBefore[address(_pool)][bucketIndex] - poolPosLps), 
                "PM8: actor's pool contract lps do not match amount redeemed by actor");

                // assert that the underlying LP balance in PositionManager is zero
                (uint256 posLps, uint256 posDepositTime) = _positionManager.getPositionInfo(tokenId_, bucketIndex);
                require(posLps == 0,         "PM8: tokenId has lps after redemption");
                require(posDepositTime == 0, "PM8: tokenId has depositTime after redemption");

                // delete mappings for reuse
                delete actorLpsBefore[address(_pool)][bucketIndex];
                delete posManLpsBefore[address(_pool)][bucketIndex];

                bucketIndexesByTokenId[tokenId_].remove(bucketIndex);
            }

            // assert that the minter is still the owner
            require(_positionManager.ownerOf(tokenId_) == preActionOwner,
            'PM8: previous owner is no longer owner on redemption');

            // assert that poolKey address matches pool address
            require(_positionManager.poolKey(tokenId_) == address(_pool),
            'PM8: poolKey has changed on redemption');

            // if all positions are redeemed
            if (totalPositionIndexes == indexes_.length) {

                // assert that no positions are associated with this tokenId
                uint256[] memory posIndexes = _positionManager.getPositionIndexes(tokenId_);
                require(posIndexes.length == 0, 'PM8: positions still exist after redemption');
                
                // info for tear down
                delete bucketIndexesByTokenId[tokenId_];
                tokenIdsByActor[address(_actor)].remove(tokenId_);
            }

        } catch (bytes memory err) {

            for ( uint256 i = 0; i < indexes_.length; i++) {
                uint256 bucketIndex = indexes_[i];
                // delete mappings for reuse
                delete actorLpsBefore[address(_pool)][bucketIndex];
                delete posManLpsBefore[address(_pool)][bucketIndex];
            }

            _ensurePositionsManagerError(err);
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
        (uint256 preActionFromLps,) = _positionManager.getPositionInfo(tokenId_, fromIndex_);
        uint256 preActionFromIndexQuote = _getQuoteAtIndex(preActionFromLps, fromIndex_);

        // toIndex values
        (uint256 preActionToLps,) = _positionManager.getPositionInfo(tokenId_, toIndex_);
        uint256 preActionToIndexQuote = _getQuoteAtIndex(preActionToLps, toIndex_);

        /**
        *  @notice Struct holding parameters for moving the liquidity of a position.
        */

        try _positionManager.moveLiquidity(address(_pool), tokenId_, fromIndex_, toIndex_, block.timestamp + 30, false) {

            bucketIndexesByTokenId[tokenId_].add(toIndex_);
            bucketIndexesByTokenId[tokenId_].remove(fromIndex_);

            // Post Action Checks //
            // remove tracked positions
            tokenIdsByBucketIndex[address(_pool)][fromIndex_].remove(tokenId_);

            // if no other positions exist for this bucketIndex, remove from bucketIndexesWithPosition
            if (getTokenIdsByBucketIndex(address(_pool), fromIndex_).length == 0) {
                bucketIndexesWithPosition[address(_pool)].remove(fromIndex_); 
            }

            // track created positions
            bucketIndexesWithPosition[address(_pool)].add(toIndex_);
            tokenIdsByBucketIndex[address(_pool)][toIndex_].add(tokenId_);

            // assert that fromIndex LP and deposit time are both zero
            (uint256 fromLps, uint256 fromDepositTime) = _positionManager.getPositionInfo(tokenId_, fromIndex_);
            require(fromLps == 0,         "PM6: from bucket still has LPs after move");
            require(fromDepositTime == 0, "PM6: from bucket still has deposit time after move");

            // assert that toIndex LP is increased and deposit time matches positionManagers depositTime pre action
            (uint256 toLps, uint256 toDepositTime) = _positionManager.getPositionInfo(tokenId_, toIndex_);
            (,uint256 postActionDepositTime)= _pool.lenderInfo(toIndex_, address(_positionManager));
            require(toLps >= preActionToLps,                "PM6: to bucket lps have not increased"); // difficult to estimate LPS, assert that it is greater than
            require(toDepositTime == postActionDepositTime, "PM6: to bucket deposit time does not match positionManager"); 

            // get post action QT represented in positionManager for tokenID
            uint256 postActionFromIndexQuote = _getQuoteAtIndex(fromLps, fromIndex_);
            uint256 postActionToIndexQuote   = _getQuoteAtIndex(toLps, toIndex_);

            // positionManager's total QT postAction is less than or equal to preAction
            // can be less than or equal due to fee on movements above -> below LUP
            greaterThanWithinDiff(
                preActionFromIndexQuote + preActionToIndexQuote,
                postActionFromIndexQuote + postActionToIndexQuote,
                1,
                "PM6: positiionManager QT balance has increased by `1` margin"
            );

        } catch (bytes memory err) {
            _ensurePositionsManagerError(err);
        }
    }

    function _burn(
        uint256 tokenId_
    ) internal {
        numberOfCalls['UBPositionHandler.burn']++;
        try _positionManager.burn(address(_pool), tokenId_) {
            // Post Action Checks //
            // should revert if token id is burned
            vm.expectRevert("ERC721: invalid token ID");
            require(_positionManager.ownerOf(tokenId_) == address(0), "PM5: ownership is not zero address");

            // assert that poolKey is returns zero address
            address poolAddress = _positionManager.poolKey(tokenId_);
            require(poolAddress == address(0), "PM5: poolKey has not been reset on burn");

            // assert that no positions are associated with this tokenId
            uint256[] memory posIndexes = _positionManager.getPositionIndexes(tokenId_);
            require(posIndexes.length == 0, "PM5: positions still exist after burn");

        } catch (bytes memory err) {
            _ensurePositionsManagerError(err);
        }
    }

    function _transferPosition(
        address receiver_,
        uint256 tokenId_
    ) internal {
        numberOfCalls['UBPositionHandler.transferPosition']++;
        try _positionManager.transferFrom(_actor, receiver_, tokenId_) {

            // actor should loses ownership, receiver gains it
            tokenIdsByActor[address(_actor)].remove(tokenId_);
            tokenIdsByActor[receiver_].add(tokenId_);

            require(_positionManager.ownerOf(tokenId_) == receiver_, "new NFT owner should be receiver");

        } catch (bytes memory err) {
            _ensurePositionsManagerError(err);
        }
    }

    /*************************/
    /**** Helper Methods *****/
    /*************************/

    function updateTokenAndPoolAddress(address pool_) internal virtual;
}