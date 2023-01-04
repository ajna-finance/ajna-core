// SPDX-License-Identifier: MIT

pragma solidity 0.8.14;

import 'src/base/interfaces/pool/IPoolLenderActions.sol';
import 'src/base/interfaces/pool/IPoolLiquidationActions.sol';
import 'src/base/interfaces/pool/IPoolReserveAuctionActions.sol';
import 'src/base/interfaces/pool/IPoolImmutables.sol';
import 'src/base/interfaces/pool/IPoolState.sol';
import 'src/base/interfaces/pool/IPoolDerivedState.sol';
import 'src/base/interfaces/pool/IPoolEvents.sol';
import 'src/base/interfaces/pool/IPoolErrors.sol';
import 'src/base/interfaces/pool/IPoolInternals.sol';
import 'src/base/interfaces/IERC3156FlashLender.sol';

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
