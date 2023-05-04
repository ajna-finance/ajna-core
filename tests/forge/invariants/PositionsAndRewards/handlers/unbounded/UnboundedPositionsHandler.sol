// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.14;

import '@openzeppelin/contracts/utils/structs/EnumerableSet.sol';

import { IPositionManagerOwnerActions } from 'src/interfaces/position/IPositionManagerOwnerActions.sol';
import { _depositFeeRate }              from 'src/libraries/helpers/PoolHelper.sol';
import { Maths }                        from "src/libraries/internal/Maths.sol";

import { BaseERC20PoolHandler }         from '../../../ERC20Pool/handlers/unbounded/BaseERC20PoolHandler.sol';
import { BasePositionsHandler }         from './BasePositionsHandler.sol';

/**
 *  @dev this contract manages multiple lenders
 *  @dev methods in this contract are called in random order
 *  @dev randomly selects a lender contract to make a txn
 */ 
abstract contract UnboundedPositionsHandler is BasePositionsHandler {

    using EnumerableSet for EnumerableSet.UintSet;

    function _memorializePositions(
        uint256 tokenId_,
        uint256[] memory indexes_
    ) internal {
        numberOfCalls['UBPositionHandler.memorialize']++;

        try _positions.memorializePositions(IPositionManagerOwnerActions.MemorializePositionsParams(tokenId_, indexes_)) {

            // TODO: store memorialized position's tokenIds in mapping, for reuse in unstake and redeem calls

            // track created positions
            for ( uint256 i = 0; i < indexes_.length; i++) {
                bucketIndexesWithPosition.add(indexes_[i]);
                tokenIdsByBucketIndex[indexes_[i]].add(tokenId_);
            }

        } catch (bytes memory err) {
            _ensurePoolError(err);
        }
    }

    function _mint() internal returns (uint256 tokenIdResult) {
        numberOfCalls['UBPositionHandler.mint']++;
        try _positions.mint(IPositionManagerOwnerActions.MintParams(_actor, address(_pool), keccak256("ERC20_NON_SUBSET_HASH"))) returns (uint256 tokenId) {

            tokenIdResult = tokenId;

        } catch (bytes memory err) {
            _ensurePoolError(err);
        }
    }

    function _redeemPositions(
        uint256 tokenId_,
        uint256[] memory indexes_
    ) internal {
        numberOfCalls['UBPositionHandler.redeem']++;

        try _positions.reedemPositions(IPositionManagerOwnerActions.RedeemPositionsParams(tokenId_, address(_pool), indexes_)) {

            // remove tracked positions
            for ( uint256 i = 0; i < indexes_.length; i++) {
                bucketIndexesWithPosition.remove(indexes_[i]); 
                tokenIdsByBucketIndex[indexes_[i]].remove(tokenId_);
            }

        } catch (bytes memory err) {
            _ensurePoolError(err);
        }

    }

    function _moveLiquidity(
        uint256 tokenId_,
        uint256 fromIndex_,
        uint256 toIndex_
    ) internal {
        numberOfCalls['UBPositionHandler.moveLiquidity']++;

        /**
        *  @notice Struct holding parameters for moving the liquidity of a position.
        */

        try _positions.moveLiquidity(IPositionManagerOwnerActions.MoveLiquidityParams(tokenId_, address(_pool), fromIndex_, toIndex_, block.timestamp + 30)) {

            // TODO: store memorialized position's tokenIds in mapping, for reuse in unstake and redeem calls

            // remove tracked positions
            tokenIdsByBucketIndex[fromIndex_].remove(tokenId_);
            if (tokenIdsByBucketIndex[fromIndex_].length() == 0) {
                bucketIndexesWithPosition.remove(fromIndex_); 
            }

            // track created positions
            bucketIndexesWithPosition.add(toIndex_);
            tokenIdsByBucketIndex[toIndex_].add(tokenId_);

        } catch (bytes memory err) {
            _ensurePoolError(err);
        }
    }


    function _burn(
        uint256 tokenId_
    ) internal {
        numberOfCalls['UBPositionHandler.burn']++;
        try _positions.burn(IPositionManagerOwnerActions.BurnParams(tokenId_, address(_pool))) {

        } catch (bytes memory err) {
            _ensurePoolError(err);
        }
    }
}