// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.14;

import "@std/console.sol";

import { Pool }              from 'src/base/Pool.sol';
import { ERC20Pool }         from 'src/ERC20Pool.sol';
import { ERC721Pool }        from 'src/ERC721Pool.sol';
import { ERC20PoolFactory }  from 'src/ERC20PoolFactory.sol';
import { ERC721PoolFactory } from 'src/ERC721PoolFactory.sol';
import { PositionManager }   from 'src/PositionManager.sol';
import { Maths }             from 'src/libraries/internal/Maths.sol';

import { IBaseHandler }               from '../interfaces/IBaseHandler.sol';
import { BaseInvariants }             from '../base/BaseInvariants.sol';
import { ReserveERC20PoolInvariants } from '../ERC20Pool/ReserveERC20PoolInvariants.t.sol';
import { ReserveERC20PoolHandler }    from '../ERC20Pool/handlers/ReserveERC20PoolHandler.sol';
import { TokenWithNDecimals }         from '../../utils/Tokens.sol';

import { PositionHandler }    from './handlers/PositionHandler.sol';

contract PositionsInvariants is BaseInvariants {

    uint256            internal constant NUM_ACTORS = 10;

    TokenWithNDecimals internal _collateral;
    ERC20Pool          internal _erc20pool;
    ERC20Pool          internal _erc20impl;
    ERC20PoolFactory   internal _erc20poolFactory;
    ERC721PoolFactory  internal _erc721poolFactory;
    ERC721Pool         internal _erc721impl;
    PositionManager    internal _position;
    PositionHandler    internal _positionHandler;

    function setUp() public override virtual {

        super.setUp();
        _collateral        = new TokenWithNDecimals("Collateral", "C", uint8(vm.envOr("COLLATERAL_PRECISION", uint256(18))));
        _erc20poolFactory  = new ERC20PoolFactory(address(_ajna));
        _erc20impl         = _erc20poolFactory.implementation();
        _erc721poolFactory = new ERC721PoolFactory(address(_ajna));
        _erc721impl        = _erc721poolFactory.implementation();
        _erc20pool         = ERC20Pool(_erc20poolFactory.deployPool(address(_collateral), address(_quote), 0.05 * 10**18));
        _pool              = Pool(address(_erc20pool));
        _position         = new PositionManager(_erc20poolFactory, _erc721poolFactory);

        excludeContract(address(_ajna));
        excludeContract(address(_collateral));
        excludeContract(address(_quote));
        excludeContract(address(_erc20poolFactory));
        excludeContract(address(_erc721poolFactory));
        excludeContract(address(_erc20pool));
        excludeContract(address(_poolInfo));
        excludeContract(address(_erc20impl));
        excludeContract(address(_erc721impl));
        excludeContract(address(_position));

        _positionHandler = new PositionHandler(
            address(_position),
            address(_erc20pool),
            address(_ajna),
            address(_quote),
            address(_collateral),
            address(_poolInfo),
            NUM_ACTORS,
            address(this)
        );

        _handler = address(_positionHandler);
    }

    function invariant_positions_PM1_PM2() public useCurrentTimestamp {
        uint256[] memory bucketIndexes = IBaseHandler(_handler).getBucketIndexesWithPosition();

        // loop over bucket indexes with positions
        for (uint256 i = 0; i < bucketIndexes.length; i++) {
            uint256 mostRecentDepositTime;
            uint256 bucketIndex = bucketIndexes[i];
            uint256 posLpAccum;
            uint256 poolLpAccum;

            (uint256 poolLp, uint256 depositTime) = _pool.lenderInfo(bucketIndex, address(_position));
            poolLpAccum += poolLp;

            // loop over tokenIds in bucket indexes
            uint256[] memory tokenIds = IBaseHandler(_handler).getTokenIdsByBucketIndex(bucketIndex);
            for (uint256 k = 0; k < tokenIds.length; k++) {
                uint256 tokenId = tokenIds[k];
                
                (, uint256 posDepositTime) = _position.getPositionInfo(tokenId, bucketIndex);
                uint256 posLp = _position.getLP(tokenId, bucketIndex);
                posLpAccum += posLp;
                mostRecentDepositTime = (posDepositTime > mostRecentDepositTime) ? posDepositTime : mostRecentDepositTime;
            }
            require(poolLpAccum == posLpAccum, "Positions Invariant PM1"); 
            require(depositTime >= mostRecentDepositTime, "Positions Invariant PM2");
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
        console.log(
            "Sum",
            IBaseHandler(_handler).numberOfCalls("BPositionHandler.mint") + 
            IBaseHandler(_handler).numberOfCalls("BPositionHandler.burn") +
            IBaseHandler(_handler).numberOfCalls("BPositionHandler.memorialize") +
            IBaseHandler(_handler).numberOfCalls("BPositionHandler.redeem") +
            IBaseHandler(_handler).numberOfCalls("BPositionHandler.moveLiquidity") 
        );
    }
}