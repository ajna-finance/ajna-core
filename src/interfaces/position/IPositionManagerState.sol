// SPDX-License-Identifier: MIT

pragma solidity 0.8.18;

/**
 * @title Positions Manager State
 */
interface IPositionManagerState {

    /**
     * @dev Struct tracking a Position's global state.
     * @param pool The pool address associated with the position.
     * @param adjustmentTime The time of last adjustment to the position.
     */
    struct TokenInfo {
        address pool;       // pool address associated with the position
        uint96 adjustmentTime; // time of last adjustment to the position
    }

}

/// @dev Struct holding Position `LP` state.
struct Position {
    uint256 lps;         // [WAD] position LP
    uint256 depositTime; // deposit time for position
}
