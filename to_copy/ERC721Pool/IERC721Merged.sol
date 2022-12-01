// SPDX-License-Identifier: AGPL-3.0-only

pragma solidity 0.8.14;

import 'src/base/interfaces/IPool.sol';
import 'src/base/interfaces/IERC3156FlashLender.sol';
import 'src/erc20/interfaces/IERC20Pool.sol';

interface IERC20PoolMerged is IERC20Pool, IPoolState, IPoolLenderActions, IPoolReserveAuctionActions, IPoolImmutables, IPoolDerivedState, IPoolStateInfo, IERC3156FlashLender {
    function multicall(bytes[] calldata data) external virtual returns (bytes[] memory results);
}