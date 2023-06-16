// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.18;

import '@openzeppelin/contracts/utils/structs/EnumerableSet.sol';

import { PositionManager }              from 'src/PositionManager.sol';
import { RewardsManager }               from 'src/RewardsManager.sol';

import { UnboundedRewardsHandler } from './unbounded/UnboundedRewardsHandler.sol';

import { ReserveERC20PoolHandler }  from '../../ERC20Pool/handlers/ReserveERC20PoolHandler.sol';
import { BaseERC20PoolPositionHandler } from './BaseERC20PoolPositionHandler.sol';

contract RewardsHandler is UnboundedRewardsHandler, BaseERC20PoolPositionHandler, ReserveERC20PoolHandler {

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
        (uint256 tokenId,) = _preStake(_lenderBucketIndex, amountToAdd_);

        // Action phase
        _stake(tokenId);
    }

    function unstake(
        uint256 actorIndex_,
        uint256 bucketIndex_,
        uint256 amountToAdd_,
        uint256 skippedTime_
    ) external useRandomActor(actorIndex_) useRandomLenderBucket(bucketIndex_) useTimestamps skipTime(skippedTime_) {
        numberOfCalls['BRewardsHandler.unstake']++;
        // Pre action
        uint256 tokenId = _preUnstake(_lenderBucketIndex, amountToAdd_);
        
        // if rewards exceed contract balance tx will revert, return
        uint256 reward = _rewardsManager.calculateRewards(tokenId, _pool.currentBurnEpoch());
        if (reward > _ajna.balanceOf(address(_rewardsManager))) return;

        // Action phase
        _unstake(tokenId);
    }

    function updateExchangeRate(
        uint256 actorIndex_,
        uint256 bucketIndex_,
        uint256 skippedTime_
    ) external useRandomActor(actorIndex_) useRandomLenderBucket(bucketIndex_) useTimestamps skipTime(skippedTime_) {
        numberOfCalls['BRewardsHandler.updateRate']++;

        // Pre action //
        uint256[] memory indexes = _preUpdateExchangeRate(_lenderBucketIndex);

        // Action phase
        _updateExchangeRate(indexes);
    }

    function claimRewards(
        uint256 actorIndex_,
        uint256 bucketIndex_,
        uint256 amountToAdd_,
        uint256 skippedTime_
    ) external useRandomActor(actorIndex_) useRandomLenderBucket(bucketIndex_) useTimestamps skipTime(skippedTime_) {
        numberOfCalls['BRewardsHandler.claimRewards']++;

        // Pre action //
        uint256 tokenId = _preUnstake(_lenderBucketIndex, amountToAdd_);

        uint256 currentEpoch = _pool.currentBurnEpoch();

        // Action phase
        _claimRewards(tokenId, currentEpoch);
    }

    /*******************************/
    /*** Rewards Tests Functions ***/
    /*******************************/

    function _preStake(
        uint256 bucketIndex_,
        uint256 amountToAdd_
    ) internal returns (uint256 tokenId_, uint256[] memory indexes_) {

        (tokenId_, indexes_) = _preMemorializePositions(bucketIndex_, amountToAdd_);
        
        _memorializePositions(tokenId_, indexes_);

        // Approve rewards contract to transfer token
        _positionManager.approve(address(_rewardsManager), tokenId_);
        
    }

    function _preUnstake(
        uint256 bucketIndex_,
        uint256 amountToAdd_
    ) internal returns (uint256 tokenId_) {

        // TODO: Check if the actor has a NFT position or a staked position is tracking events
        
        // Create a staked position
        uint256[] memory indexes;
        (tokenId_, indexes)= _preStake(bucketIndex_, amountToAdd_);
        _stake(tokenId_);

        _advanceEpochRewardStakers(amountToAdd_, indexes);
    }

    function _advanceEpochRewardStakers(
        uint256 amountToAdd_,
        uint256[] memory indexes_
    ) internal {

        // draw some debt and then repay after some times to increase pool earning / reserves 
        (, uint256 claimableReserves, , ) = _pool.reservesInfo();
        if (claimableReserves == 0) {
            uint256 amountToBorrow = _preDrawDebt(amountToAdd_);
            _drawDebt(amountToBorrow);

            skip(20 days); // epochs are spaced a minimum of 14 days apart
        
            _repayDebt(type(uint256).max);
        }

        (, claimableReserves, , ) = _pool.reservesInfo();

        _kickReserveAuction();

        // skip time for price to decrease, large price decrease reduces chances of rewards exceeding rewards contract balance
        skip(60 hours);

        uint256 boundedTakeAmount = constrictToRange(amountToAdd_, claimableReserves / 2, claimableReserves);
        _takeReserves(boundedTakeAmount);

        // exchange rates must be updated so that rewards can be checked
        _rewardsManager.updateBucketExchangeRatesAndClaim(address(_pool), keccak256("ERC20_NON_SUBSET_HASH"), indexes_);

    }

    function _preUpdateExchangeRate(
        uint256 bucketIndex_
    ) internal pure returns (uint256[] memory indexes_) {
        indexes_ = new uint256[](1);
        indexes_[0] = bucketIndex_;
    }
}
