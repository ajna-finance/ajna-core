// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.14;

import "@std/console.sol";

import { Maths } from 'src/libraries/internal/Maths.sol';
import { IBaseHandler }          from '../interfaces/IBaseHandler.sol';
import { ReserveInvariants } from './ReserveInvariants.t.sol';

abstract contract PositionsInvariants is ReserveInvariants {

    function invariant_positions_PM1_PM2() public useCurrentTimestamp {
        uint256 mostRecentDepositTime;
        uint256[] memory bucketIndexes = IBaseHandler(_handler).getBucketIndexesWithPosition();

        // loop over bucket indexes with positions
        for (uint256 i = 0; i < bucketIndexes.length; i++) {
            uint256 bucketIndex = bucketIndexes[i];
            uint256 posLpAccum;
            uint256 poolLpAccum;

            (uint256 poolLp, uint256 depositTime) = _pool.lenderInfo(bucketIndex, address(_positions));
            poolLpAccum += poolLp;

            // loop over tokenIds in bucket indexes
            uint256[] memory tokenIds = IBaseHandler(_handler).getTokenIdsByBucketIndex(bucketIndex);
            for (uint256 k = 0; k < tokenIds.length; k++) {
                uint256 tokenId = tokenIds[k];
                
                (uint256 posLp, uint256 posDepositTime) = _positions.getPositionInfo(tokenId, bucketIndex);
                posLpAccum += posLp;
                mostRecentDepositTime = (posDepositTime > mostRecentDepositTime) ? posDepositTime : mostRecentDepositTime;
            }

            assertEq(poolLpAccum, posLpAccum, "Positions Invariant PM1"); 
            assertEq(depositTime, mostRecentDepositTime, "Positions Invariant PM2");
        }
    }
}