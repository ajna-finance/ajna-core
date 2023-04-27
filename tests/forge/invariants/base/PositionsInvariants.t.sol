// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.14;

import "@std/console.sol";

import { Maths } from 'src/libraries/internal/Maths.sol';
import { IBaseHandler }          from '../interfaces/IBaseHandler.sol';
import { ReserveInvariants } from './ReserveInvariants.t.sol';

abstract contract PositionsInvariants is ReserveInvariants {

    function invariant_positions_PM1_PM5() public useCurrentTimestamp {
        uint256 mostRecentDepositTime;
        // uint256[] memory bucketIndexes = IBaseHandler(_handler).bucketIndexesWithPosition.values();
        uint256[] memory bucketIndexes = IBaseHandler(_handler).getBucketIndexesWithPosition();

        // loop over indexes
        for (uint256 i = 0; i < bucketIndexes.length; i++) {
            uint256 bucketIndex = bucketIndexes[i];
            uint256 posLpAccum;
            uint256 poolLpAccum;

            (uint256 poolLp, uint256 depositTime) = _pool.lenderInfo(bucketIndex, address(_positions));
            poolLpAccum += poolLp;

            // loop over tokenIds
            for (uint256 k = 0; k < IBaseHandler(_handler).tokenIdsByBucketIndex(bucketIndex).length; k++) {
                uint256 tokenId = IBaseHandler(_handler).tokenIdsByBucketIndex(bucketIndex)[k];
                
                (uint256 posLp, uint256 posDepositTime) = _positions.getPositionInfo(tokenId, bucketIndex);
                posLpAccum += posLp;
                mostRecentDepositTime = (posDepositTime > mostRecentDepositTime) ? posDepositTime : mostRecentDepositTime;

            }

            assertEq(poolLpAccum, posLpAccum); 
            assertEq(depositTime, mostRecentDepositTime);

        }

    }
}