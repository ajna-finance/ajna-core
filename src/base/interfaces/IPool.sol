// SPDX-License-Identifier: MIT

pragma solidity 0.8.14;

import './pool/IPoolLenderActions.sol';
import './pool/IPoolReserveAuctionActions.sol';
import './pool/IPoolImmutables.sol';
import './pool/IPoolState.sol';
import './pool/IPoolDerivedState.sol';
import './pool/IPoolEvents.sol';
import './pool/IPoolErrors.sol';
import './pool/IPoolStateInfo.sol';

/**
 * @title Base Pool
 */
interface IPool is
    IPoolLenderActions,
    IPoolReserveAuctionActions,
    IPoolImmutables,
    IPoolState,
    IPoolDerivedState,
    IPoolEvents,
    IPoolErrors,
    IPoolStateInfo
{

}

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
