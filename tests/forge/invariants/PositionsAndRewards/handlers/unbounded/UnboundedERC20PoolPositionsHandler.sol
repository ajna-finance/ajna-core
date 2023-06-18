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

/**
 *  @dev this contract manages multiple lenders
 *  @dev methods in this contract are called in random order
 *  @dev randomly selects a lender contract to make a txn
 */ 
abstract contract UnboundedERC20PoolPositionsHandler is UnboundedBasePositionHandler, BaseERC20PoolHandler {

    using EnumerableSet for EnumerableSet.UintSet;

    function _memorializePositions(
        uint256 tokenId_,
        uint256[] memory indexes_
    ) internal {
        numberOfCalls['UBPositionHandler.memorialize']++;

        for(uint256 i=0; i < indexes_.length; i++) {

            // store vals pre action to check after memorializing:
            (uint256 actorLps, uint256 actorDepositTime)   = _pool.lenderInfo(indexes_[i], address(_actor));
            (uint256 posManLps, uint256 posManDepositTime) = _pool.lenderInfo(indexes_[i], address(_positionManager));

            bucketIndexToActorPoolLps[indexes_[i]] = actorLps;
            bucketIndexToPositionManPoolLps[indexes_[i]]   = posManLps;

            // positionManager is assigned the most recent depositTime
            bucketIndexToDepositTime[indexes_[i]] = (actorDepositTime >= posManDepositTime) ? actorDepositTime : posManDepositTime;

            // assert that the underlying LP balance in PositionManager is 0 
            (uint256 posPreActionLps,) = _positionManager.getPositionInfo(tokenId_, indexes_[i]);
            require(posPreActionLps == 0, "tokenID already has lps associated on memorialize");

        }

        try _positionManager.memorializePositions(address(_pool), tokenId_, indexes_) {
            
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
                (uint256 poolLps, uint256 poolDepositTime) = _pool.lenderInfo(bucketIndex, address(_positionManager));
                require(poolLps == bucketIndexToActorPoolLps[bucketIndex] + bucketIndexToPositionManPoolLps[bucketIndex],
                "PM7: pool contract lps do not match amount added by actor");

                require(poolDepositTime == bucketIndexToDepositTime[bucketIndex],
                "PM7: positionManager depositTime does not match most recent depositTime");

                // assert that the positionManager LP balance of the actor has increased
                (uint256 posLps,) = _positionManager.getPositionInfo(tokenId_, bucketIndex);
                require(posLps == bucketIndexToActorPoolLps[bucketIndex],
                "PM7: positionManager lps do not match amount added by actor");

                delete bucketIndexToActorPoolLps[bucketIndex];
                delete bucketIndexToPositionManPoolLps[bucketIndex];
                delete bucketIndexToDepositTime[bucketIndex];
            }

        } catch (bytes memory err) {
            _ensurePositionsManagerError(err);
        }
    }

    function _mint() internal returns (uint256 tokenIdResult) {
        numberOfCalls['UBPositionHandler.mint']++;
        try _positionManager.mint(address(_pool), _actor, keccak256("ERC20_NON_SUBSET_HASH")) returns (uint256 tokenId) {

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

        address preActionOwner = _positionManager.ownerOf(tokenId_);

        for (uint256 i=0; i < indexes_.length; i++) {

            // store vals in mappings to check lps
            (uint256 poolPreActionActorLps,)  = _pool.lenderInfo(indexes_[i], preActionOwner);
            (uint256 poolPreActionPosManLps,) = _pool.lenderInfo(indexes_[i], address(_positionManager));

            bucketIndexToActorPoolLps[indexes_[i]]       = poolPreActionActorLps;
            bucketIndexToPositionManPoolLps[indexes_[i]] = poolPreActionPosManLps;

            // assert that the underlying LP balance in PositionManager is greater than 0 
            (uint256 posPreActionLps,) = _positionManager.getPositionInfo(tokenId_, indexes_[i]);
            require(posPreActionLps > 0, "tokenID does not have lps associated on redemption");
        } 

        try _positionManager.redeemPositions(address(_pool), tokenId_, indexes_) {
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
            require(_positionManager.ownerOf(tokenId_) == preActionOwner,
            'PM8: previous owner is no longer owner on redemption');

            // assert that poolKey is still same
            address poolAddress = _positionManager.poolKey(tokenId_);
            require(poolAddress == address(_pool), 'PM8: poolKey has changed on redemption');

            // assert that no positions are associated with this tokenId
            uint256[] memory posIndexes = _positionManager.getPositionIndexes(tokenId_);
            require(posIndexes.length == 0, 'PM8: positions still exist after redemption');

            for(uint256 i=0; i < indexes_.length; i++) {
                uint256 bucketIndex = indexes_[i];

                uint256 actorPoolLps        = bucketIndexToActorPoolLps[bucketIndex];
                uint256 positionManPoolLps  = bucketIndexToPositionManPoolLps[bucketIndex];

                (uint256 poolActorLps,) = _pool.lenderInfo(bucketIndex, preActionOwner);
                (uint256 poolPosLps,)   = _pool.lenderInfo(bucketIndex, address(_positionManager));

                // assert PositionsMan LP in pool matches the amount redeemed by actor 
                // positionMan has now == positionMan pre - actor's LP change
                require(poolPosLps == positionManPoolLps - (poolActorLps - actorPoolLps),
                "PM8: positionManager's pool contract lps do not match amount redeemed by actor");

                // assert actor LP in pool matches amount removed from the posMan's position 
                // assert actor LP in pool = what actor LP had pre + what LP positionManager redeemed to actor
                require(poolActorLps == actorPoolLps + (positionManPoolLps - poolPosLps), 
                "PM8: actor's pool contract lps do not match amount redeemed by actor");

                // assert that the underlying LP balance in PositionManager is zero
                (uint256 posLps, uint256 posDepositTime) = _positionManager.getPositionInfo(tokenId_, bucketIndex);
                require(posLps == 0,         "PM8: tokenId has lps after redemption");
                require(posDepositTime == 0, "PM8: tokenId has depositTime after redemption");

                // delete mappings for reuse
                delete bucketIndexToActorPoolLps[bucketIndex];
                delete bucketIndexToPositionManPoolLps[bucketIndex];
            }

        } catch (bytes memory err) {
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

        try _positionManager.moveLiquidity(address(_pool), tokenId_, fromIndex_, toIndex_, block.timestamp + 30) {

            bucketIndexesByTokenId[tokenId_].add(toIndex_);
            bucketIndexesByTokenId[tokenId_].remove(fromIndex_);

            // Post Action Checks //
            // remove tracked positios
            bucketIndexesWithPosition.remove(fromIndex_); 
            tokenIdsByBucketIndex[fromIndex_].remove(tokenId_);

            // track created positions
            bucketIndexesWithPosition.add(toIndex_);
            tokenIdsByBucketIndex[toIndex_].add(tokenId_);

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
}

