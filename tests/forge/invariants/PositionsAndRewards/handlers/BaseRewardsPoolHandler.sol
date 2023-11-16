// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.18;

import { Strings } from '@openzeppelin/contracts/utils/Strings.sol';

import { BasePositionPoolHandler }     from './BasePositionPoolHandler.sol';
import { UnboundedRewardsPoolHandler } from './unbounded/UnboundedRewardsPoolHandler.sol';

abstract contract BaseRewardsPoolHandler is UnboundedRewardsPoolHandler, BasePositionPoolHandler {

    /*******************************/
    /*** Prepare Tests Functions ***/
    /*******************************/

    function _preStake(
        uint256 bucketIndex_,
        uint256 amountToAdd_
    ) internal returns (uint256 tokenId_, uint256[] memory indexes_) {

        // retreive or create a NFT position
        (tokenId_, indexes_) = _getNFTPosition(bucketIndex_, amountToAdd_);

        // Approve rewards contract to transfer token
        _positionManager.approve(address(_rewardsManager), tokenId_); 
    }

    function _preUnstake(
        uint256 bucketIndex_,
        uint256 amountToAdd_,
        uint256 numberOfEpochs_
    ) internal returns (uint256 tokenId_, uint256[] memory indexes_) {
        (tokenId_, indexes_) = _getStakedPosition(bucketIndex_, amountToAdd_);

        if (indexes_.length != 0) {
            _advanceEpochRewardStakers(
                amountToAdd_,
                indexes_,
                numberOfEpochs_
            );
        }
    }

    function _getStakedPosition(
        uint256 bucketIndex_,
        uint256 amountToAdd_
    ) internal returns (uint256 tokenId_, uint256[] memory indexes_) {

        // Check for exisiting staked positions in RewardsManager
        uint256[] memory tokenIds = getStakedTokenIdsByActor(_actor);

        if (tokenIds.length != 0 ) {
            // use existing position NFT
            tokenId_ = tokenIds[0];
            indexes_ = getBucketIndexesByTokenId(tokenId_);
            updateTokenAndPoolAddress(_positionManager.poolKey(tokenId_));

            // create position in NFT if not already there
            if (indexes_.length == 0) {
                indexes_ = _getPosition(bucketIndex_, amountToAdd_);
                _memorializePositions(tokenId_, indexes_);
            }
            
        } else {
            // retreive or create a NFT position
            (tokenId_, indexes_) = _getNFTPosition(bucketIndex_, amountToAdd_);
            updateTokenAndPoolAddress(_positionManager.poolKey(tokenId_));

            // approve rewards contract to transfer token
            _positionManager.approve(address(_rewardsManager), tokenId_);

            // stake the position
            _stake(tokenId_);
        }
    }
}
