// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.18;

import "@std/console.sol";

import { Strings } from '@openzeppelin/contracts/utils/Strings.sol';

import { Pool }              from 'src/base/Pool.sol';
import { ERC20Pool }         from 'src/ERC20Pool.sol';
import { ERC721Pool }        from 'src/ERC721Pool.sol';
import { ERC20PoolFactory }  from 'src/ERC20PoolFactory.sol';
import { ERC721PoolFactory } from 'src/ERC721PoolFactory.sol';
import { PositionManager }   from 'src/PositionManager.sol';
import { Maths }             from 'src/libraries/internal/Maths.sol';

import { IBaseHandler }                from '../interfaces/IBaseHandler.sol';
import { IPositionsAndRewardsHandler } from '../interfaces/IPositionsAndRewardsHandler.sol';
import { TokenWithNDecimals }          from '../../utils/Tokens.sol';

import { ERC20PoolPositionHandler }    from './handlers/ERC20PoolPositionHandler.sol';
import { PositionsInvariants }         from './PositionsInvariants.sol';

contract ERC20PoolPositionsInvariants is PositionsInvariants {

    ERC20PoolPositionHandler              internal _erc20positionHandler;
    ERC20PoolPositionHandler.PoolInfo[10] internal _poolsInfo;

    function setUp() public override virtual {

        super.setUp();
        _erc20poolFactory  = new ERC20PoolFactory(address(_ajna));
        _erc20impl         = _erc20poolFactory.implementation();
        _erc721poolFactory = new ERC721PoolFactory(address(_ajna));
        _erc721impl        = _erc721poolFactory.implementation();
        _positionManager   = new PositionManager(_erc20poolFactory, _erc721poolFactory);

        for (uint256 i = 0; i < 10; ++i) {
            _poolsInfo[i].collateral = address(new TokenWithNDecimals(string(abi.encodePacked("Collateral", Strings.toString(i + 1))), "C", uint8(vm.envOr("COLLATERAL_PRECISION", uint256(18)))));
            _poolsInfo[i].quote      = address(new TokenWithNDecimals(string(abi.encodePacked("Quote", Strings.toString(i + 1))), "Q", uint8(vm.envOr("QUOTE_PRECISION", uint256(18)))));
            _poolsInfo[i].pool       = address(_erc20poolFactory.deployPool(_poolsInfo[i].collateral, _poolsInfo[i].quote, 0.05 * 10**18));

            excludeContract(_poolsInfo[i].collateral);
            excludeContract(_poolsInfo[i].quote);
            excludeContract(_poolsInfo[i].pool);
            _pools.push(_poolsInfo[i].pool);
        }

        excludeContract(address(_ajna));
        excludeContract(address(_quote));
        excludeContract(address(_erc20poolFactory));
        excludeContract(address(_erc721poolFactory));
        excludeContract(address(_poolInfo));
        excludeContract(address(_erc20impl));
        excludeContract(address(_erc721impl));
        excludeContract(address(_positionManager));

        _erc20positionHandler = new ERC20PoolPositionHandler(
            address(_positionManager),
            _poolsInfo,
            address(_ajna),
            address(_poolInfo),
            NUM_ACTORS,
            address(this)
        );

        _handler = address(_erc20positionHandler);
    }
}
