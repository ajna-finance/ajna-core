// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.14;

import { Maths } from 'src/libraries/internal/Maths.sol';

import { IPositionManagerOwnerActions } from 'src/interfaces/position/IPositionManagerOwnerActions.sol';
import { UnboundedPositionsHandler }    from '../../base/handlers/unbounded/UnboundedPositionsHandler.sol';
import { ReservePoolHandler }           from './ReservePoolHandler.sol';

abstract contract PositionsHandler is UnboundedPositionsHandler, ReservePoolHandler {

    /*******************************/
    /*** Positions Test Functions ***/
    /*******************************/

    function memorializePositions(
        uint256 actorIndex_,
        uint256 bucketIndex_,
        uint256 amountToAdd_,
        uint256 skippedTime_
    ) external useRandomActor(actorIndex_) useRandomLenderBucket(bucketIndex_) useTimestamps skipTime(skippedTime_) {
        // Pre action
        (uint256 tokenId, uint256[] memory indexes) = _preMemorializePositions(bucketIndex_, amountToAdd_);
        
        // Action phase
        _memorializePositions(tokenId, indexes);
    }

    
    function _preMemorializePositions(
        uint256 bucketIndex_,
        uint256 amountToAdd_
    ) internal returns (uint256 tokenId_, uint256[] memory indexes_) {

        // ensure actor has a position
        (uint256 lpBalanceBefore, ) = _pool.lenderInfo(bucketIndex_, _actor);

        // add quote token if they don't have a position
        if (lpBalanceBefore == 0) {
            // Prepare test phase
            uint256 boundedAmount = _preAddQuoteToken(amountToAdd_);
            _addQuoteToken(boundedAmount, bucketIndex_);
        }

        //TODO: stake w/ multiple buckets instead of just one
        indexes_ = new uint256[](1);
        indexes_[0] = bucketIndex_;

        uint256[] memory lpBalances = new uint256[](1);

        // mint position NFT
        tokenId_ = _positions.mint(IPositionManagerOwnerActions.MintParams({
            recipient:      _actor,
            pool:           address(_pool),
            poolSubsetHash: keccak256("ERC20_NON_SUBSET_HASH")
        }));

        (lpBalances[0], ) = _pool.lenderInfo(bucketIndex_, _actor);
        _pool.increaseLPAllowance(address(_positions), indexes_, lpBalances);
    }
}