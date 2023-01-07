// SPDX-License-Identifier: MIT

pragma solidity 0.8.14;

import { IPoolLenderActions }         from './pool/IPoolLenderActions.sol';
import { IPoolLiquidationActions }    from './pool/IPoolLiquidationActions.sol';
import { IPoolReserveAuctionActions } from './pool/IPoolReserveAuctionActions.sol';
import { IPoolImmutables }            from './pool/IPoolImmutables.sol';
import { IPoolState }                 from './pool/IPoolState.sol';
import { IPoolDerivedState }          from './pool/IPoolDerivedState.sol';
import { IPoolEvents }                from './pool/IPoolEvents.sol';
import { IPoolErrors }                from './pool/IPoolErrors.sol';
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
