// SPDX-License-Identifier: MIT

pragma solidity 0.8.14;

import { Maths } from "./libraries/Maths.sol";

abstract contract FenwickScaleTree {
    /***********************/
    /*** State Variables ***/
    /***********************/

    uint256 constant NUM_BITS  = 13;
    uint256 constant TREE_SIZE = 8192; // size of the tree

    uint256[8193] internal _v; // values
    uint256[8193] internal _s; // scaling

    /**
     *  @notice Retrieves the cumulative scale of the index.
     *  @param  i_ index to scale
     */
    function _scale(uint256 i_) internal view returns (uint256 scaled_) {
        require(i_ >= 0 && i_ < TREE_SIZE, "FW:S:INVALID_INDEX");

        scaled_ = Maths.WAD;
        while (i_ <= TREE_SIZE) {
            if (_s[i_] != 0) scaled_ = Maths.wmul(scaled_, _s[i_]);
            i_  += _lsb(i_);
        }
    }

    /**
     *  @notice Multiplies scaling factor af index i by f.
     *  @param  i_  index to scale
     *  @param  f_ factor to be used when scale
     */
    function _mult(uint256 i_, uint256 f_) internal {
        require(i_ >= 0 && i_ < TREE_SIZE, "FW:M:INVALID_INDEX");
        require(f_ != 0, "FW:M:FACTOR_ZERO");

        i_ += 1;
        uint256 s;
        uint256 j;

        while (i_ > 0) {
            s += (f_ - 1) * _v[i_] * _s[i_];
            _s[i_] = Maths.wmul(f_, _s[i_]);

            j  = i_ + _lsb(i_);
            i_ -= _lsb(i_);
            while (((_lsb(j)) < (_lsb(i_))) || (i_ == 0 && j <= TREE_SIZE)) {
                _v[j] += s;
                s = Maths.wmul(s, _s[j]);
                j += _lsb(j);
            }
        }
    }

    /**
     *  @notice Adds x (WAD) to i'th element (0-based indexing).
     */
    function _addToDeposits(uint256 i_, uint256 x_) internal {
        require(i_ >= 0 && i_ < TREE_SIZE, "FW:A:INVALID_INDEX");

        i_ += 1;
        uint256 sc = _scale(i_);

        while (i_ <= TREE_SIZE) {
            _v[i_] += Maths.wdiv(x_, sc);
            if (_s[i_] != 0) sc = Maths.wdiv(sc, _s[i_]);
            i_ += _lsb(i_);
        }
    }

    /**
     *  @notice Removes x (WAD) from i'th element (0-based indexing).
     */
    function _removeFromDeposits(uint256 i_, uint256 x_) internal {
        require(i_ >= 0 && i_ < TREE_SIZE, "FW:A:INVALID_INDEX");

        i_ += 1;
        uint256 sc = _scale(i_);

        while (i_ <= TREE_SIZE) {
            _v[i_] -= Maths.wdiv(x_, sc);
            sc = Maths.wdiv(sc, _s[i_]);
            i_ += _lsb(i_);
        }
    }

    /**
     *  @notice Finds the scaled cumulative sum of index i.
     *  @param  i_ index
     *  @return s_ scaled cumulative sum of index i 
     */
    function _prefixSum(uint256 i_) internal view returns (uint256 s_) {
        i_ += 1;
        uint256 sc = Maths.WAD;
        uint256 j  = 4096; // 1 << (TREE_SIZE - 1)
        uint256 ii;

        while (j > 0) {
            if (i_ & j != 0) {
                s_ += Maths.wmul(Maths.wmul(sc, _s[ii + j]), _v[ii + j]);
            } else {
                sc = Maths.wmul(sc, _s[ii + j]);
            }

            ii = ii + (i_ & j);
            j = j >> 1;
        }
    }

    /**
     *  @notice Returns sum from start to stop, both inclusive.
     *  @param  start_ start index
     *  @param  stop_  stop index 
     */
    function _rangeSum(uint256 start_, uint256 stop_) internal view returns (uint256) {
        require(start_ >= 0 && start_ < TREE_SIZE, "FW:R:INVALID_START");
        require(stop_ >= start_ && stop_ <= TREE_SIZE,   "FW:R:INVALID_STOP");
        return _prefixSum(stop_) - _prefixSum(start_ - 1);
    }

    /**
     *  @notice Returns total sum of the tree.
     */
    function sum() external view returns (uint256) {
        return _v[TREE_SIZE];
    }

    /**
     *  @notice Find the index of the first element which precedes a specified prefix sum x.
     *  @param  x_ prefix sum
     *  @return m_ index of the first element which precedes x_ 
     */
    function _findSum(uint256 x_) internal view returns (uint256 m_) {
        uint256 i = 4096; // 1 << (TREE_SIZE - 1)
        uint256 ss;
        uint256 sc = Maths.WAD;

        while (i > 0) {
            if (ss + Maths.wmul(Maths.wmul(sc, _s[m_ + i]), _v[m_ + i]) < x_) {
                m_ += i;
                ss += Maths.wmul(Maths.wmul(sc, _s[m_]), _v[m_]);
            } else {
                sc = Maths.wmul(sc, _s[m_ + i]);
            }
            i = i >> 1;
        }
    }

    // Least significant bit
    function _lsb(uint256 i_) internal pure returns (uint256) {
        // "i & (-i)"
        return
            i_ &
            ((i_ ^
                0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff) +
                1);
    }
}