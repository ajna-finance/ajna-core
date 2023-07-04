// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.18;

import '@std/Test.sol';
import '@openzeppelin/contracts/utils/structs/EnumerableSet.sol';

import { PositionManager } from 'src/PositionManager.sol';
import { RewardsManager }  from 'src/RewardsManager.sol';

/**
 *  @dev this contract manages multiple lenders
 *  @dev methods in this contract are called in random order
 *  @dev randomly selects a lender contract to make a txn
 */ 
abstract contract UnboundedBasePositionHandler is Test {

    PositionManager internal _positionManager;
    RewardsManager  internal _rewardsManager;

    bytes32 internal _poolHash;

    uint256 MAX_AJNA_AMOUNT = vm.envOr("MAX_AJNA_AMOUNT_ERC20", uint256(100_000_000 * 1e18));

    // positionManager & rewardsManager
    EnumerableSet.UintSet internal bucketIndexesWithPosition;
    mapping(uint256 => EnumerableSet.UintSet) internal bucketIndexesByTokenId;

    // positionManager
    mapping(uint256 => EnumerableSet.UintSet) internal tokenIdsByBucketIndex;
    mapping(address => EnumerableSet.UintSet) internal tokenIdsByActor;
    // used to track changes in `_redeemPositions()` and `_memorializePositions()`
    mapping(uint256 => uint256) internal actorLpsBefore;
    mapping(uint256 => uint256) internal posManLpsBefore;
    mapping(uint256 => uint256) internal bucketIndexToDepositTime;

    // rewardsManager
    mapping(address => EnumerableSet.UintSet) internal stakedTokenIdsByActor;
    mapping(uint256 => uint256) public rewardsClaimedPerEpoch;       // staking rewards per epoch
    mapping(uint256 => uint256) public updateRewardsClaimedPerEpoch; // updating rewards per epoch

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

    function getTokenIdsByActor(address actor_) public view returns(uint256[] memory) {
        return tokenIdsByActor[actor_].values();
    }

    function getStakedTokenIdsByActor(address actor_) public view returns(uint256[] memory) {
        return stakedTokenIdsByActor[actor_].values();
    }

    function _ensurePositionsManagerError(bytes memory err_) internal pure {
        bytes32 err = keccak256(err_);

        require(
            err == keccak256(abi.encodeWithSignature("AllowanceTooLow()")) ||
            err == keccak256(abi.encodeWithSignature("BucketBankrupt()")) ||
            err == keccak256(abi.encodeWithSignature("DeployWithZeroAddress()")) ||
            err == keccak256(abi.encodeWithSignature("LiquidityNotRemoved()")) ||
            err == keccak256(abi.encodeWithSignature("NoAuth()")) ||
            err == keccak256(abi.encodeWithSignature("NoToken()")) ||
            err == keccak256(abi.encodeWithSignature("NotAjnaPool()")) ||
            err == keccak256(abi.encodeWithSignature("RemovePositionFailed()")) ||
            err == keccak256(abi.encodeWithSignature("WrongPool()")) || 
            err == keccak256(abi.encodeWithSignature("NoAllowance()")) ||
            err == keccak256(abi.encodeWithSignature("MoveToSameIndex()")) ||
            err == keccak256(abi.encodeWithSignature("RemoveDepositLockedByAuctionDebt()")) ||
            err == keccak256(abi.encodeWithSignature("DustAmountNotExceeded()")) ||
            err == keccak256(abi.encodeWithSignature("InvalidIndex()")) ||
            err == keccak256(abi.encodeWithSignature("LUPBelowHTP()")) ||
            err == keccak256(abi.encodeWithSignature("InsufficientLP()")) ||
            err == keccak256(abi.encodeWithSignature("AuctionNotCleared()")),
            "Unexpected revert error"
        );
    }
}
