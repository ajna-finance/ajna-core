// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity 0.8.14;

/**
    @title  Maths library
    @notice Internal library containing common maths.
 */
library Maths {

    uint256 internal constant WAD = 1e18;
    uint256 internal constant RAY = 10**27;

    function wmul(uint256 x, uint256 y) internal pure returns (uint256) {
        return (x * y + 1e18 / 2) / 1e18;
    }

    function wdiv(uint256 x, uint256 y) internal pure returns (uint256) {
        return (x * 1e18 + y / 2) / y;
    }

    function max(uint256 x, uint256 y) internal pure returns (uint256) {
        return x >= y ? x : y;
    }

    function min(uint256 x, uint256 y) internal pure returns (uint256) {
        return x <= y ? x : y;
    }

    function wad(uint256 x) internal pure returns (uint256) {
        return x * 1e18;
    }

    function rmul(uint256 x, uint256 y) internal pure returns (uint256) {
        return (x * y + 10**27 / 2) / 10**27;
    }

    function rdiv(uint256 x, uint256 y) internal pure returns (uint256) {
        return (x * 10**27 + y / 2) / y;
    }

    /** @notice Divides a WAD by a RAY and returns a RAY */
    function wrdivr(uint256 x, uint256 y) internal pure returns (uint256) {
        return (x * 1e36 + y / 2) / y;
    }

    /** @notice Divides a WAD by a WAD and returns a RAY */
    function wwdivr(uint256 x, uint256 y) internal pure returns (uint256) {
        return (x * 1e27 + y / 2) / y;
    }

    /** @notice Divides a RAY by another RAY and returns a WAD */
    function rrdivw(uint256 x, uint256 y) internal pure returns (uint256) {
        return (x * 1e18 + y / 2) / y;
    }

    /** @notice Divides a RAY by a WAD and returns a WAD */
    function rwdivw(uint256 x, uint256 y) internal pure returns (uint256) {
        return (x * 1e9 + y / 2) / y;
    }

    function rpow(uint256 x, uint256 n) internal pure returns (uint256 z) {
        z = n % 2 != 0 ? x : 10**27;

        for (n /= 2; n != 0; n /= 2) {
            x = rmul(x, x);

            if (n % 2 != 0) {
                z = rmul(z, x);
            }
        }
    }

    function wadToRay(uint256 x) internal pure returns (uint256) {
        return x * 10**9;
    }

    function rayToWad(uint256 x) internal pure returns (uint256) {
        return (x + 10**9 / 2) / 10**9;
    }

    /*************************/
    /*** Integer Functions ***/
    /*************************/

    function maxInt(int256 x, int256 y) internal pure returns (int256) {
        return x >= y ? x : y;
    }

    function minInt(int256 x, int256 y) internal pure returns (int256) {
        return x <= y ? x : y;
    }

}
