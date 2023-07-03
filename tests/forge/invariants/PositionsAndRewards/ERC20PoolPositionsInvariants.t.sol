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
import { TokenWithNDecimals }          from '../../utils/Tokens.sol';

import { ERC20PoolPositionHandler }    from './handlers/ERC20PoolPositionHandler.sol';
import { PositionsInvariants }         from './PositionsInvariants.sol';

contract ERC20PoolPositionsInvariants is PositionsInvariants {

    TokenWithNDecimals       internal _collateral;
    ERC20Pool                internal _erc20pool;
    ERC20PoolPositionHandler internal _erc20positionHandler;

    function setUp() public override virtual {

        super.setUp();
        _collateral        = new TokenWithNDecimals("Collateral", "C", uint8(vm.envOr("COLLATERAL_PRECISION", uint256(18))));
        _erc20poolFactory  = new ERC20PoolFactory(address(_ajna));
        _erc20impl         = _erc20poolFactory.implementation();
        _erc721poolFactory = new ERC721PoolFactory(address(_ajna));
        _erc721impl        = _erc721poolFactory.implementation();
        _erc20pool         = ERC20Pool(_erc20poolFactory.deployPool(address(_collateral), address(_quote), 0.05 * 10**18));
        _pool              = Pool(address(_erc20pool));
        _positionManager   = new PositionManager(_erc20poolFactory, _erc721poolFactory);

        excludeContract(address(_ajna));
        excludeContract(address(_collateral));
        excludeContract(address(_quote));
        excludeContract(address(_erc20poolFactory));
        excludeContract(address(_erc721poolFactory));
        excludeContract(address(_erc20pool));
        excludeContract(address(_poolInfo));
        excludeContract(address(_erc20impl));
        excludeContract(address(_erc721impl));
        excludeContract(address(_positionManager));

        _erc20positionHandler = new ERC20PoolPositionHandler(
            address(_positionManager),
            address(_erc20pool),
            address(_ajna),
            address(_quote),
            address(_collateral),
            address(_poolInfo),
            NUM_ACTORS,
            address(this)
        );

        _handler = address(_erc20positionHandler);
    }
}
