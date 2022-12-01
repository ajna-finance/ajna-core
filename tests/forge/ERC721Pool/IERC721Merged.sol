// SPDX-License-Identifier: AGPL-3.0-only

pragma solidity 0.8.14;

import 'src/base/interfaces/IPool.sol';
import 'src/base/interfaces/IERC3156FlashLender.sol';
import 'src/erc721/interfaces/IERC721Pool.sol';

interface IERC721PoolMerged is IERC721Pool, IPoolState, IPoolLenderActions, IPoolReserveAuctionActions, IPoolImmutables, IPoolDerivedState, IPoolStateInfo, IERC3156FlashLender {
    function pool () external returns (address);
    function multicall(bytes[] calldata data) external returns (bytes[] memory results);
    function isSubset () external returns (bool);
}