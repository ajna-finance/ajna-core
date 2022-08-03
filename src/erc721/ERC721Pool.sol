// SPDX-License-Identifier: MIT

pragma solidity 0.8.14;

import { IERC721Pool } from "./interfaces/IERC721Pool.sol";

import { ScaledPool } from "../base/ScaledPool.sol";

// Added
import { EnumerableSet } from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

contract ERC721Pool is IERC721Pool, ScaledPool {
}
