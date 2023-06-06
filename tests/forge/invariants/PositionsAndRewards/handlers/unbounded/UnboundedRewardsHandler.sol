// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.18;

import '@std/console.sol';
import '@openzeppelin/contracts/utils/structs/EnumerableSet.sol';

import { IPositionManagerOwnerActions } from 'src/interfaces/position/IPositionManagerOwnerActions.sol';
import { _depositFeeRate }              from 'src/libraries/helpers/PoolHelper.sol';
import { Maths }                        from "src/libraries/internal/Maths.sol";

import { BasePositionsHandler }         from './BasePositionsHandler.sol';

import { _depositFeeRate }   from 'src/libraries/helpers/PoolHelper.sol';


/**
 *  @dev this contract manages multiple lenders
 *  @dev methods in this contract are called in random order
 *  @dev randomly selects a lender contract to make a txn
 */ 
abstract contract UnboundedRewardsHandler is BasePositionsHandler {

    using EnumerableSet for EnumerableSet.UintSet;

    function _stake(
        uint256 tokenId_
    ) internal updateLocalStateAndPoolInterest {
        numberOfCalls['UBRewardsHandler.stake']++;

        require(_position.ownerOf(tokenId_) == address(_actor), "RW5: owner should be actor staking");

        try _rewards.stake(tokenId_) {
            // actor should loses ownership, positionManager gains it
            tokenIdsByActor[address(_rewards)].add(tokenId_);
            tokenIdsByActor[address(_actor)].remove(tokenId_);

            require(_position.ownerOf(tokenId_) == address(_rewards), "RW5: owner should be rewardsManager");

        } catch (bytes memory err) {
            _ensurePoolError(err);
        }
    }

    function _unstake(
        uint256 tokenId_
    ) internal updateLocalStateAndPoolInterest {
        numberOfCalls['UBRewardsHandler.unstake']++;

        uint256 actorAjnaBalanceBeforeClaim = _ajna.balanceOf(_actor);
        uint256 rewardsClaimedBeforeAction  = _rewards.rewardsClaimed(tokenId_);

        try _rewards.unstake(tokenId_) {

            // actor should receive tokenId, positionManager loses ownership
            tokenIdsByActor[address(_actor)].add(tokenId_);
            tokenIdsByActor[address(_rewards)].remove(tokenId_);

            // add to total rewards if actor received reward

            (,,uint256 lastClaimedEpoch) = _rewards.getStakeInfo(tokenId_);

            if ((_ajna.balanceOf(_actor) - actorAjnaBalanceBeforeClaim) != 0) {
                totalRewardPerEpoch[lastClaimedEpoch] += _ajna.balanceOf(_actor) - actorAjnaBalanceBeforeClaim;

                uint256 actorAjnaGain = _ajna.balanceOf(_actor) - actorAjnaBalanceBeforeClaim;
                uint256 rewardsClaimedGain = _rewards.rewardsClaimed(tokenId_) - rewardsClaimedBeforeAction;

                require(_rewards.isEpochClaimed(tokenId_, _pool.currentBurnEpoch()) == true, "RW6: most recent epoch should be claimed");
                require( lastClaimedEpoch == _pool.currentBurnEpoch(), "RW6: most recent epoch should be claimed");
                require(actorAjnaGain == rewardsClaimedGain, "RW6: rewardsManager's rewards claimed increase should match actor's claim");
            }


        } catch (bytes memory err) {
            _ensurePoolError(err);
        }
    }

    function _updateExchangeRate(
        uint256[] memory indexes_
    ) internal {
        numberOfCalls['UBRewardsHandler.exchangeRate']++;

        uint256 actorAjnaBalanceBeforeClaim = _ajna.balanceOf(_actor);

        try _rewards.updateBucketExchangeRatesAndClaim(address(_pool), keccak256("ERC20_NON_SUBSET_HASH"), indexes_) {

            // add to total rewards if actor received reward
            if ((_ajna.balanceOf(_actor) - actorAjnaBalanceBeforeClaim) != 0) {
                uint256 curBurnEpoch = _pool.currentBurnEpoch();
                totalRewardPerEpoch[curBurnEpoch] += _ajna.balanceOf(_actor) - actorAjnaBalanceBeforeClaim;
            }

        } catch (bytes memory err) {
            _ensurePoolError(err);
        }
    }

    function _claimRewards(
        uint256 tokenId_,
        uint256 epoch_
    ) internal {
        numberOfCalls['UBRewardsHandler.claimRewards']++;

        try _rewards.claimRewards(tokenId_, epoch_, 0) {
        } catch (bytes memory err) {
            _ensurePoolError(err);
        }
    }
}
