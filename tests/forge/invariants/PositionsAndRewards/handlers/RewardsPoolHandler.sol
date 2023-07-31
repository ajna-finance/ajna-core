// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.18;

import { Strings } from '@openzeppelin/contracts/utils/Strings.sol';

import { Pool } from 'src/base/Pool.sol';

import { PositionPoolHandler }         from './PositionPoolHandler.sol';
import { BaseRewardsPoolHandler } from './BaseRewardsPoolHandler.sol';

abstract contract RewardsPoolHandler is BaseRewardsPoolHandler, PositionPoolHandler {

    /*******************************/
    /*** Rewards Test Functions ***/
    /*******************************/

    function stake(
        uint256 actorIndex_,
        uint256 bucketIndex_,
        uint256 amountToAdd_,
        uint256 skippedTime_
    ) external useRandomActor(actorIndex_) useRandomLenderBucket(bucketIndex_) useTimestamps skipTime(skippedTime_) writeLogs writePositionLogs writeRewardsLogs {
        numberOfCalls['BRewardsHandler.stake']++;
        // Pre action
        (uint256 tokenId, uint256[] memory indexes) = _preStake(_lenderBucketIndex, amountToAdd_);

        // NFT doesn't have a position associated with it, return
        if (indexes.length == 0) return;

        // Action phase
        _stake(tokenId);
    }

    function unstake(
        uint256 actorIndex_,
        uint256 bucketIndex_,
        uint256 amountToAdd_,
        uint256 skippedTime_,
        uint256 numberOfEpochs_
    ) external useRandomActor(actorIndex_) useRandomLenderBucket(bucketIndex_) useTimestamps skipTime(skippedTime_) writeLogs writePositionLogs writeRewardsLogs {
        numberOfCalls['BRewardsHandler.unstake']++;
        // Pre action
        (uint256 tokenId, uint256[] memory indexes) = _preUnstake(
            _lenderBucketIndex,
            amountToAdd_,
            numberOfEpochs_
        );

        // NFT doesn't have a position associated with it, return
        if (indexes.length == 0) return;
        
        // if rewards exceed contract balance tx will revert, return
        uint256 reward = _rewardsManager.calculateRewards(tokenId, _pool.currentBurnEpoch());
        if (reward > _ajna.balanceOf(address(_rewardsManager))) return;

        // Action phase
        _unstake(tokenId);
    }

    function emergencyUnstake(
        uint256 actorIndex_,
        uint256 bucketIndex_,
        uint256 amountToAdd_,
        uint256 skippedTime_,
        uint256 numberOfEpochs_
    ) external useRandomActor(actorIndex_) useRandomLenderBucket(bucketIndex_) useTimestamps skipTime(skippedTime_) writeLogs writePositionLogs writeRewardsLogs {
        numberOfCalls['BRewardsHandler.emergencyUnstake']++;
        
        // Pre action
        (uint256 tokenId, uint256[] memory indexes) = _preUnstake(
            _lenderBucketIndex,
            amountToAdd_,
            numberOfEpochs_
        );

        // NFT doesn't have a position associated with it, return
        if (indexes.length == 0) return;
        
        // Action phase
        _emergencyUnstake(tokenId);
    }

    function updateExchangeRate(
        uint256 actorIndex_,
        uint256 bucketIndex_,
        uint256 amountToAdd_,
        uint256 skippedTime_
    ) external useRandomActor(actorIndex_) useRandomLenderBucket(bucketIndex_) useTimestamps skipTime(skippedTime_) writeLogs writePositionLogs writeRewardsLogs {
        numberOfCalls['BRewardsHandler.updateRate']++;

        // Pre action //
        uint256[] memory indexes = getBucketIndexesWithPosition(address(_pool));

        // if there are no existing positions, create a position at a a random index
        if (indexes.length == 0) {
           (, indexes) = _getStakedPosition(_lenderBucketIndex, amountToAdd_);

            // NFT doesn't have a position associated with it, return
            if (indexes.length == 0) return;
        }

        // Action phase
        _updateExchangeRate(indexes);
    }

    function claimRewards(
        uint256 actorIndex_,
        uint256 bucketIndex_,
        uint256 amountToAdd_,
        uint256 skippedTime_,
        uint256 numberOfEpochs_
    ) external useRandomActor(actorIndex_) useRandomLenderBucket(bucketIndex_) useTimestamps skipTime(skippedTime_) writeLogs writePositionLogs writeRewardsLogs {
        numberOfCalls['BRewardsHandler.claimRewards']++;

        // Pre action //
        (uint256 tokenId, uint256[] memory indexes) = _preUnstake(
            _lenderBucketIndex,
            amountToAdd_,
            numberOfEpochs_
        );

        // NFT doesn't have a position associated with it, return
        if (indexes.length == 0) return;

        // Action phase
        _claimRewards(tokenId, _pool.currentBurnEpoch());
    }

    /********************************/
    /*** Logging Helper Functions ***/
    /********************************/

    modifier writeRewardsLogs() {
        // Verbosity of Log file for rewardsManager
        logVerbosity = uint256(vm.envOr("LOGS_VERBOSITY_REWARDS", uint256(0)));

        if (logVerbosity != 0) logToFile = true;

        _;

        if (logVerbosity > 0) {
            printInNextLine("== RewardsManager Details ==");
            writeStakedActorLogs();
            writeEpochRewardLogs();
            printInNextLine("=======================");
        }
    }

    function writeStakedActorLogs() internal {

        for (uint256 i = 0; i < actors.length; i++) {

            uint256[] memory tokenIds = getStakedTokenIdsByActor(actors[i]);

            if (tokenIds.length != 0) {
                string memory actorStr = string(abi.encodePacked("Actor ", Strings.toString(i), " staked tokenIds: "));

                string memory tokenIdStr;
                for (uint256 k = 0; k < tokenIds.length; k++) {
                    tokenIdStr = string(abi.encodePacked(tokenIdStr, " ", Strings.toString(tokenIds[k])));
                }

                printLine(string.concat(actorStr,tokenIdStr)); 
            }
        }
    }

    function writeEpochRewardLogs() internal {
        // loop over pools
        for (uint256 i = 0; i < _pools.length; i++) {
            address pool = _pools[i];
            printLine(string.concat("Pool: ", Strings.toHexString(uint160(pool), 20)));
            uint256 epoch = 0;
            uint256 currentPoolEpoch = Pool(pool).currentBurnEpoch();
            if (currentPoolEpoch != 0) {
                while (epoch <= currentPoolEpoch) {
                    printLine("");
                    printLog("Epoch = ", epoch);
                    printLog("Claimed Staking Rewards  = ", rewardsClaimedPerEpoch[pool][epoch]);
                    printLog("Claimed Updating Rewards = ", updateRewardsClaimedPerEpoch[pool][epoch]);

                    epoch++;
                }
            }
        }
        
    }
}
