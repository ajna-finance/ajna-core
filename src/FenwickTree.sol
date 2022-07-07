// SPDX-License-Identifier: MIT

pragma solidity 0.8.14;

import { Maths } from "./libraries/Maths.sol";

abstract contract FenwickTree {
    uint256 public _numBits = 13;
    uint256 public _n = 8192;
    uint256[8193] public _v; // values
    uint256[] public _s; // scaling

    function _scale(uint256 i_) internal view returns (uint256 a_) {
        require(i_ >= 0 && i_ < _n, "FW:S:INVALID_INDEX");

        a_ = Maths.WAD;
        while (i_ <= _n) {
            a_ = Maths.wmul(a_, _s[i_]);
            i_ += _lsb(i_);
        }
    }


    function _mult(uint256 i_, uint256 f_) internal {
        require(i_ >= 0 && i_ < _n, "FW:M:INVALID_INDEX");
        require(f_ != 0, "FW:M:FACTOR_ZERO");

        i_ += 1;
        uint256 sum;
        uint256 j;
        uint256 df = f_ - Maths.WAD;

        while (i_ > 0) {
            sum += Maths.wmul(Maths.wmul(df, _v[i_]), _s[i_]);
            _s[i_] = Maths.wmul(f_, _s[i_]);
            j = i_ + _lsb(i_);
            i_ -= _lsb(i_);
            while ((_lsb(j) < _lsb(i_)) || (i_ == 0 && j <= _n)) {
                _v[j] += sum;
                sum = Maths.wmul(sum, _s[j]);
                j += _lsb(j);
            }
        }
    }

    function _add(uint256 i_, uint256 x_) internal {
        require(i_ >= 0 && i_ < _n, "FW:A:INVALID_INDEX");

        i_ += 1;
        uint256 j = 8192; // 1 << 13
        uint256 ii;
        uint256 sc = Maths.WAD;

        while (j > 0) {
            if (((i_ - 1) & j) != 0) {
                ii += j;
            } else {
                sc = Maths.wmul(sc, _s[ii + j]);
                _v[ii + j] += Maths.wdiv(x_, sc);
            }
            j = j >> 1;
        }
    }

    function _remove(uint256 i_, uint256 x_) internal {
        require(i_ >= 0 && i_ < _n, "FW:A:INVALID_INDEX");

        i_ += 1;
        uint256 j = 8192; // 1 << 13
        uint256 ii;
        uint256 sc = Maths.WAD;

        while (j > 0) {
            if (((i_ - 1) & j) != 0) {
                ii += j;
            } else {
                sc = Maths.wmul(sc, _s[ii + j]);
                _v[ii + j] -= Maths.wdiv(x_, sc);
            }
            j = j >> 1;
        }
    }

    function _prefixSum(uint256 i_) internal view returns (uint256 s_) {
        i_ += 1;
        uint256 sc = Maths.WAD;
        uint256 j  = 8192; // 1 << 13
        uint256 ii;

        while (j > 0 && ii + j <= _n) {
            if (i_ & j != 0) {
                s_ += Maths.wmul(Maths.wmul(sc, _s[ii + j]), _v[ii + j]);
            } else {
                sc = Maths.wmul(sc, _s[ii + j]);
            }

            ii = ii + (i_ & j);
            j = j >> 1;
        }
    }

    function _rangeSum(uint256 start_, uint256 stop_) internal view returns (uint256) {
        require(start_ >= 0 && start_ < _n, "FW:R:INVALID_START");
        require(stop_ >= start_ && stop_ <= _n,   "FW:R:INVALID_STOP");
        return _prefixSum(stop_) - _prefixSum(start_ - 1);
    }

    function _findSum(uint256 x_) internal view returns (uint256 m_) {
        uint256 i = 4096; // 1 << (_numBits - 1)
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
        if (i_ == 0) return 0;
        // "i & (-i)"
        return
            i_ &
            ((i_ ^
                0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff) +
                1);
    }

    function treeSum() external view returns (uint256) {
        return _v[_n];
    }

    function get(uint256 i_) public view returns (uint256 m_) {
        return _rangeSum(i_, i_);
    }

    function scale(uint256 i_) public view returns (uint256 a_) {
        return _scale(i_);
    }

    function findSum(uint256 x_) public view returns (uint256 m_) {
        return _findSum(x_);
    }

    function prefixSum(uint256 i_) public view returns (uint256 s_) {
        return _prefixSum(i_);
    }

    function lsb(uint256 i_) public pure returns (uint256) {
        // "i & (-i)"
        return _lsb(i_);
    }
}