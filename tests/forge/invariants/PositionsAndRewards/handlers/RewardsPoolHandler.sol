// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.18;

import { Strings } from '@openzeppelin/contracts/utils/Strings.sol';

import { PositionPoolHandler }         from './PositionPoolHandler.sol';
import { UnboundedRewardsPoolHandler } from './unbounded/UnboundedRewardsPoolHandler.sol';

abstract contract RewardsPoolHandler is UnboundedRewardsPoolHandler, PositionPoolHandler {

    /*******************************/
    /*** Rewards Test Functions ***/
    /*******************************/

    function stake(
        uint256 actorIndex_,
        uint256 bucketIndex_,
        uint256 amountToAdd_,
        uint256 skippedTime_
    ) external useRandomActor(actorIndex_) useRandomLenderBucket(bucketIndex_) useTimestamps skipTime(skippedTime_) writePositionLogs writeRewardsLogs {
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
        uint256 numberOfEpochs_,
        uint256 bucketSubsetToUpdate_
    ) external useRandomActor(actorIndex_) useRandomLenderBucket(bucketIndex_) useTimestamps skipTime(skippedTime_) writePositionLogs writeRewardsLogs {
        numberOfCalls['BRewardsHandler.unstake']++;
        // Pre action
        (uint256 tokenId, uint256[] memory indexes) = _preUnstake(
            _lenderBucketIndex,
            amountToAdd_,
            numberOfEpochs_,
            bucketSubsetToUpdate_
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
        uint256 numberOfEpochs_,
        uint256 bucketSubsetToUpdate_
    ) external useRandomActor(actorIndex_) useRandomLenderBucket(bucketIndex_) useTimestamps skipTime(skippedTime_) writePositionLogs writeRewardsLogs {
        numberOfCalls['BRewardsHandler.emergencyUnstake']++;
        
        // Pre action
        (uint256 tokenId, uint256[] memory indexes) = _preUnstake(
            _lenderBucketIndex,
            amountToAdd_,
            numberOfEpochs_,
            bucketSubsetToUpdate_
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
    ) external useRandomActor(actorIndex_) useRandomLenderBucket(bucketIndex_) useTimestamps skipTime(skippedTime_) writePositionLogs writeRewardsLogs {
        numberOfCalls['BRewardsHandler.updateRate']++;

        // Pre action //
        uint256[] memory indexes = getBucketIndexesWithPosition();

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
        uint256 numberOfEpochs_,
        uint256 bucketSubsetToUpdate_
    ) external useRandomActor(actorIndex_) useRandomLenderBucket(bucketIndex_) useTimestamps skipTime(skippedTime_) writePositionLogs writeRewardsLogs {
        numberOfCalls['BRewardsHandler.claimRewards']++;

        // Pre action //
        (uint256 tokenId, uint256[] memory indexes) = _preUnstake(
            _lenderBucketIndex,
            amountToAdd_,
            numberOfEpochs_,
            bucketSubsetToUpdate_
        );

        // NFT doesn't have a position associated with it, return
        if (indexes.length == 0) return;

        // Action phase
        _claimRewards(tokenId, _pool.currentBurnEpoch());
    }

    /*******************************/
    /*** Prepare Tests Functions ***/
    /*******************************/

    function _preStake(
        uint256 bucketIndex_,
        uint256 amountToAdd_
    ) internal returns (uint256 tokenId_, uint256[] memory indexes_) {

        // retreive or create a NFT position
        (tokenId_, indexes_)= _getNFTPosition(bucketIndex_, amountToAdd_);

        // Approve rewards contract to transfer token
        _positionManager.approve(address(_rewardsManager), tokenId_); 
    }

    function _preUnstake(
        uint256 bucketIndex_,
        uint256 amountToAdd_,
        uint256 numberOfEpochs_,
        uint256 bucketSubsetToUpdate_
    ) internal returns (uint256 tokenId_, uint256[] memory indexes_) {
        (tokenId_, indexes_)= _getStakedPosition(bucketIndex_, amountToAdd_);

        if (indexes_.length != 0) {
            _advanceEpochRewardStakers(
                amountToAdd_,
                indexes_,
                numberOfEpochs_,
                bucketSubsetToUpdate_
            );
        }
    }

    function _getStakedPosition(
        uint256 bucketIndex_,
        uint256 amountToAdd_
    ) internal returns (uint256 tokenId_, uint256[] memory indexes_) {

        // Check for exisiting staked positions in RewardsManager
        uint256[] memory tokenIds = getStakedTokenIdsByActor(address(_actor));

        if (tokenIds.length != 0 ) {
            // use existing position NFT
            tokenId_ = tokenIds[0];
            indexes_ = getBucketIndexesByTokenId(tokenId_);
        } else {
            // retreive or create a NFT position
            (tokenId_, indexes_)= _getNFTPosition(bucketIndex_, amountToAdd_);

            // approve rewards contract to transfer token
            _positionManager.approve(address(_rewardsManager), tokenId_);

            // stake the position
            _stake(tokenId_);
        }
    } 

    modifier writeRewardsLogs() {
        _;
        if (logFileVerbosity > 6) {
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
        uint256 epoch = 0;
        if (_pool.currentBurnEpoch() != 0) {
            while (epoch <= _pool.currentBurnEpoch()) {
                printLine("");
                printLog("Epoch = ", epoch);
                printLog("Claimed Staking Rewards  = ", rewardsClaimedPerEpoch[epoch]);
                printLog("Claimed Updating Rewards = ", updateRewardsClaimedPerEpoch[epoch]);

                epoch++;
            }
        }
    }
}
