// SPDX-License-Identifier: MIT

pragma solidity 0.8.14;

import { Maths } from "./libraries/Maths.sol";

abstract contract FenwickTree {
    uint256 public constant SIZE = 8192;

    uint256[8193] public _values;  // values
    uint256[8193] public _scaling; // scaling

    function _scale(uint256 i_) internal view returns (uint256 a_) {
        require(i_ >= 0 && i_ < SIZE, "FW:S:INVALID_INDEX");

        a_ = Maths.WAD;
        uint256 scaled;
        while (i_ <= SIZE) {
            scaled = _scaling[i_];
            if (scaled != 0) a_ = Maths.wmul(a_, scaled);
            i_ += _lsb(i_);
        }
    }


    function _mult(uint256 i_, uint256 f_) internal {
        require(i_ >= 0 && i_ < SIZE, "FW:M:INVALID_INDEX");
        require(f_ != 0, "FW:M:FACTOR_ZERO");

        i_ += 1;
        uint256 sum;
        uint256 j;
        uint256 df = f_ - Maths.WAD;

        uint256 scaledI;
        uint256 scaledJ;

        while (i_ > 0) {
            scaledI =  _scaling[i_];
            sum = scaledI != 0 ? sum + Maths.wmul(Maths.wmul(df, _values[i_]), scaledI) : sum + Maths.wmul(df, _values[i_]);
            _scaling[i_] = scaledI != 0 ? Maths.wmul(f_, scaledI) : f_;
            j = i_ + _lsb(i_);
            i_ -= _lsb(i_);
            while ((_lsb(j) < _lsb(i_)) || (i_ == 0 && j <= SIZE)) {
                _values[j] += sum;
                scaledJ = _scaling[j];
                if (scaledJ != 0) sum = Maths.wmul(sum, scaledJ);
                j += _lsb(j);
            }
        }
    }

    function _add(uint256 i_, uint256 x_) internal {
        require(i_ >= 0 && i_ < SIZE, "FW:A:INVALID_INDEX");

        i_ += 1;
        uint256 j = 8192; // 1 << 13
        uint256 ii;
        uint256 sc = Maths.WAD;

        uint256 scaled;

        while (j > 0) {
            if (((i_ - 1) & j) != 0) {
                ii += j;
            } else {
                scaled = _scaling[ii + j];
                if (scaled != 0) sc = Maths.wmul(sc, scaled);
                _values[ii + j] += Maths.wdiv(x_, sc);
            }
            j = j >> 1;
        }
    }

    function _remove(uint256 i_, uint256 x_) internal {
        require(i_ >= 0 && i_ < SIZE, "FW:A:INVALID_INDEX");

        i_ += 1;
        uint256 j = 8192; // 1 << 13
        uint256 ii;
        uint256 sc = Maths.WAD;

        uint256 scaled;

        while (j > 0) {
            if (((i_ - 1) & j) != 0) {
                ii += j;
            } else {
                scaled = _scaling[ii + j];
                if (scaled != 0) sc = Maths.wmul(sc, scaled);
                _values[ii + j] -= Maths.wdiv(x_, sc);
            }
            j = j >> 1;
        }
    }

    function _prefixSum(uint256 i_) internal view returns (uint256 s_) {
        i_ += 1;
        uint256 sc = Maths.WAD;
        uint256 j  = 8192; // 1 << 13
        uint256 ii;

        uint256 scaled;

        while (j > 0 && ii + j <= SIZE) {
            scaled = _scaling[ii + j];
            if (i_ & j != 0) {
                s_ = scaled != 0 ? s_ + Maths.wmul(Maths.wmul(sc, scaled), _values[ii + j]) : s_ + Maths.wmul(sc, _values[ii + j]);
            } else {
                if (scaled != 0) sc = Maths.wmul(sc, scaled);
            }

            ii = ii + (i_ & j);
            j = j >> 1;
        }
    }

    function _rangeSum(uint256 start_, uint256 stop_) internal view returns (uint256) {
        require(start_ >= 0 && start_ < SIZE,      "FW:R:INVALID_START");
        require(stop_ >= start_ && stop_ <= SIZE,  "FW:R:INVALID_STOP");
        return _prefixSum(stop_) - _prefixSum(start_ - 1);
    }

    function _findSum(uint256 x_) internal view returns (uint256 m_) {
        uint256 i = 4096; // 1 << (_numBits - 1) = 1 << (13 - 1) = 4096
        uint256 ss;
        uint256 sc = Maths.WAD;

        uint256 scaledM;
        uint256 scaledMInc;
        uint256 ssCond;

        while (i > 0) {
            scaledMInc = _scaling[m_ + i];
            ssCond = scaledMInc != 0 ? ss + Maths.wmul(Maths.wmul(sc, scaledMInc), _values[m_ + i]) : ss + Maths.wmul(sc, _values[m_ + i]);
            if (ssCond < x_) {
                m_ += i;
                scaledM = _scaling[m_];
                ss = scaledM != 0 ? ss + Maths.wmul(Maths.wmul(sc, scaledM), _values[m_]) : ss + Maths.wmul(sc, _values[m_]);
            } else {
                if (scaledMInc != 0) sc = Maths.wmul(sc, scaledMInc);
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
        return _values[SIZE];
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