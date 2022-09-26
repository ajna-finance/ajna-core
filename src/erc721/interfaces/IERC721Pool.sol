// SPDX-License-Identifier: MIT
pragma solidity 0.8.14;

import '../../base/interfaces/IAjnaPool.sol';

import './pool/IERC721PoolBorrowerActions.sol';
import './pool/IERC721PoolLenderActions.sol';
import './pool/IERC721PoolLiquidationsActions.sol';
import './pool/IERC721PoolState.sol';
import './pool/IERC721PoolEvents.sol';
import './pool/IERC721PoolErrors.sol';

/**
 * @title Ajna ERC20 Pool
 */
interface IERC721Pool is
    IAjnaPool,
    IERC721PoolLenderActions,
    IERC721PoolBorrowerActions,
    IERC721PoolLiquidationsActions,
    IERC721PoolState,
    IERC721PoolEvents,
    IERC721PoolErrors
{


    /**
     *  @notice Called by deployNFTSubsetPool()
     *  @dev    Used to initialize pools that only support a subset of tokenIds
     *  @param  tokenIds         Enumerates tokenIds to be allowed in the pool.
     *  @param  interestRate     Initial interest rate of the pool.
     *  @param  ajnaTokenAddress Address of the Ajna token.
     */
    function initializeSubset(
        uint256[] memory tokenIds,
        uint256 interestRate,
        address ajnaTokenAddress
    ) external;

}
