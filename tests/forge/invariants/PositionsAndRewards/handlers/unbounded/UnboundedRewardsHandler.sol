// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.18;

import '@openzeppelin/contracts/utils/structs/EnumerableSet.sol';

import { IPositionManagerOwnerActions } from 'src/interfaces/position/IPositionManagerOwnerActions.sol';
import { _depositFeeRate }              from 'src/libraries/helpers/PoolHelper.sol';
import { Maths }                        from "src/libraries/internal/Maths.sol";

import { UnboundedBasePositionHandler } from './UnboundedBasePositionHandler.sol';

import { _depositFeeRate }   from 'src/libraries/helpers/PoolHelper.sol';

import '@std/console.sol';

/**
 *  @dev this contract manages multiple lenders
 *  @dev methods in this contract are called in random order
 *  @dev randomly selects a lender contract to make a txn
 */ 
abstract contract UnboundedRewardsHandler is UnboundedBasePositionHandler {

    using EnumerableSet for EnumerableSet.UintSet;

    function _stake(
        uint256 tokenId_
    ) internal updateLocalStateAndPoolInterest {
        numberOfCalls['UBRewardsHandler.stake']++;

        require(_positionManager.ownerOf(tokenId_) == address(_actor), "RW5: owner should be actor staking");

        try _rewardsManager.stake(tokenId_) {
            // actor should loses ownership, positionManager gains it
            tokenIdsByActor[address(_rewardsManager)].add(tokenId_);
            tokenIdsByActor[address(_actor)].remove(tokenId_);

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
        for (uint256 epoch = preActionLastClaimedEpoch; epoch <= _pool.currentBurnEpoch(); epoch++) {
            
            // track epochs that have already been claimed
            if (_rewardsManager.isEpochClaimed(tokenId_, epoch)) {
                rewardsAlreadyClaimed[epoch] = _rewardsManager.rewardsClaimed(epoch);
            }
            
            // total the rewards earned pre action
            totalRewardsEarnedPreAction  += _rewardsManager.rewardsClaimed(epoch) + _rewardsManager.updateRewardsClaimed(epoch);
        }
 
        try _rewardsManager.unstake(tokenId_) {

            // check token was transferred from rewards contract to actor
            require(_positionManager.ownerOf(tokenId_) == _actor, "actor should receive ownership after unstaking");

            // actor should receive tokenId, positionManager loses ownership
            tokenIdsByActor[address(_actor)].add(tokenId_);
            tokenIdsByActor[address(_rewardsManager)].remove(tokenId_);

            // balance changes
            uint256 actorAjnaGain = _ajna.balanceOf(_actor) - actorAjnaBalanceBeforeClaim;

            // loop over all epochs that were claimed
            uint256 totalRewardsEarnedPostAction;
            for (uint256 epoch = preActionLastClaimedEpoch; epoch <= _pool.currentBurnEpoch(); epoch++) {

                if (rewardsAlreadyClaimed[epoch] != 0) {
                    require(rewardsAlreadyClaimed[epoch] == _rewardsManager.rewardsClaimed(epoch), 
                    "RW9: staker has claimed rewards from the same epoch twice"); 
                }

                // total rewards earned post action
                totalRewardsEarnedPostAction += _rewardsManager.rewardsClaimed(epoch) + _rewardsManager.updateRewardsClaimed(epoch);

                // reset staking and updating rewards earned in epoch
                rewardsClaimedPerEpoch[epoch]       = _rewardsManager.rewardsClaimed(epoch);
                updateRewardsClaimedPerEpoch[epoch] = _rewardsManager.updateRewardsClaimed(epoch);
            }

            require(actorAjnaGain <= totalRewardsEarnedPostAction - totalRewardsEarnedPreAction,
            "RW6: actor's total claimed is greater than rewards earned");

            require(actorAjnaGain == contractAjnaBalanceBeforeClaim - _ajna.balanceOf(address(_rewardsManager)),
            "RW7: ajna deducted from rewardsManager doesn't equal ajna gained by actor");

            (address owner, address pool, uint256 lastClaimedEpoch) = _rewardsManager.getStakeInfo(tokenId_);
            require(owner == address(0) && pool == address(0) && lastClaimedEpoch == 0,
            "RW8: stake info is not reset after unstake");

        } catch (bytes memory err) {
            _ensureRewardsManagerError(err);
        }
    }

    function _updateExchangeRate(
        uint256[] memory indexes_
    ) internal {
        numberOfCalls['UBRewardsHandler.exchangeRate']++;

        // track balances
        uint256 actorAjnaBalanceBeforeClaim    = _ajna.balanceOf(_actor);
        uint256 contractAjnaBalanceBeforeClaim = _ajna.balanceOf(address(_rewardsManager));

        try _rewardsManager.updateBucketExchangeRatesAndClaim(address(_pool), keccak256("ERC20_NON_SUBSET_HASH"), indexes_) {

            uint256 actorAjnaGain = _ajna.balanceOf(_actor) - actorAjnaBalanceBeforeClaim;
            require(actorAjnaGain == contractAjnaBalanceBeforeClaim - _ajna.balanceOf(address(_rewardsManager)),
            "RW7: ajna deducted from rewardsManager doesn't equal ajna gained by actor");

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
        for (uint256 epoch = preActionLastClaimedEpoch; epoch <= _pool.currentBurnEpoch(); epoch++) {
            
            // track epochs that have already been claimed
            if (_rewardsManager.isEpochClaimed(tokenId_, epoch)) {
                rewardsAlreadyClaimed[epoch] = _rewardsManager.rewardsClaimed(epoch);
            }
            
            // total the rewards earned pre action
            totalRewardsEarnedPreAction += _rewardsManager.rewardsClaimed(epoch);
        }

        try _rewardsManager.claimRewards(tokenId_, epoch_, 0) {

            // balance changes
            uint256 actorAjnaGain = _ajna.balanceOf(_actor) - actorAjnaBalanceBeforeClaim;

            // loop over all epochs that were claimed
            uint256 totalRewardsEarnedPostAction;
            for (uint256 epoch = preActionLastClaimedEpoch; epoch <= _pool.currentBurnEpoch(); epoch++) {

                if (rewardsAlreadyClaimed[epoch] != 0) {
                    require(rewardsAlreadyClaimed[epoch] == _rewardsManager.rewardsClaimed(epoch), 
                    "RW9: staker has claimed rewards from the same epoch twice"); 
                }

                // total staking rewards earned post action
                totalRewardsEarnedPostAction += _rewardsManager.rewardsClaimed(epoch);

                // reset staking rewards earned in epoch
                rewardsClaimedPerEpoch[epoch] = _rewardsManager.rewardsClaimed(epoch);
            }

            require(actorAjnaGain <= totalRewardsEarnedPostAction - totalRewardsEarnedPreAction,
            "RW6: actor's total claimed is greater than rewards earned");

            require(actorAjnaGain == contractAjnaBalanceBeforeClaim - _ajna.balanceOf(address(_rewardsManager)),
            "RW7: ajna deducted from rewardsManager doesn't equal ajna gained by actor");

        } catch (bytes memory err) {
            _ensureRewardsManagerError(err);
        }
    }

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
