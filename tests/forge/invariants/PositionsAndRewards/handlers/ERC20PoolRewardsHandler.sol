// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.18;

import '@openzeppelin/contracts/utils/structs/EnumerableSet.sol';

import { PositionManager }              from 'src/PositionManager.sol';
import { RewardsManager }               from 'src/RewardsManager.sol';

import { UnboundedERC20PoolRewardsHandler } from './unbounded/UnboundedERC20PoolRewardsHandler.sol';
import { ReserveERC20PoolHandler }          from '../../ERC20Pool/handlers/ReserveERC20PoolHandler.sol';
import { BaseERC20PoolPositionHandler }     from './BaseERC20PoolPositionHandler.sol';

contract ERC20PoolRewardsHandler is UnboundedERC20PoolRewardsHandler, BaseERC20PoolPositionHandler, ReserveERC20PoolHandler {

    constructor(
        address rewards_,
        address positions_,
        address pool_,
        address ajna_,
        address quote_,
        address collateral_,
        address poolInfo_,
        uint256 numOfActors_,
        address testContract_
    ) ReserveERC20PoolHandler(pool_, ajna_, quote_, collateral_, poolInfo_, numOfActors_, testContract_) {

        // Position manager
        _positionManager = PositionManager(positions_); 

        // Rewards manager
        _rewardsManager = RewardsManager(rewards_);
    }

    /*******************************/
    /*** Rewards Test Functions ***/
    /*******************************/

    function stake(
        uint256 actorIndex_,
        uint256 bucketIndex_,
        uint256 amountToAdd_,
        uint256 skippedTime_
    ) external useRandomActor(actorIndex_) useRandomLenderBucket(bucketIndex_) useTimestamps skipTime(skippedTime_) {
        numberOfCalls['BRewardsHandler.stake']++;
        // Pre action
        (uint256 tokenId, uint256[] memory indexes) = _preStake(_lenderBucketIndex, amountToAdd_);

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
    ) external useRandomActor(actorIndex_) useRandomLenderBucket(bucketIndex_) useTimestamps skipTime(skippedTime_) {
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
    ) external useRandomActor(actorIndex_) useRandomLenderBucket(bucketIndex_) useTimestamps skipTime(skippedTime_) {
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
    ) external useRandomActor(actorIndex_) useRandomLenderBucket(bucketIndex_) useTimestamps skipTime(skippedTime_) {
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
    ) external useRandomActor(actorIndex_) useRandomLenderBucket(bucketIndex_) useTimestamps skipTime(skippedTime_) {
        numberOfCalls['BRewardsHandler.claimRewards']++;

        // Pre action //
        (uint256 tokenId, uint256[] memory indexes_) = _preUnstake(
            _lenderBucketIndex,
            amountToAdd_,
            numberOfEpochs_,
            bucketSubsetToUpdate_
        );

        // NFT doesn't have a position associated with it, return
        if (indexes_.length == 0) return;

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
        (tokenId_, indexes_) = _getStakedPosition(bucketIndex_, amountToAdd_);

        _advanceEpochRewardStakers(
            amountToAdd_,
            indexes_,
            numberOfEpochs_,
            bucketSubsetToUpdate_
        );
    }

    function _advanceEpochRewardStakers(
        uint256 amountToAdd_,
        uint256[] memory indexes_,
        uint256 numberOfEpochs_,
        uint256 bucketSubsetToUpdate_
    ) internal {

        numberOfEpochs_ = constrictToRange(numberOfEpochs_, 1, vm.envOr("MAX_EPOCH_ADVANCE", uint256(5)));

        for (uint256 epoch = 0; epoch <= numberOfEpochs_; epoch ++) {
            // draw some debt and then repay after some times to increase pool earning / reserves 
            (, uint256 claimableReserves, , ) = _pool.reservesInfo();
            if (claimableReserves == 0) {
                uint256 amountToBorrow = _preDrawDebt(amountToAdd_);
                _drawDebt(amountToBorrow);

            
                _repayDebt(type(uint256).max);
            }

            skip(20 days); // epochs are spaced a minimum of 14 days apart

            (, claimableReserves, , ) = _pool.reservesInfo();

            _kickReserveAuction();

            // skip time for price to decrease, large price decrease reduces chances of rewards exceeding rewards contract balance
            skip(60 hours);

            uint256 boundedTakeAmount = constrictToRange(amountToAdd_, claimableReserves / 2, claimableReserves);
            _takeReserves(boundedTakeAmount);

            // exchange rates must be updated so that rewards can be claimed
            indexes_ = _randomizeExchangeRateIndexes(indexes_, bucketSubsetToUpdate_);
            if (indexes_.length != 0) { _updateExchangeRate(indexes_); }
        }
    }

    function _randomizeExchangeRateIndexes(
        uint256[] memory indexes_,
        uint256 bucketSubsetToUpdate_
    ) internal view returns (uint256[] memory boundBuckets_) {
        
        uint256 boundIndexes = constrictToRange(bucketSubsetToUpdate_, 0, indexes_.length);
        boundBuckets_ = new uint256[](boundIndexes);

        if (boundBuckets_.length !=0) {
            for (uint256 i = 0; i < boundIndexes; i++) {
                boundBuckets_[i] = indexes_[i];
            }
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
}
