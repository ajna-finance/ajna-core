
// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.14;

import '@openzeppelin/contracts/utils/structs/EnumerableSet.sol';
import { Strings } from '@openzeppelin/contracts/utils/Strings.sol';

import { IPositionManagerOwnerActions } from 'src/interfaces/position/IPositionManagerOwnerActions.sol';
import { _depositFeeRate }   from 'src/libraries/helpers/PoolHelper.sol';
import { Maths }             from "src/libraries/internal/Maths.sol";

import { BaseHandler }         from '../../../base/handlers/unbounded/BaseHandler.sol';

import { PositionManager }   from 'src/PositionManager.sol';

/**
 *  @dev this contract manages multiple lenders
 *  @dev methods in this contract are called in random order
 *  @dev randomly selects a lender contract to make a txn
 */ 
abstract contract BasePositionsHandler is BaseHandler {

    PositionManager internal _positions;

    // positions invariant test state
    mapping(uint256 => EnumerableSet.UintSet) internal tokenIdsByBucketIndex;
    EnumerableSet.UintSet internal bucketIndexesWithPosition;
    EnumerableSet.UintSet internal tokenIdsMinted;
    mapping(uint256 => uint256) internal bucketIndexToPreActionActorLps; // to track LP changes
    mapping(uint256 => uint256) internal bucketIndexToPreActionPosLps; // to track LP changes
    mapping(uint256 => uint256) internal bucketIndexToPreActionDepositTime;
    using EnumerableSet for EnumerableSet.UintSet;

    function _buildActors(uint256 noOfActors_) internal returns(address[] memory) {
        address[] memory actorsAddress = new address[](noOfActors_);

        for (uint i = 0; i < noOfActors_; i++) {
            address actor = makeAddr(string(abi.encodePacked("Actor", Strings.toString(i))));
            actorsAddress[i] = actor;

            vm.startPrank(actor);

            _quote.mint(actor, 1e45);
            _quote.approve(address(_pool), 1e45);

            vm.stopPrank();
        }

        return actorsAddress;
    }

    function getBucketIndexesWithPosition() public view returns(uint256[] memory) {
        return bucketIndexesWithPosition.values();
    }

    function getTokenIdsByBucketIndex(uint256 bucketIndex_) public view returns(uint256[] memory) {
        return tokenIdsByBucketIndex[bucketIndex_].values();
    }

    function getTokenIds() public view returns(uint256[] memory) {
        return tokenIdsMinted.values();
    }



}