// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.18;

import "@std/console.sol";

import { Pool }              from 'src/base/Pool.sol';
import { ERC20Pool }         from 'src/ERC20Pool.sol';
import { ERC721Pool }        from 'src/ERC721Pool.sol';
import { ERC20PoolFactory }  from 'src/ERC20PoolFactory.sol';
import { ERC721PoolFactory } from 'src/ERC721PoolFactory.sol';
import { PositionManager }   from 'src/PositionManager.sol';
import { Maths }             from 'src/libraries/internal/Maths.sol';

import { IBaseHandler }                from '../interfaces/IBaseHandler.sol';
import { IPositionsAndRewardsHandler } from '../interfaces/IPositionsAndRewardsHandler.sol';
import { BaseInvariants }              from '../base/BaseInvariants.sol';
import { TokenWithNDecimals }          from '../../utils/Tokens.sol';

abstract contract PositionsInvariants is BaseInvariants {

    uint256 internal constant NUM_ACTORS = 10;

    ERC20Pool          internal _erc20impl;
    ERC20PoolFactory   internal _erc20poolFactory;
    ERC721PoolFactory  internal _erc721poolFactory;
    ERC721Pool         internal _erc721impl;
    PositionManager    internal _positionManager;
    address[]          internal _pools;

    function invariant_positions_PM1_PM2_PM3() public useCurrentTimestamp {
        for (uint256 poolIndex = 0; poolIndex < _pools.length; poolIndex++) {
            address pool = _pools[poolIndex];

            uint256[] memory bucketIndexes = IPositionsAndRewardsHandler(_handler).getBucketIndexesWithPosition(pool);

            // loop over bucket indexes with positions
            for (uint256 i = 0; i < bucketIndexes.length; i++) {
                uint256 mostRecentDepositTime;
                uint256 bucketIndex = bucketIndexes[i];
                uint256 posLpAccum;
                uint256 poolLpAccum;

                (uint256 poolLp, uint256 depositTime) = Pool(pool).lenderInfo(bucketIndex, address(_positionManager));
                poolLpAccum += poolLp;

                // loop over tokenIds in bucket indexes
                uint256[] memory tokenIds = IPositionsAndRewardsHandler(_handler).getTokenIdsByBucketIndex(pool, bucketIndex);
                for (uint256 k = 0; k < tokenIds.length; k++) {
                    uint256 tokenId = tokenIds[k];
                    
                    (, uint256 posDepositTime) = _positionManager.getPositionInfo(tokenId, bucketIndex);
                    uint256 posLp = _positionManager.getLP(tokenId, bucketIndex);
                    posLpAccum += posLp;
                    mostRecentDepositTime = (posDepositTime > mostRecentDepositTime) ? posDepositTime : mostRecentDepositTime;
                }
                require(poolLpAccum == posLpAccum,            "Positions Invariant PM1 and PM2"); 
                require(depositTime >= mostRecentDepositTime, "Positions Invariant PM3");
            }
        }
    }

    function invariant_call_summary() public virtual useCurrentTimestamp {
        console.log("\nCall Summary\n");
        console.log("--Positions--------");
        console.log("UBPositionHandler.mint              ",  IBaseHandler(_handler).numberOfCalls("UBPositionHandler.mint"));
        console.log("BPositionHandler.mint               ",  IBaseHandler(_handler).numberOfCalls("BPositionHandler.mint"));
        console.log("UBPositionHandler.burn              ",  IBaseHandler(_handler).numberOfCalls("UBPositionHandler.burn"));
        console.log("BPositionHandler.burn               ",  IBaseHandler(_handler).numberOfCalls("BPositionHandler.burn"));
        console.log("UBPositionHandler.memorialize       ",  IBaseHandler(_handler).numberOfCalls("UBPositionHandler.memorialize"));
        console.log("BPositionHandler.memorialize        ",  IBaseHandler(_handler).numberOfCalls("BPositionHandler.memorialize"));
        console.log("UBPositionHandler.redeem            ",  IBaseHandler(_handler).numberOfCalls("UBPositionHandler.redeem"));
        console.log("BPositionHandler.redeem             ",  IBaseHandler(_handler).numberOfCalls("BPositionHandler.redeem"));
        console.log("UBPositionHandler.moveLiquidity     ",  IBaseHandler(_handler).numberOfCalls("UBPositionHandler.moveLiquidity"));
        console.log("BPositionHandler.moveLiquidity      ",  IBaseHandler(_handler).numberOfCalls("BPositionHandler.moveLiquidity"));
        console.log("BPositionHandler.transferPosition   ",  IBaseHandler(_handler).numberOfCalls("BPositionHandler.transferPosition"));
        console.log(
            "Sum",
            IBaseHandler(_handler).numberOfCalls("BPositionHandler.mint") + 
            IBaseHandler(_handler).numberOfCalls("BPositionHandler.burn") +
            IBaseHandler(_handler).numberOfCalls("BPositionHandler.memorialize") +
            IBaseHandler(_handler).numberOfCalls("BPositionHandler.redeem") +
            IBaseHandler(_handler).numberOfCalls("BPositionHandler.moveLiquidity") +
            IBaseHandler(_handler).numberOfCalls("BPositionHandler.transferPosition") 
        );
    }
}
