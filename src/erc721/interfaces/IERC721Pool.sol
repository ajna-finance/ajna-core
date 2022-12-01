// SPDX-License-Identifier: MIT

pragma solidity 0.8.14;

import '../../base/interfaces/IPool.sol';

import './pool/IERC721PoolBorrowerActions.sol';
import './pool/IERC721PoolLenderActions.sol';
import './pool/IERC721PoolState.sol';
import './pool/IERC721PoolEvents.sol';
import './pool/IERC721PoolErrors.sol';
import '../../base/interfaces/pool/IPoolErrors.sol';
import '../../base/interfaces/pool/IPoolEvents.sol';
import '../../base/interfaces/pool/IPoolBorrowerActions.sol';
import '../../base/interfaces/pool/IPoolLiquidationActions.sol';

/**
 * @title ERC721 Pool
 */
interface IERC721Pool is
    IERC721PoolLenderActions,
    IERC721PoolBorrowerActions,
    IPoolBorrowerActions,
    IPoolLiquidationActions,
    IERC721PoolState,
    IERC721PoolEvents,
    IERC721PoolErrors,
    IPoolErrors,
    IPoolEvents
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

    function take(
        address        borrower,
        uint256        maxAmount,
        address        callee,
        bytes calldata data
    ) external;

    /**
     *  @notice Called by lenders to claim unencumbered collateral from a price bucket.
     *  @param  amount   The amount of unencumbered collateral (or the number of NFT tokens) to claim.
     *  @param  index    The bucket index from which unencumbered collateral will be removed.
     *  @return lpAmount The amount of LP used for removing collateral amount.
     */
    function removeCollateral(
        uint256 amount,
        uint256 index
    ) external returns (uint256 lpAmount);

    /**
     *  @notice Called by borrowers to remove an amount of collateral.
     *  @param  amount The amount of collateral in deposit tokens (or number of NFTs) to be removed from a position.
     */
    function pullCollateral(
        uint256 amount
    ) external;

}
