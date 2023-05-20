// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity 0.8.14;

/**
    @title  Maths library
    @notice Internal library containing common maths.
 */
library Maths {

    uint256 internal constant WAD = 1e18;

    function wmul(uint256 x, uint256 y) internal pure returns (uint256) {
        return (x * y + WAD / 2) / WAD;
    }

    function floorWmul(uint256 x, uint256 y) internal pure returns (uint256) {
        return (x * y) / WAD;
    }

    function wdiv(uint256 x, uint256 y) internal pure returns (uint256) {
        return (x * WAD + y / 2) / y;
    }

    function floorWdiv(uint256 x, uint256 y) internal pure returns (uint256) {
        return (x * WAD) / y;
    }

    function max(uint256 x, uint256 y) internal pure returns (uint256) {
        return x >= y ? x : y;
    }

    function min(uint256 x, uint256 y) internal pure returns (uint256) {
        return x <= y ? x : y;
    }

    function wad(uint256 x) internal pure returns (uint256) {
        return x * WAD;
    }

    function rmul(uint256 x, uint256 y) internal pure returns (uint256) {
        return (x * y + 10**27 / 2) / 10**27;
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

    /**********************************/
    /*** Wider Arithmetic Functions ***/
    /**********************************/

    function uminus(
        uint256 i_
    ) internal pure returns (uint256 minusi_) {
        minusi_ = ((i_ ^ 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff) + 1);
    }
    
    /**
     *  @notice Get least significant bit (`LSB`) of integer `i_`.
     *  @dev    Used primarily to decrement the binary index in loops, iterating over range parents.
     *  @param  i_  The integer with which to return the `LSB`.
     */
    function lsb(
        uint256 i_
    ) internal pure returns (uint256 lsb_) {
        if (i_ != 0) {
            // "i & (-i)"
            lsb_ = i_ & uminus(i_);
        }
    }

    function fullMul (uint256 x, uint256 y)
        public pure returns (uint256 l, uint256 h)
    {
        uint mm = mulmod (x, y, 2**256 - 1);
        unchecked {
        l = x * y;
        h = mm - l;
        }
        if (mm < l) h -= 1;
    }

    function mulDiv (uint256 x, uint256 y, uint256 z)
        public pure returns (uint256) {
        uint r = 1;
        (uint256 l, uint256 h) = fullMul(x, y);
        unchecked {
        require (h < z);
        uint mm = mulmod (x, y, z);
        if (mm > l) h -= 1;
        l -= mm;
        uint pow2 = lsb(z);
        z /= pow2;
        l /= pow2;
        l += h * (uminus(pow2) / pow2 + 1);
        r *= 2 - z * r;
        r *= 2 - z * r;
        r *= 2 - z * r;
        r *= 2 - z * r;
        r *= 2 - z * r;
        r *= 2 - z * r;
        r *= 2 - z * r;
        r *= 2 - z * r;
        return l * r;
        }
    } 
}
