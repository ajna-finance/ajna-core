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
        numberOfCalls['UBPositionsHandler.memorialize']++;

        try _positions.memorializePositions(IPositionManagerOwnerActions.MemorializePositionsParams(tokenId_, indexes_)) {

            // TODO: store memorialized position's tokenIds in mapping, for reuse in unstake and redeem calls

            // track created positions
            for ( uint256 i = 0; i < indexes_.length; i++) {
                bucketIndexesWithPosition.add(indexes_[i]);
                tokenIdsByBucketIndex[indexes_[i]].push(tokenId_);
            }

        } catch (bytes memory err) {
            _ensurePoolError(err);
        }
    }

    function _mint() internal updateLocalStateAndPoolInterest {

        try _positions.mint(IPositionManagerOwnerActions.MintParams(_actor, address(_pool), keccak256("ERC20_NON_SUBSET_HASH"))) returns (uint256 tokenId) {
            
            // add minted token to list of tokenIds
            tokenIdsMinted.add(tokenId);

            // tokenIdResult = tokenId;

        } catch (bytes memory err) {
            _ensurePoolError(err);
        }        
    }



}