// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.14;

import '@std/Test.sol';

import { ERC20Pool }        from 'src/ERC20Pool.sol';
import { ERC20PoolFactory } from 'src/ERC20PoolFactory.sol';
import { PoolInfoUtils }    from 'src/PoolInfoUtils.sol';

import { Token, BurnableToken }  from '../../../utils/Tokens.sol';
import { InvariantsTestHelpers } from './InvariantsTestHelpers.sol';

abstract contract InvariantsTestBase is InvariantsTestHelpers, Test {

    Token internal _quote;
    Token internal _collateral;

    BurnableToken internal _ajna;

    ERC20Pool        internal _pool;
    ERC20Pool        internal _impl;
    PoolInfoUtils    internal _poolInfo;
    ERC20PoolFactory internal _poolFactory;

    uint256 public currentTimestamp;

    // use current timestamp for invariants
    modifier useCurrentTimestamp {
        vm.warp(currentTimestamp);

        _;
    }

    function setUp() public virtual {
        // Tokens
        _ajna       = new BurnableToken("Ajna", "A");
        _quote      = new Token("Quote", "Q");
        _collateral = new Token("Collateral", "C");

        // Pool
        _poolFactory = new ERC20PoolFactory(address(_ajna));
        _pool        = ERC20Pool(_poolFactory.deployPool(address(_collateral), address(_quote), 0.05 * 10**18));
        _poolInfo    = new PoolInfoUtils();
        _impl        = _poolFactory.implementation();

        currentTimestamp = block.timestamp;
    }

    function setCurrentTimestamp(uint256 currentTimestamp_) external {
        currentTimestamp = currentTimestamp_;
    }
}