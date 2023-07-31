// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.18;

import { Maths } from 'src/libraries/internal/Maths.sol';
import { Strings } from '@openzeppelin/contracts/utils/Strings.sol';
import '@openzeppelin/contracts/utils/structs/EnumerableSet.sol';

import { UnboundedPositionPoolHandler } from './unbounded/UnboundedPositionPoolHandler.sol';

abstract contract PositionPoolHandler is UnboundedPositionPoolHandler {

    using EnumerableSet for EnumerableSet.UintSet;

    /********************************/
    /*** Positions Test Functions ***/
    /********************************/

    function memorializePositions(
        uint256 actorIndex_,
        uint256 noOfBuckets_,
        uint256 amountToAdd_,
        uint256 skippedTime_
    ) external useRandomActor(actorIndex_) useTimestamps skipTime(skippedTime_) useRandomPool(skippedTime_) writeLogs writePositionLogs {
        numberOfCalls['BPositionHandler.memorialize']++;
        // Pre action //
        (uint256 tokenId, uint256[] memory indexes) = _preMemorializePositions(noOfBuckets_, amountToAdd_);

        // Action phase // 
        _memorializePositions(tokenId, indexes);
    }

    function redeemPositions(
        uint256 actorIndex_,
        uint256 noOfBuckets_,
        uint256 amountToAdd_,
        uint256 skippedTime_
    ) external useRandomActor(actorIndex_) useTimestamps skipTime(skippedTime_) useRandomPool(skippedTime_) writeLogs writePositionLogs {
        numberOfCalls['BPositionHandler.redeem']++;
        // Pre action //
        (uint256 tokenId, uint256[] memory indexes) = _preRedeemPositions(noOfBuckets_, amountToAdd_);

        // NFT doesn't have a position associated with it, return
        if (indexes.length == 0) return; 
 
        // Action phase // 
        _redeemPositions(tokenId, indexes);
    }

    function mint(
        uint256 actorIndex_,
        uint256 skippedTime_
    ) external useRandomActor(actorIndex_) useTimestamps skipTime(skippedTime_) useRandomPool(skippedTime_) writeLogs writePositionLogs {
        numberOfCalls['BPositionHandler.mint']++;        

        // Action phase //
        _mint();
    }

    function burn(
        uint256 actorIndex_,
        uint256 bucketIndex_,
        uint256 skippedTime_,
        uint256 amountToAdd_
    ) external useRandomActor(actorIndex_) useRandomLenderBucket(bucketIndex_) useTimestamps skipTime(skippedTime_) useRandomPool(skippedTime_) writeLogs writePositionLogs {
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
        uint256 toIndex_
    ) external useRandomActor(actorIndex_) useTimestamps skipTime(skippedTime_) useRandomPool(skippedTime_) writeLogs writePositionLogs {
        numberOfCalls['BPositionHandler.moveLiquidity']++;        
        // Pre action //
        (
            uint256 tokenId,
            uint256 fromIndex,
            uint256 toIndex
        ) = _preMoveLiquidity(amountToMove_, toIndex_);

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
        uint256 noOfBuckets_,
        uint256 amountToAdd_
    ) internal returns (uint256 tokenId_, uint256[] memory indexes_) {
        noOfBuckets_ = constrictToRange(noOfBuckets_, 1, buckets.length());
        indexes_     = getRandomElements(noOfBuckets_, buckets.values());
        uint256[] memory lpBalances = new uint256[](noOfBuckets_);

        for (uint256 i = 0; i < noOfBuckets_; i++) {

            uint256 bucketIndex = indexes_[i];

            // ensure actor has a position
            (uint256 lpBalanceBefore,) = _pool.lenderInfo(bucketIndex, _actor);

            // add quote token if they don't have a position
            if (lpBalanceBefore == 0) {
                // bound amount
                uint256 boundedAmount = constrictToRange(amountToAdd_, Maths.max(_pool.quoteTokenScale(), MIN_QUOTE_AMOUNT), MAX_QUOTE_AMOUNT);
                _ensureQuoteAmount(_actor, boundedAmount);
                try _pool.addQuoteToken(boundedAmount, bucketIndex, block.timestamp + 1 minutes, false) {
                } catch (bytes memory err) {
                    _ensurePoolError(err);
                }
            }

            (lpBalances[i], ) = _pool.lenderInfo(bucketIndex, _actor);
        }

        _pool.increaseLPAllowance(address(_positionManager), indexes_, lpBalances);

        // mint position NFT
        tokenId_ = _mint();
    }

    function _preRedeemPositions(
        uint256 noOfBuckets_,
        uint256 amountToAdd_
    ) internal returns (uint256 tokenId_, uint256[] memory indexes_) {
 
        (tokenId_, indexes_) = _getNFTPosition(noOfBuckets_, amountToAdd_);

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
        uint256 toIndex_
    ) internal returns (uint256 tokenId_, uint256 boundedFromIndex_, uint256 boundedToIndex_) {
        boundedToIndex_   = constrictToRange(toIndex_,   LENDER_MIN_BUCKET_INDEX, LENDER_MAX_BUCKET_INDEX);

        uint256[] memory indexes;
        (tokenId_, indexes) = _getNFTPosition(1, amountToMove_);
        boundedFromIndex_   = indexes.length != 0 ? indexes[0]: 0;
    }

    function _getNFTPosition(
        uint256 noOfBuckets_,
        uint256 amountToAdd_
    ) internal returns (uint256 tokenId_, uint256[] memory indexes_) {

        // Check for exisiting nft positions in PositionManager
        uint256[] memory tokenIds = getTokenIdsByActor(address(_actor));

        if (tokenIds.length != 0 ) {
            // use existing position NFT
            tokenId_ = tokenIds[constrictToRange(randomSeed(), 0, tokenIds.length - 1)];
            indexes_ = getBucketIndexesByTokenId(tokenId_);
            if (indexes_.length != 0) {
                noOfBuckets_ = constrictToRange(noOfBuckets_, 1, indexes_.length);

                // pick random indexes from all positions
                indexes_ = getRandomElements(noOfBuckets_, indexes_);
            }
        } else {
            // create a position for the actor
            (tokenId_, indexes_) = _preMemorializePositions(noOfBuckets_, amountToAdd_); 
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
        // loop over pools
        for (uint256 i = 0; i < _pools.length; i++) {
            address pool = _pools[i];
            printLine(string.concat("Pool: ", Strings.toHexString(uint160(pool), 20)));
            uint256[] memory bucketIndexes = getBucketIndexesWithPosition(pool);

            // loop over bucket indexes with positions
            for (uint256 j = 0; j < bucketIndexes.length; j++) {
                uint256 bucketIndex = bucketIndexes[j];

                printLine("");
                printLog("Bucket: ", bucketIndex);

                // loop over tokenIds in bucket indexes
                uint256[] memory tokenIds = getTokenIdsByBucketIndex(pool, bucketIndex);
                for (uint256 k = 0; k < tokenIds.length; k++) {
                    uint256 tokenId = tokenIds[k];
                    
                    uint256 posLp = _positionManager.getLP(tokenId, bucketIndex);
                    string memory tokenIdStr = string.concat("tokenID ", Strings.toString(tokenId));
                    printLog(string.concat(tokenIdStr, " LP in positionMan = "), posLp);
                }
            }
        }
    }

    function getRandomElements(uint256 noOfElements, uint256[] memory arr) internal returns (uint256[] memory randomBuckets_) {
        randomBuckets_ = new uint256[](noOfElements);
        
        for (uint256 i = 0; i < noOfElements; i++) {
            uint256 bucketIndex = constrictToRange(randomSeed(), 0, arr.length - 1 - i);
            uint256 bucket = arr[bucketIndex];
            randomBuckets_[i] = bucket;
            
            // put last element from array to choosen array and next time pick new random element from first to last second element.
            arr[bucketIndex] = arr[arr.length - 1 - i];
        }
    }
}