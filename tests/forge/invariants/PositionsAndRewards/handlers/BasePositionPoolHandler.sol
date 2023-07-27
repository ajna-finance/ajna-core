// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.18;

import { Maths } from 'src/libraries/internal/Maths.sol';

import { UnboundedPositionPoolHandler } from './unbounded/UnboundedPositionPoolHandler.sol';

abstract contract BasePositionPoolHandler is UnboundedPositionPoolHandler {

    /********************************/
    /***  Prepare Tests Functions ***/
    /********************************/

    function _preMemorializePositions(
        uint256 bucketIndex_,
        uint256 amountToAdd_
    ) internal returns (uint256 tokenId_, uint256[] memory indexes_) {
        indexes_ = _getPosition(bucketIndex_, amountToAdd_);

        // mint position NFT
        tokenId_ = _mint();
    }

    function _preRedeemPositions(
        uint256 bucketIndex_,
        uint256 amountToAdd_
    ) internal returns (uint256 tokenId_, uint256[] memory indexes_) {
 
        (tokenId_, indexes_) = _getNFTPosition(bucketIndex_, amountToAdd_);

        // approve positionManager to transfer LP tokens
        address[] memory transferors = new address[](1);
        transferors[0] = address(_positionManager);

        _pool.approveLPTransferors(transferors);
    }

    function _preBurn(
        uint256 bucketIndex_,
        uint256 amountToAdd_
    ) internal returns (uint256 tokenId_) { 
        uint256[] memory indexes;

        // check and create the position
        (tokenId_, indexes) = _preRedeemPositions(bucketIndex_, amountToAdd_);

        _redeemPositions(tokenId_, indexes);
    }

    function _preMoveLiquidity(
        uint256 amountToMove_,
        uint256 fromIndex_,
        uint256 toIndex_
    ) internal returns (uint256 tokenId_, uint256 boundedFromIndex_, uint256 boundedToIndex_) {
        boundedFromIndex_ = constrictToRange(fromIndex_, LENDER_MIN_BUCKET_INDEX, LENDER_MAX_BUCKET_INDEX);
        boundedToIndex_   = constrictToRange(toIndex_,   LENDER_MIN_BUCKET_INDEX, LENDER_MAX_BUCKET_INDEX);

        uint256[] memory indexes;
        (tokenId_, indexes) = _getNFTPosition(boundedFromIndex_, amountToMove_);
        boundedFromIndex_   = indexes.length != 0 ? indexes[0]: 0;
    }

    function _getNFTPosition(
        uint256 bucketIndex_,
        uint256 amountToAdd_
    ) internal returns (uint256 tokenId_, uint256[] memory indexes_) {

        // Check for exisiting nft positions in PositionManager
        uint256[] memory tokenIds = getTokenIdsByActor(address(_actor));

        if (tokenIds.length != 0 ) {
            // use existing position NFT
            tokenId_ = tokenIds[0];
            indexes_ = getBucketIndexesByTokenId(tokenId_);

            // create position in NFT if not already there
            if (indexes_.length == 0) {
                indexes_ = _getPosition(bucketIndex_, amountToAdd_);
                _memorializePositions(tokenId_, indexes_);
            }
        } else {
            // create a position for the actor
            (tokenId_, indexes_) = _preMemorializePositions(bucketIndex_, amountToAdd_); 
            _memorializePositions(tokenId_, indexes_);
        }
    }

    function _getPosition(
        uint256 bucketIndex_,
        uint256 amountToAdd_
    ) internal returns (uint256[] memory indexes_) {
        // ensure actor has a position
        (uint256 lpBalanceBefore,) = _pool.lenderInfo(bucketIndex_, _actor);

        // add quote token if they don't have a position
        if (lpBalanceBefore == 0) {
            // bound amount
            uint256 boundedAmount = constrictToRange(amountToAdd_, Maths.max(_pool.quoteTokenScale(), MIN_QUOTE_AMOUNT), MAX_QUOTE_AMOUNT);
            _ensureQuoteAmount(_actor, boundedAmount);
            try _pool.addQuoteToken(boundedAmount, bucketIndex_, block.timestamp + 1 minutes, false) {
            } catch (bytes memory err) {
                _ensurePoolError(err);
            }
        }

        indexes_ = new uint256[](1);
        indexes_[0] = bucketIndex_;

        uint256[] memory lpBalances = new uint256[](1);

        (lpBalances[0], ) = _pool.lenderInfo(bucketIndex_, _actor);
        _pool.increaseLPAllowance(address(_positionManager), indexes_, lpBalances);
    }
}