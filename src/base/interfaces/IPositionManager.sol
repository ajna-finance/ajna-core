// SPDX-License-Identifier: MIT

pragma solidity 0.8.14;

import { IPositionManagerDerivedState } from 'src/base/interfaces/position/IPositionManagerDerivedState.sol';
import { IPositionManagerEvents }       from 'src/base/interfaces/position/IPositionManagerEvents.sol';
import { IPositionManagerOwnerActions } from 'src/base/interfaces/position/IPositionManagerOwnerActions.sol';
/**
 *  @title Position Manager Interface
 */
interface IPositionManager is
    IPositionManagerDerivedState,
    IPositionManagerEvents,
    IPositionManagerOwnerActions
{

    /**
     * @notice User failed to add liquidity in an index to their NFT.
     */
    error AddLiquidityFailed();

    /**
     * @notice User attempting to burn a LPB NFT before removing liquidity.
     */
    error LiquidityNotRemoved();

    /**
     * @notice User not authorized to interact with the specified NFT.
     */
    error NoAuth();

    /**
     * @notice User attempted to mint an NFT pointing to a pool that wasn't deployed by an Ajna factory.
     */
    error NotAjnaPool();

    /**
     * @notice User failed to remove liquidity in an index from their NFT.
     */
    error RemoveLiquidityFailed();

    /**
     * @notice User attempting to interact with a pool that doesn't match the pool associated with the tokenId.
     */
    error WrongPool();

}
