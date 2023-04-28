// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.14;

import '@openzeppelin/contracts/utils/structs/EnumerableSet.sol';

import { IPositionManagerOwnerActions } from 'src/interfaces/position/IPositionManagerOwnerActions.sol';
import { _depositFeeRate }   from 'src/libraries/helpers/PoolHelper.sol';
import { Maths }             from "src/libraries/internal/Maths.sol";

import { BaseHandler } from './BaseHandler.sol';

/**
 *  @dev this contract manages multiple lenders
 *  @dev methods in this contract are called in random order
 *  @dev randomly selects a lender contract to make a txn
 */ 
abstract contract UnboundedPositionsHandler is BaseHandler {

    using EnumerableSet for EnumerableSet.UintSet;

    function _memorializePositions(
        uint256 tokenId_,
        uint256[] memory indexes_
    ) internal updateLocalStateAndPoolInterest {
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

    function _mint() internal updateLocalStateAndPoolInterest returns (uint256 tokenIdResult) {
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
    ) internal updateLocalStateAndPoolInterest {
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
    ) internal updateLocalStateAndPoolInterest {
        numberOfCalls['UBPositionHandler.moveLiquidity']++;

        /**
        *  @notice Struct holding parameters for moving the liquidity of a position.
        */
        // struct MoveLiquidityParams {
        //     uint256 tokenId;   // The tokenId of the positions NFT
        //     address pool;      // The pool address associated with positions NFT
        //     uint256 fromIndex; // The bucket index from which liquidity should be moved
        //     uint256 toIndex;   // The bucket index to which liquidity should be moved
        //     uint256 expiry;    // Timestamp after which this TX will revert, preventing inclusion in a block with unfavorable price
        // }


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
    ) internal updateLocalStateAndPoolInterest {
        numberOfCalls['UBPositionHandler.burn']++;
        try _positions.burn(IPositionManagerOwnerActions.BurnParams(tokenId_, address(_pool))) {

        } catch (bytes memory err) {
            _ensurePoolError(err);
        }
    }



}