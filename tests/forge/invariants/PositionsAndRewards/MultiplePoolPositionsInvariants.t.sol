// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.18;

import "@std/console.sol";

import { Pool }              from 'src/base/Pool.sol';
import { ERC20Pool }         from 'src/ERC20Pool.sol';

import { ERC20PoolPositionHandler }    from './handlers/ERC20PoolPositionHandler.sol';
import { PositionsInvariants }         from './PositionsInvariants.sol';


contract MultiplePoolPositionsInvariants is PositionsInvariants {

    TokenWithNDecimals       internal _collateral;
    ERC20Pool                internal _erc20pool;
    ERC20PoolPositionHandler internal _erc20positionHandler;

    function setUp() public override virtual {
    
    }

}
