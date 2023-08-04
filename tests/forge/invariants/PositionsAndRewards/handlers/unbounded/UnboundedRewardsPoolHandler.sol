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

import { UnboundedPositionPoolHandler } from './UnboundedPositionPoolHandler.sol';

/**
 *  @dev this contract manages multiple lenders
 *  @dev methods in this contract are called in random order
 *  @dev randomly selects a lender contract to make a txn
 */ 
abstract contract UnboundedRewardsPoolHandler is UnboundedPositionPoolHandler {

    using EnumerableSet for EnumerableSet.UintSet;

    /********************************/
    /*** Rewards Helper Functions ***/
    /********************************/

    function _stake(
        uint256 tokenId_
    ) internal updateLocalStateAndPoolInterest {
        numberOfCalls['UBRewardsHandler.stake']++;

        require(_positionManager.ownerOf(tokenId_) == address(_actor), "the actor calling `stake()` is not the owner");

        try _rewardsManager.stake(tokenId_) {
            // actor should loses ownership, positionManager gains it
            tokenIdsByActor[address(_rewardsManager)].add(tokenId_);
            tokenIdsByActor[address(_actor)].remove(tokenId_);

            // staked position is tracked
            stakedTokenIdsByActor[address(_actor)].add(tokenId_);

            require(_positionManager.ownerOf(tokenId_) == address(_rewardsManager), "RW5: owner should be rewardsManager");

        } catch (bytes memory err) {
            _ensureRewardsManagerError(err);
        }
    }

    function _unstake(
        uint256 tokenId_
    ) internal updateLocalStateAndPoolInterest {
        numberOfCalls['UBRewardsHandler.unstake']++;

        // track balances
        uint256 actorAjnaBalanceBeforeClaim    = _ajna.balanceOf(_actor);
        uint256 contractAjnaBalanceBeforeClaim = _ajna.balanceOf(address(_rewardsManager));

        (,,uint256 preActionLastClaimedEpoch) = _rewardsManager.getStakeInfo(tokenId_);

        // loop over all epochs that are going to be
        uint256 totalRewardsEarnedPreAction;

        uint256[] memory rewardsEarnedInEpochPreAction = new uint256[](_pool.currentBurnEpoch() + 1);

        for (uint256 epoch = preActionLastClaimedEpoch; epoch <= _pool.currentBurnEpoch(); epoch++) {

            // for epochs already claimed by the staker, `rewardsClaimed()` should go unchanged 
            if (_rewardsManager.isEpochClaimed(tokenId_, epoch)) {
                rewardsEarnedInEpochPreAction[epoch] = _rewardsManager.getRewardsClaimed(address(_pool), epoch);
            }
            
            // total the rewards earned pre action
            totalRewardsEarnedPreAction  += _rewardsManager.getRewardsClaimed(address(_pool), epoch) + _rewardsManager.getUpdateRewardsClaimed(address(_pool), epoch);
        } 

        try _rewardsManager.unstake(tokenId_) {

            // actor should receive tokenId, positionManager loses ownership
            tokenIdsByActor[address(_actor)].add(tokenId_);
            tokenIdsByActor[address(_rewardsManager)].remove(tokenId_);

            // staked position is no longer tracked
            stakedTokenIdsByActor[address(_actor)].remove(tokenId_);

            // balance changes
            uint256 actorAjnaGain = _ajna.balanceOf(_actor) - actorAjnaBalanceBeforeClaim;

            // loop over all epochs that were claimed
            uint256 totalRewardsEarnedPostAction;
            for (uint256 epoch = preActionLastClaimedEpoch; epoch <= _pool.currentBurnEpoch(); epoch++) {

                // if lastClaimed is the same as epoch staked isEpochClaimed will return false
                if (epoch != preActionLastClaimedEpoch) {
                    require(_rewardsManager.isEpochClaimed(tokenId_, epoch) == true,
                    "RW6: epoch after claim rewards is not claimed");
                }
                
                if (rewardsEarnedInEpochPreAction[epoch] > 0) {
                    require(rewardsEarnedInEpochPreAction[epoch] == _rewardsManager.getRewardsClaimed(address(_pool), epoch), 
                    "RW10: staker has claimed rewards from the same epoch twice"); 
                }

                // total rewards earned across all actors in epoch post action
                totalRewardsEarnedPostAction += _rewardsManager.getRewardsClaimed(address(_pool), epoch) + _rewardsManager.getUpdateRewardsClaimed(address(_pool), epoch);

                // reset staking and updating rewards earned in epoch
                rewardsClaimedPerEpoch[address(_pool)][epoch]       = _rewardsManager.getRewardsClaimed(address(_pool), epoch);
                updateRewardsClaimedPerEpoch[address(_pool)][epoch] = _rewardsManager.getUpdateRewardsClaimed(address(_pool), epoch);
            }

            require(_positionManager.ownerOf(tokenId_) == address(_actor),
            "RW5: caller of unstake is not owner of NFT");

            require(actorAjnaGain <= totalRewardsEarnedPostAction - totalRewardsEarnedPreAction,
            "RW7: actor's total claimed is greater than rewards earned");

            require(actorAjnaGain == contractAjnaBalanceBeforeClaim - _ajna.balanceOf(address(_rewardsManager)),
            "RW8: ajna deducted from rewardsManager doesn't equal ajna gained by actor");

            (address owner, address pool, uint256 lastClaimedEpoch) = _rewardsManager.getStakeInfo(tokenId_);
            require(owner == address(0) && pool == address(0) && lastClaimedEpoch == 0,
            "RW9: stake info is not reset after unstake");

        } catch (bytes memory err) {
            _ensureRewardsManagerError(err);
        }
    }

    function _emergencyUnstake(
        uint256 tokenId_
    ) internal updateLocalStateAndPoolInterest {
        numberOfCalls['UBRewardsHandler.emergencyUnstake']++;

        uint256 actorAjnaBalanceBeforeClaim    = _ajna.balanceOf(_actor);
        uint256 contractAjnaBalanceBeforeClaim = _ajna.balanceOf(address(_rewardsManager));

        // loop over all epochs that have occured
        uint256 totalRewardsEarnedPreAction;
        for (uint256 epoch = 0; epoch <= _pool.currentBurnEpoch(); epoch++) {
             
            // total rewards earned across all actors in epoch pre action
            totalRewardsEarnedPreAction  += _rewardsManager.getRewardsClaimed(address(_pool), epoch) + _rewardsManager.getUpdateRewardsClaimed(address(_pool), epoch);
        }

        try _rewardsManager.emergencyUnstake(tokenId_) {

            // actor should receive tokenId, positionManager loses ownership
            tokenIdsByActor[address(_actor)].add(tokenId_);
            tokenIdsByActor[address(_rewardsManager)].remove(tokenId_);

            // staked position is no longer tracked
            stakedTokenIdsByActor[address(_actor)].remove(tokenId_);

            // loop over all epochs that have occured
            uint256 totalRewardsEarnedPostAction;
            for (uint256 epoch = 0; epoch <= _pool.currentBurnEpoch(); epoch++) {

                // total rewards earned across all actors in epoch post action
                totalRewardsEarnedPostAction += _rewardsManager.getRewardsClaimed(address(_pool), epoch) + _rewardsManager.getUpdateRewardsClaimed(address(_pool), epoch);
            }

            require(totalRewardsEarnedPreAction == totalRewardsEarnedPostAction,
            "rewards were earned on emergency unstake");

            require(_positionManager.ownerOf(tokenId_) == address(_actor),
            "RW5: caller of unstake is not owner of NFT");

            require(contractAjnaBalanceBeforeClaim == _ajna.balanceOf(address(_rewardsManager)),
            "RW8: ajna balance of rewardsManager changed");

            require(actorAjnaBalanceBeforeClaim == _ajna.balanceOf(_actor),
            "RW8: ajna balance of actor changed");

        } catch (bytes memory err) {
            _ensureRewardsManagerError(err);
        }
    }

    function _updateExchangeRate(
        uint256[] memory indexes_
    ) internal {
        numberOfCalls['UBRewardsHandler.updateExchangeRate']++;

        // track balances
        uint256 actorAjnaBalanceBeforeClaim    = _ajna.balanceOf(_actor);
        uint256 contractAjnaBalanceBeforeClaim = _ajna.balanceOf(address(_rewardsManager));
      
        // total the rewards earned pre action
        uint256 totalRewardsEarnedPreAction = _rewardsManager.getUpdateRewardsClaimed(address(_pool), _pool.currentBurnEpoch());

        try _rewardsManager.updateBucketExchangeRatesAndClaim(address(_pool), keccak256("ERC20_NON_SUBSET_HASH"), indexes_) {

            // balance changes
            uint256 actorAjnaGain = _ajna.balanceOf(_actor) - actorAjnaBalanceBeforeClaim;

            require(actorAjnaGain <= _rewardsManager.getUpdateRewardsClaimed(address(_pool), _pool.currentBurnEpoch()) - totalRewardsEarnedPreAction,
            "RW7: actor's total claimed is greater than update rewards earned");

            require(actorAjnaGain == contractAjnaBalanceBeforeClaim - _ajna.balanceOf(address(_rewardsManager)),
            "RW8: ajna deducted from rewardsManager doesn't equal ajna gained by actor");

        } catch (bytes memory err) {
            _ensureRewardsManagerError(err);
        }
    }

    function _claimRewards(
        uint256 tokenId_,
        uint256 epoch_
    ) internal {
        numberOfCalls['UBRewardsHandler.claimRewards']++;

        // track balances
        uint256 actorAjnaBalanceBeforeClaim    = _ajna.balanceOf(_actor);
        uint256 contractAjnaBalanceBeforeClaim = _ajna.balanceOf(address(_rewardsManager));

        (,,uint256 preActionLastClaimedEpoch) = _rewardsManager.getStakeInfo(tokenId_);

        // loop over all epochs that are going to be
        uint256 totalRewardsEarnedPreAction;

        uint256[] memory rewardsEarnedInEpochPreAction = new uint256[](_pool.currentBurnEpoch() + 1);
        for (uint256 epoch = preActionLastClaimedEpoch; epoch <= _pool.currentBurnEpoch(); epoch++) {
            
            // track epochs that have already been claimed
            if (_rewardsManager.isEpochClaimed(tokenId_, epoch)) {
                rewardsEarnedInEpochPreAction[epoch] = _rewardsManager.getRewardsClaimed(address(_pool), epoch);
            }
            // total the rewards earned pre action
            totalRewardsEarnedPreAction  += _rewardsManager.getRewardsClaimed(address(_pool), epoch) + _rewardsManager.getUpdateRewardsClaimed(address(_pool), epoch);
        }

        try _rewardsManager.claimRewards(tokenId_, epoch_, 0) {

            // balance changes
            uint256 actorAjnaGain = _ajna.balanceOf(_actor) - actorAjnaBalanceBeforeClaim;

            // loop over all epochs that were claimed
            uint256 totalRewardsEarnedPostAction;
            for (uint256 epoch = preActionLastClaimedEpoch; epoch <= _pool.currentBurnEpoch(); epoch++) {

                // if lastClaimed is the same as epoch staked isEpochClaimed will return false
                if (epoch != preActionLastClaimedEpoch) {
                    require(_rewardsManager.isEpochClaimed(tokenId_, epoch) == true,
                    "RW6: epoch after claim rewards is not claimed");
                }

                if (rewardsEarnedInEpochPreAction[epoch] > 0) {
                    require(rewardsEarnedInEpochPreAction[epoch] == _rewardsManager.getRewardsClaimed(address(_pool), epoch), 
                    "RW10: staker has claimed rewards from the same epoch twice"); 
                }

                // total rewards earned across all actors in epoch post action
                totalRewardsEarnedPostAction += _rewardsManager.getRewardsClaimed(address(_pool), epoch) + _rewardsManager.getUpdateRewardsClaimed(address(_pool), epoch);

                // reset staking and updating rewards earned in epoch
                rewardsClaimedPerEpoch[address(_pool)][epoch]       = _rewardsManager.getRewardsClaimed(address(_pool), epoch);
                updateRewardsClaimedPerEpoch[address(_pool)][epoch] = _rewardsManager.getUpdateRewardsClaimed(address(_pool), epoch);
            }

            (, , uint256 lastClaimedEpoch) = _rewardsManager.getStakeInfo(tokenId_);
            require(lastClaimedEpoch == _pool.currentBurnEpoch(),
            "RW6: lastClaimed is not current epoch");

            require(actorAjnaGain <= totalRewardsEarnedPostAction - totalRewardsEarnedPreAction,
            "RW7: actor's total claimed is greater than rewards earned");

            require(actorAjnaGain == contractAjnaBalanceBeforeClaim - _ajna.balanceOf(address(_rewardsManager)),
            "RW8: ajna deducted from rewardsManager doesn't equal ajna gained by actor");

        } catch (bytes memory err) {
            _ensureRewardsManagerError(err);
        }
    }

    function _advanceEpochRewardStakers(
        uint256 amountToAdd_,
        uint256[] memory indexes_,
        uint256 numberOfEpochs_
    ) internal virtual;

    function _ensureRewardsManagerError(bytes memory err_) internal pure {
        bytes32 err = keccak256(err_);

        require(
            err == keccak256(abi.encodeWithSignature("AlreadyClaimed()")) ||
            err == keccak256(abi.encodeWithSignature("EpochNotAvailable()")) ||
            err == keccak256(abi.encodeWithSignature("InsufficientLiquidity()")) ||
            err == keccak256(abi.encodeWithSignature("MoveStakedLiquidityInvalid()")) ||
            err == keccak256(abi.encodeWithSignature("NotAjnaPool()")) ||
            err == keccak256(abi.encodeWithSignature("NotOwnerOfDeposit()")) ||
            err == keccak256(abi.encodeWithSignature("DeployWithZeroAddress()")),
            "Unexpected revert error"
        );
    }
}