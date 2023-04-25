// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.14;

import { _depositFeeRate }   from 'src/libraries/helpers/PoolHelper.sol';
import { Maths }             from "src/libraries/internal/Maths.sol";

import { BaseHandler } from './BaseHandler.sol';

/**
 *  @dev this contract manages multiple lenders
 *  @dev methods in this contract are called in random order
 *  @dev randomly selects a lender contract to make a txn
 */ 
abstract contract UnboundedPositionsHandler is BaseHandler {


    function _memorializePositions(
        uint256 tokenId_,
        uint256[] memory indexes_
    ) internal updateLocalStateAndPoolInterest {
        numberOfCalls['UBPositionsHandler.memorializePositions']++;

        try _positions.memorializePositions(_positions.MemorializePositionsParams({tokenId: tokenId_, indexes: indexes_})) {

            // TODO: store memorialized position's tokenIds in mapping, for reuse in unstake and redeem calls
            // uint256[] memory ownedPositions = positions[_actor];
            // ownedPositions.push(tokenId_);
            // positions[_actor] = positions;

        } catch (bytes memory err) {
            _ensurePoolError(err);
        }
    }

    function _mint(
        uint256 tokenId_
    ) internal {
        try _positions.mint(tokenId_) {

        } catch (bytes memory err) {
            _ensurePoolError(err);
        }        
    }



}