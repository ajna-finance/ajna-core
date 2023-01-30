
// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.14;

import '@std/Test.sol';
import "forge-std/console.sol";

import { ERC20Pool }        from 'src/ERC20Pool.sol';
import { ERC20PoolFactory } from 'src/ERC20PoolFactory.sol';
import { Token }            from '../../../utils/Tokens.sol';
import { PoolInfoUtils }    from 'src/PoolInfoUtils.sol';
import { InvariantTest } from '../InvariantTest.sol';


contract BaseHandler is InvariantTest, Test {

    // Pool
    ERC20Pool   internal _pool;
    PoolInfoUtils   internal _poolInfo;

    // Tokens
    Token   internal _quote;
    Token   internal _collateral;

    // Modifiers
    address   internal _actor;
    uint256   internal _lenderBucketIndex;
    uint256   internal _limitIndex;
    address[] public   _actors;

    // Logging
    mapping(bytes32 => uint256) public numberOfCalls;

    constructor(address pool, address quote, address collateral, address poolInfo) {
        // Pool
        _pool       = ERC20Pool(pool);
        _poolInfo   = PoolInfoUtils(poolInfo);

        // Tokens
        _quote      = Token(quote);
        _collateral = Token(collateral);
    }

    /**************************************************************************************************************************************/
    /*** Helper Functions                                                                                                               ***/
    /**************************************************************************************************************************************/

    function constrictToRange(
        uint256 x,
        uint256 min,
        uint256 max
    ) pure public returns (uint256 result) {
        require(max >= min, "MAX_LESS_THAN_MIN");

        uint256 size = max - min;

        if (size == 0) return min;            // Using max would be equivalent as well.
        if (max != type(uint256).max) size++; // Make the max inclusive.

        // Ensure max is inclusive in cases where x != 0 and max is at uint max.
        if (max == type(uint256).max && x != 0) x--; // Accounted for later.

        if (x < min) x += size * (((min - x) / size) + 1);

        result = min + ((x - min) % size);

        // Account for decrementing x to make max inclusive.
        if (max == type(uint256).max && x != 0) result++;
    }

}