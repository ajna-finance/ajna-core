// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.14;

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


    function _memorializePositions(
        uint256 tokenId_,
        uint256[] memory indexes_
    ) internal updateLocalStateAndPoolInterest {
        numberOfCalls['UBPositionsHandler.memorialize']++;

        try _positions.memorializePositions(IPositionManagerOwnerActions.MemorializePositionsParams(tokenId_, indexes_)) {

            // TODO: store memorialized position's tokenIds in mapping, for reuse in unstake and redeem calls
            // uint256[] memory ownedPositions = positions[_actor];
            // ownedPositions.push(tokenId_);
            // positions[_actor] = positions;

        } catch (bytes memory err) {
            _ensurePoolError(err);
        }
    }

    function _mint() internal {
        try _positions.mint(IPositionManagerOwnerActions.MintParams(_actor, address(_pool), keccak256("ERC20_NON_SUBSET_HASH"))) {

        } catch (bytes memory err) {
            _ensurePoolError(err);
        }        
    }



}