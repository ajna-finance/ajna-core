// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.18;

import "@std/console.sol";
import { Pool }              from 'src/base/Pool.sol';
import { ERC20Pool }         from 'src/ERC20Pool.sol';
import { ERC721Pool }        from 'src/ERC721Pool.sol';
import { ERC20PoolFactory }  from 'src/ERC20PoolFactory.sol';
import { ERC721PoolFactory } from 'src/ERC721PoolFactory.sol';
import { PositionManager }   from 'src/PositionManager.sol';

import { NFTCollateralToken }          from '../../utils/Tokens.sol';

import { ERC721PoolPositionHandler }    from './handlers/ERC721PoolPositionHandler.sol';
import { PositionsInvariants }         from './PositionsInvariants.sol';

contract ERC721PoolPositionsInvariants is PositionsInvariants {

    NFTCollateralToken        internal _collateral;
    ERC721Pool                internal _erc721pool;
    ERC721PoolPositionHandler internal _erc721positionHandler;

    function setUp() public override virtual {

        super.setUp();
        
        uint256[] memory tokenIds;
        _collateral        = new NFTCollateralToken();
        _erc20poolFactory  = new ERC20PoolFactory(address(_ajna));
        _erc20impl         = _erc20poolFactory.implementation();
        _erc721poolFactory = new ERC721PoolFactory(address(_ajna));
        _erc721pool        = ERC721Pool(_erc721poolFactory.deployPool(address(_collateral), address(_quote), tokenIds, 0.05 * 10**18));
        _erc721impl        = _erc721poolFactory.implementation();
        _pool              = Pool(address(_erc721pool));
        _positionManager   = new PositionManager(_erc20poolFactory, _erc721poolFactory);

        excludeContract(address(_ajna));
        excludeContract(address(_collateral));
        excludeContract(address(_quote));
        excludeContract(address(_erc20poolFactory));
        excludeContract(address(_erc721poolFactory));
        excludeContract(address(_erc721pool));
        excludeContract(address(_poolInfo));
        excludeContract(address(_erc20impl));
        excludeContract(address(_erc721impl));
        excludeContract(address(_positionManager));

        _erc721positionHandler = new ERC721PoolPositionHandler(
            address(_positionManager),
            address(_erc721pool),
            address(_ajna),
            address(_quote),
            address(_collateral),
            address(_poolInfo),
            NUM_ACTORS,
            address(this)
        );

        _handler = address(_erc721positionHandler);
    }
}
