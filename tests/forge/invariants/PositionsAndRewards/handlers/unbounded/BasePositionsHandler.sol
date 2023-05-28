
// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.18;

import '@openzeppelin/contracts/utils/structs/EnumerableSet.sol';
import { Strings } from '@openzeppelin/contracts/utils/Strings.sol';

import { IPositionManagerOwnerActions } from 'src/interfaces/position/IPositionManagerOwnerActions.sol';
import { _depositFeeRate }   from 'src/libraries/helpers/PoolHelper.sol';
import { Maths }             from "src/libraries/internal/Maths.sol";

import { BaseERC20PoolHandler }         from '../../../ERC20Pool/handlers/unbounded/BaseERC20PoolHandler.sol';

import { PositionManager }   from 'src/PositionManager.sol';
import { RewardsManager }    from 'src/RewardsManager.sol';
import { ERC20Pool }         from 'src/ERC20Pool.sol';

/**
 *  @dev this contract manages multiple lenders
 *  @dev methods in this contract are called in random order
 *  @dev randomly selects a lender contract to make a txn
 */ 
abstract contract BasePositionsHandler is BaseERC20PoolHandler {

    PositionManager internal _position;
    RewardsManager  internal _rewards;

    // positions invariant test state
    // used for PM1_PM2_PM3 tracking
    mapping(uint256 => EnumerableSet.UintSet) internal tokenIdsByBucketIndex;
    EnumerableSet.UintSet internal bucketIndexesWithPosition;

    // used for removing all CT and QT to reset exchange rate
    mapping(uint256 => address) internal actorByTokenId;
    mapping(uint256 => EnumerableSet.UintSet) internal bucketIndexesByTokenId;

    EnumerableSet.UintSet internal stakedTokenIds;

    EnumerableSet.UintSet internal tokenIdsMinted;
    // used to track LP changes
    mapping(uint256 => uint256) internal bucketIndexToActorPositionManLps;
    mapping(uint256 => uint256) internal bucketIndexToPositionManPoolLps;
    mapping(uint256 => uint256) internal bucketIndexToActorPoolLps;
    mapping(uint256 => uint256) internal bucketIndexToDepositTime;


    using EnumerableSet for EnumerableSet.UintSet;

    function getBucketIndexesWithPosition() public view returns(uint256[] memory) {
        return bucketIndexesWithPosition.values();
    }

    function getTokenIdsByBucketIndex(uint256 bucketIndex_) public view returns(uint256[] memory) {
        return tokenIdsByBucketIndex[bucketIndex_].values();
    }

    function getBucketIndexesByTokenId(uint256 tokenId_) public view returns(uint256[] memory) {
        return bucketIndexesByTokenId[tokenId_].values();
    }

    function getTokenIds() public view returns(uint256[] memory) {
        return tokenIdsMinted.values();
    }
}