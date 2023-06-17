
// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.18;

import '@std/Test.sol';
import '@openzeppelin/contracts/utils/structs/EnumerableSet.sol';
import { Strings } from '@openzeppelin/contracts/utils/Strings.sol';

import { IPositionManagerOwnerActions } from 'src/interfaces/position/IPositionManagerOwnerActions.sol';
import { _depositFeeRate }   from 'src/libraries/helpers/PoolHelper.sol';
import { Maths }             from "src/libraries/internal/Maths.sol";

import { PositionManager }   from 'src/PositionManager.sol';
import { RewardsManager }    from 'src/RewardsManager.sol';

/**
 *  @dev this contract manages multiple lenders
 *  @dev methods in this contract are called in random order
 *  @dev randomly selects a lender contract to make a txn
 */ 
abstract contract UnboundedBasePositionHandler is Test {

    PositionManager internal _positionManager;
    RewardsManager  internal _rewardsManager;

    uint256 MAX_AJNA_AMOUNT = vm.envOr("MAX_AJNA_AMOUNT_ERC20", uint256(100_000_000 * 1e18));

    // Position invariant test state //

    // used for PM1_PM2_PM3 tracking
    mapping(uint256 => EnumerableSet.UintSet) internal tokenIdsByBucketIndex;
    EnumerableSet.UintSet internal bucketIndexesWithPosition;

    // used for removing all CT and QT to reset bucket exchange rate 
    mapping(uint256 => address) internal actorByTokenId;
    mapping(address => EnumerableSet.UintSet) internal tokenIdsByActor;
    mapping(uint256 => EnumerableSet.UintSet) internal bucketIndexesByTokenId;

    // used to track LP changes in `_redeemPositions()` and `_memorializePositions()`
    mapping(uint256 => uint256) internal bucketIndexToActorPositionManLps;
    mapping(uint256 => uint256) internal bucketIndexToPositionManPoolLps;
    mapping(uint256 => uint256) internal bucketIndexToActorPoolLps;
    mapping(uint256 => uint256) internal bucketIndexToDepositTime;

    // Rewards invariant test state //
    mapping(uint256 => uint256) public rewardsClaimedPerEpoch;       // staking rewards per epoch
    mapping(uint256 => uint256) public updateRewardsClaimedPerEpoch; // updating rewards per epoch

    mapping(uint256 => uint256) public rewardsAlreadyClaimed;  // tracks rewards already claimed
    uint256 public totalStakerRewPerEpoch;                     // amount of reserve decrease
    uint256 public totalUpdaterRewPerEpoch;                    // amount of reserve increase

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
            err == keccak256(abi.encodeWithSignature("MoveToSameIndex()")) ||
            err == keccak256(abi.encodeWithSignature("RemoveDepositLockedByAuctionDebt()")) ||
            err == keccak256(abi.encodeWithSignature("DustAmountNotExceeded()")) ||
            err == keccak256(abi.encodeWithSignature("InvalidIndex()")) ||
            err == keccak256(abi.encodeWithSignature("LUPBelowHTP()")),
            "Unexpected revert error"
        );
    }
}
