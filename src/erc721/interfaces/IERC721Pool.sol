// SPDX-License-Identifier: MIT

pragma solidity 0.8.14;

import { IPool } from 'src/base/interfaces/IPool.sol';

import { IERC721PoolBorrowerActions } from 'src/erc721/interfaces/pool/IERC721PoolBorrowerActions.sol';
import { IERC721PoolLenderActions }   from 'src/erc721/interfaces/pool/IERC721PoolLenderActions.sol';
import { IERC721PoolImmutables }      from 'src/erc721/interfaces/pool/IERC721PoolImmutables.sol';
import { IERC721PoolState }           from 'src/erc721/interfaces/pool/IERC721PoolState.sol';
import { IERC721PoolEvents }          from 'src/erc721/interfaces/pool/IERC721PoolEvents.sol';
import { IERC721PoolErrors }          from 'src/erc721/interfaces/pool/IERC721PoolErrors.sol';

/**
 * @title ERC721 Pool
 */
interface IERC721Pool is
    IPool,
    IERC721PoolLenderActions,
    IERC721PoolBorrowerActions,
    IERC721PoolState,
    IERC721PoolImmutables,
    IERC721PoolEvents,
    IERC721PoolErrors
{

    /**
     *  @notice Initializes a new pool, setting initial state variables.
     *  @param  tokenIds  Enumerates tokenIds to be allowed in the pool.
     *  @param  rate      Initial interest rate of the pool.
     */
    function initialize(
        uint256[] memory tokenIds,
        uint256 rate
    ) external;

}
