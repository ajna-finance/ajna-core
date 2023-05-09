// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.14;

import '@openzeppelin/contracts/utils/structs/EnumerableSet.sol';

import { PositionManager }              from 'src/PositionManager.sol';
import { RewardsManager }               from 'src/RewardsManager.sol';

import { UnboundedRewardsHandler } from './unbounded/UnboundedRewardsHandler.sol';

import { ReserveERC20PoolHandler } from '../../ERC20Pool/handlers/ReserveERC20PoolHandler.sol';
import { PositionHandlerAbstract } from './PositionHandlerAbstract.sol';

contract RewardsHandler is UnboundedRewardsHandler, PositionHandlerAbstract, ReserveERC20PoolHandler {

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
        _position = PositionManager(positions_); 

        // Rewards manager
        _rewards = RewardsManager(rewards_);

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
        uint256 tokenId = _preStake(bucketIndex_, amountToAdd_);
        
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
        uint256 tokenId = _preUnstake(bucketIndex_, amountToAdd_);
        
        // Action phase
        _unstake(tokenId);


        // Post action
        // check token was transferred from rewards contract to actor
        assertEq(_position.ownerOf(tokenId), _actor);
    }


    /*******************************/
    /*** Rewards Tests Functions ***/
    /*******************************/

    function _preStake(
        uint256 bucketIndex_,
        uint256 amountToAdd_
    ) internal returns (uint256) {

        (uint256 tokenId, uint256[] memory indexes) = _preMemorializePositions(bucketIndex_, amountToAdd_);
        
        _memorializePositions(tokenId, indexes);

        // Approve rewards contract to transfer token
        _position.approve(address(_rewards), tokenId);
        
        return tokenId;
    }

    function _preUnstake(
        uint256 bucketIndex_,
        uint256 amountToAdd_
    ) internal returns (uint256 tokenId_) {

        // Only way to check if the actor has a NFT position or a staked position is tracking events
        // Create a staked position
        tokenId_ = _preStake(bucketIndex_, amountToAdd_);
        _stake(tokenId_);

        //TODO: Perform multiple randomized reserve auctions to ensure staked position has rewards over multiple epochs 
        // trigger reserve auction
        _kickReserveAuction(); 

        uint256 boundedAmount = _preTakeReserves(amountToAdd_);
        _takeReserves(boundedAmount);
    }

}
