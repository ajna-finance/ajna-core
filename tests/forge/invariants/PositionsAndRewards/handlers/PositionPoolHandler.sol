// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.18;

import { Maths } from 'src/libraries/internal/Maths.sol';
import { Strings } from '@openzeppelin/contracts/utils/Strings.sol';

import { UnboundedPositionPoolHandler } from './unbounded/UnboundedPositionPoolHandler.sol';

abstract contract PositionPoolHandler is UnboundedPositionPoolHandler { 

    /********************************/
    /*** Positions Test Functions ***/
    /********************************/

    function memorializePositions(
        uint256 actorIndex_,
        uint256 bucketIndex_,
        uint256 amountToAdd_,
        uint256 skippedTime_
    ) external useRandomActor(actorIndex_) useRandomLenderBucket(bucketIndex_) useTimestamps skipTime(skippedTime_) writeLogs writePositionLogs {
        numberOfCalls['BPositionHandler.memorialize']++;
        // Pre action //
        (uint256 tokenId, uint256[] memory indexes) = _preMemorializePositions(_lenderBucketIndex, amountToAdd_);

        // Action phase // 
        _memorializePositions(tokenId, indexes);
    }

    function redeemPositions(
        uint256 actorIndex_,
        uint256 bucketIndex_,
        uint256 amountToAdd_,
        uint256 skippedTime_
    ) external useRandomActor(actorIndex_) useRandomLenderBucket(bucketIndex_) useTimestamps skipTime(skippedTime_) writeLogs writePositionLogs {
        numberOfCalls['BPositionHandler.redeem']++;
        // Pre action //
        (uint256 tokenId, uint256[] memory indexes) = _preRedeemPositions(_lenderBucketIndex, amountToAdd_);

        // NFT doesn't have a position associated with it, return
        if (indexes.length == 0) return; 
 
        // Action phase // 
        _redeemPositions(tokenId, indexes);
    }

    function mint(
        uint256 actorIndex_,
        uint256 skippedTime_
    ) external useRandomActor(actorIndex_) useTimestamps skipTime(skippedTime_) writeLogs writePositionLogs {
        numberOfCalls['BPositionHandler.mint']++;        

        // Action phase //
        _mint();
    }

    function burn(
        uint256 actorIndex_,
        uint256 bucketIndex_,
        uint256 skippedTime_,
        uint256 amountToAdd_
    ) external useRandomActor(actorIndex_) useRandomLenderBucket(bucketIndex_) useTimestamps skipTime(skippedTime_) writeLogs writePositionLogs {
        numberOfCalls['BPositionHandler.burn']++;        
        // Pre action //
        (uint256 tokenId_) = _preBurn(_lenderBucketIndex, amountToAdd_);
        
        // Action phase //
        _burn(tokenId_);
    }

    function moveLiquidity(
        uint256 actorIndex_,
        uint256 skippedTime_,
        uint256 amountToMove_,
        uint256 fromIndex_,
        uint256 toIndex_
    ) external useRandomActor(actorIndex_) useTimestamps skipTime(skippedTime_) writeLogs writePositionLogs {
        numberOfCalls['BPositionHandler.moveLiquidity']++;        
        // Pre action //
        (
            uint256 tokenId,
            uint256 fromIndex,
            uint256 toIndex
        ) = _preMoveLiquidity(amountToMove_, fromIndex_, toIndex_);

        // retrieve info of bucket from pool
        (
            ,
            uint256 bucketCollateral,
            ,
            ,
        ) = _pool.bucketInfo(fromIndex);

        // NFT doesn't have a position associated with it, return
        if (fromIndex == 0) return;

        // to avoid LP mismatch revert return if bucket has collateral or exchangeRate < 1e18
        if (bucketCollateral != 0) return;
        if (_pool.bucketExchangeRate(fromIndex) < 1e18) return;
        
        // Action phase //
        _moveLiquidity(tokenId, fromIndex, toIndex);
    }

    function transferPosition(
        uint256 actorIndex_,
        uint256 bucketIndex_,
        uint256 skippedTime_,
        uint256 amountToAdd_
    ) external useRandomActor(actorIndex_) useRandomLenderBucket(bucketIndex_) useTimestamps skipTime(skippedTime_) writeLogs writePositionLogs {
        numberOfCalls['BPositionHandler.transferPosition']++;        
        // Pre action //
        (uint256 tokenId_, uint256[] memory indexes) = _getNFTPosition(_lenderBucketIndex, amountToAdd_);

        address receiver = actors[constrictToRange(actorIndex_, 0, actors.length - 1)];

        // NFT doesn't have a position associated with it, return
        if (indexes.length == 0) return;
        
        // Action phase //
        _transferPosition(receiver, tokenId_);
    }

    function _preMemorializePositions(
        uint256 bucketIndex_,
        uint256 amountToAdd_
    ) internal returns (uint256 tokenId_, uint256[] memory indexes_) {

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

        // mint position NFT
        tokenId_ = _mint();

        (lpBalances[0], ) = _pool.lenderInfo(bucketIndex_, _actor);
        _pool.increaseLPAllowance(address(_positionManager), indexes_, lpBalances);
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
            tokenId_ = tokenIds[constrictToRange(randomSeed(), 0, tokenIds.length - 1)];
            indexes_ = getBucketIndexesByTokenId(tokenId_);
        } else {
            // create a position for the actor
            (tokenId_, indexes_) = _preMemorializePositions(bucketIndex_, amountToAdd_); 
            _memorializePositions(tokenId_, indexes_);
        }
    }

    modifier writePositionLogs() {
        // Verbosity of Log file for positionManager
        logVerbosity = uint256(vm.envOr("LOGS_VERBOSITY_POSITION", uint256(0)));

        if (logVerbosity != 0) logToFile = true;

        _;

        if (logVerbosity > 0) {
            printInNextLine("== PositionManager Details ==");
            writeActorLogs();
            writeBucketLogs();
            printInNextLine("=======================");
        }
    }

    function writeActorLogs() internal {

        for (uint256 i = 0; i < actors.length; i++) {

            uint256[] memory tokenIds = getTokenIdsByActor(actors[i]);

            if (tokenIds.length != 0) {
                string memory actorStr = string(abi.encodePacked("Actor ", Strings.toString(i), " tokenIds: "));
                string memory tokenIdStr;

                for (uint256 k = 0; k < tokenIds.length; k++) {
                    tokenIdStr = string(abi.encodePacked(tokenIdStr, " ", Strings.toString(tokenIds[k])));
                }

                printLine(string.concat(actorStr,tokenIdStr)); 
            }
        }
    }

    function writeBucketLogs() internal {
        uint256[] memory bucketIndexes = getBucketIndexesWithPosition();

        // loop over bucket indexes with positions
        for (uint256 i = 0; i < bucketIndexes.length; i++) {
            uint256 bucketIndex = bucketIndexes[i];

            printLine("");
            printLog("Bucket: ", bucketIndex);

            // loop over tokenIds in bucket indexes
            uint256[] memory tokenIds = getTokenIdsByBucketIndex(bucketIndex);
            for (uint256 k = 0; k < tokenIds.length; k++) {
                uint256 tokenId = tokenIds[k];
                
                uint256 posLp = _positionManager.getLP(tokenId, bucketIndex);
                string memory tokenIdStr = string.concat("tokenID ", Strings.toString(tokenId));
                printLog(string.concat(tokenIdStr, " LP in positionMan = "), posLp);
            }
        }
    }
}