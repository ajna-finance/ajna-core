// SPDX-License-Identifier: MIT

pragma solidity 0.8.14;

import '../../base/interfaces/IPool.sol';

import './pool/IERC721PoolBorrowerActions.sol';
import './pool/IERC721PoolLenderActions.sol';
import './pool/IERC721PoolImmutables.sol';
import './pool/IERC721PoolState.sol';
import './pool/IERC721PoolEvents.sol';
import './pool/IERC721PoolErrors.sol';

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
