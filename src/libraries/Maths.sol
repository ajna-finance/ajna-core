// SPDX-License-Identifier: MIT
pragma solidity 0.8.14;

library Maths {

    /**********************************/
    /*** Unsigned Integer Functions ***/
    /**********************************/

    uint256 public constant WAD = 10**18;
    uint256 public constant RAY = 10**27;
    uint256 public constant RAD = 10**45;

    function wmul(uint256 x, uint256 y) internal pure returns (uint256) {
        return (x * y + 10**18 / 2) / 10**18;
    }

    function wdiv(uint256 x, uint256 y) internal pure returns (uint256) {
        return (x * 10**18 + y / 2) / y;
    }

    function max(uint256 x, uint256 y) internal pure returns (uint256) {
        return x >= y ? x : y;
    }

    function min(uint256 x, uint256 y) internal pure returns (uint256) {
        return x <= y ? x : y;
    }

    function wad(uint256 x) internal pure returns (uint256) {
        return x * 10**18;
    }

    function ray(uint256 x) internal pure returns (uint256) {
        return x * 10**27;
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

    /** @notice Divides a WAD by a RAY and returns a WAD */
    function wrdivw(uint256 x, uint256 y) internal pure returns (uint256) {
        return (x * 1e27 + y / 2) / y;
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

    function wpow(uint256 x, uint256 n) internal pure returns (uint256 z) {
        z = n % 2 != 0 ? x : 10**18;

        for (n /= 2; n != 0; n /= 2) {
            x = wmul(x, x);

            if (n % 2 != 0) {
                z = wmul(z, x);
            }
        }
    }

    function rad(uint256 x) internal pure returns (uint256) {
        return x * 10**45;
    }

    function wadToRay(uint256 x) internal pure returns (uint256) {
        return x * 10**9;
    }

    function wadToRad(uint256 x) internal pure returns (uint256) {
        return x * 10**27;
    }

    function rayToWad(uint256 x) internal pure returns (uint256) {
        return (x + 10**9 / 2) / 10**9;
    }

    function rayToRad(uint256 x) internal pure returns (uint256) {
        return x * 10**18;
    }

    function radToWad(uint256 x) internal pure returns (uint256) {
        return (x + 10**27 / 2) / 10**27;
    }

    function radToWadTruncate(uint256 x) internal pure returns (uint256) {
        return x / 10**27;
    }

    function radToRay(uint256 x) internal pure returns (uint256) {
        return (x + 10**18 / 2) / 10**18;
    }

    /**
     * @notice Round up a fraction to the nearest integer
     * @dev Doesn't check over or underflows
     */
    function divRoundingUp(uint256 x, uint256 y) internal pure returns (uint256 z) {
        assembly {
            z := add(div(x, y), gt(mod(x, y), 0))
        }
    }

    /**
     * @notice Round up a fraction to the nearest integer
     * @dev Based upon OZ Math.ceilDiv()
     */
    function divRoundingUpSafe(uint256 a, uint256 b) internal pure returns (uint256) {
        // (a + b - 1) / b can overflow on addition, so we distribute.
        return a / b + (a % b == 0 ? 0 : 1);
    }

    /**
     * @notice Convert a WAD to an integer, rounding down
     */
    function wadToIntRoundingDown(uint256 a) internal pure returns (uint256) {
        return wdiv(a, 10 ** 18) / 10 ** 18;
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
