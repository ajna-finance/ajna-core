// SPDX-License-Identifier: MIT

pragma solidity 0.8.14;

import { IPoolLenderActions }         from './commons/IPoolLenderActions.sol';
import { IPoolLiquidationActions }    from './commons/IPoolLiquidationActions.sol';
import { IPoolReserveAuctionActions } from './commons/IPoolReserveAuctionActions.sol';
import { IPoolImmutables }            from './commons/IPoolImmutables.sol';
import { IPoolState }                 from './commons/IPoolState.sol';
import { IPoolDerivedState }          from './commons/IPoolDerivedState.sol';
import { IPoolEvents }                from './commons/IPoolEvents.sol';
import { IPoolErrors }                from './commons/IPoolErrors.sol';
import { IERC3156FlashLender }        from './IERC3156FlashLender.sol';

/**
 * @title Base Pool
 */
interface IPool is
    IPoolLenderActions,
    IPoolLiquidationActions,
    IPoolReserveAuctionActions,
    IPoolImmutables,
    IPoolState,
    IPoolDerivedState,
    IPoolEvents,
    IPoolErrors,
    IERC3156FlashLender
{

}

enum PoolType { ERC20, ERC721 }

interface IERC20Token {
    function balanceOf(address account) external view returns (uint256);
    function burn(uint256 amount) external;
    function decimals() external view returns (uint8);
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) external returns (bool);
}

interface IERC721Token {
    function safeTransferFrom(
        address from,
        address to,
        uint256 tokenId
    ) external;
}
