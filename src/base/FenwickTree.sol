// SPDX-License-Identifier: MIT

pragma solidity 0.8.14;

import { Maths } from "../libraries/Maths.sol";

abstract contract FenwickTree {
    uint256 public constant SIZE = 8192;

    /**
     *  @notice Array of values in the FenwickTree.
     */
    uint256[8193] internal values;  // values
    /**
     *  @notice Array of values in the nested scaling FenwickTree.
     */
    uint256[8193] internal scaling; // scaling

    function _scale(uint256 i_) internal view returns (uint256 a_) {
        require(i_ < SIZE, "FW:S:INVALID_INDEX");

        a_ = Maths.WAD;
        uint256 scaled;
        while (i_ <= SIZE) {
            scaled = scaling[i_];
            if (scaled != 0) a_ = Maths.wmul(a_, scaled);
            i_ += _lsb(i_);
        }
    }


    // TODO: add check to ensure scaling factor is at least a WAD? 
    function _mult(uint256 i_, uint256 f_) internal {
        require(i_ < SIZE, "FW:M:INVALID_INDEX");
        require(f_ != 0,   "FW:M:FACTOR_ZERO");

        i_ += 1;
        uint256 sum = 0;
        uint256 j;
        uint256 df = f_ - Maths.WAD;

        uint256 scaledI;
        uint256 scaledJ;

        while (i_ > 0) {
            scaledI =  scaling[i_];
            sum = scaledI != 0 ? sum + Maths.wmul(Maths.wmul(df, values[i_]), scaledI) : sum + Maths.wmul(df, values[i_]);
            scaling[i_] = scaledI != 0 ? Maths.wmul(f_, scaledI) : f_;
            uint256 lsbI = _lsb(i_);
            j = i_ + lsbI;
            i_ -= lsbI;
            uint256 lsbJ = _lsb(j);
            //slither-disable-next-line incorrect-equality
            while ((lsbJ < _lsb(i_)) || (i_ == 0 && j <= SIZE)) {
                values[j] += sum;
                scaledJ = scaling[j];
                if (scaledJ != 0) sum = Maths.wmul(sum, scaledJ);
                j += lsbJ;
                lsbJ = _lsb(j);
            }
        }
    }

    function _add(uint256 i_, uint256 x_) internal {
        require(i_ < SIZE, "FW:A:INVALID_INDEX");

        i_ += 1;
        uint256 j     = 8192; // 1 << 13
        uint256 ii    = 0;
        uint256 sc    = Maths.WAD;
        uint256 index = 8192;

        uint256 scaled;

        while (j > 0) {
            if (((i_ - 1) & j) != 0) {
                ii += j;
            } else {
                scaled = scaling[index];
                if (scaled != 0) sc = Maths.wmul(sc, scaled);
                values[index] += Maths.wdiv(x_, sc);
            }
            j = j >> 1;
            index = ii + j;
        }
    }

    function _remove(uint256 i_, uint256 x_) internal {
        require(i_ < SIZE, "FW:R:INVALID_INDEX");

        i_ += 1;
        uint256 j = 8192; // 1 << 13
        uint256 ii = 0;
        uint256 sc = Maths.WAD;
        uint256 index = 8192;

        uint256 scaled;

        while (j > 0) {
            if (((i_ - 1) & j) != 0) {
                ii += j;
            } else {
                scaled = scaling[index];
                if (scaled != 0) sc = Maths.wmul(sc, scaled);
                values[index] -= Maths.wdiv(x_, sc);
            }
            j = j >> 1;
            index = ii + j;
        }
    }

    function _prefixSum(uint256 i_) internal view returns (uint256 s_) {
        i_ += 1;
        uint256 sc = Maths.WAD;
        uint256 j  = 8192; // 1 << 13
        uint256 ii;
        uint256 index = 8192;

        uint256 scaled;

        while (j > 0 && index <= SIZE) {
            scaled = scaling[index];
            if (i_ & j != 0) {
                s_ = scaled != 0 ? s_ + Maths.wmul(Maths.wmul(sc, scaled), values[index]) : s_ + Maths.wmul(sc, values[index]);
            } else {
                if (scaled != 0) sc = Maths.wmul(sc, scaled);
            }

            ii = ii + (i_ & j);
            j = j >> 1;
            index = ii + j;
        }
    }

    function _rangeSum(uint256 start_, uint256 stop_) internal view returns (uint256) {
        require(start_ < SIZE, "FW:R:INVALID_START");
        require(stop_ >= start_ && stop_ <= SIZE,  "FW:R:INVALID_STOP");
        return _prefixSum(stop_) - _prefixSum(start_ - 1);
    }

    function _valueAt(uint256 i_) internal view returns (uint256 s_) {
        require(i_ < SIZE, "FW:V:INVALID_INDEX");

        uint256 j  = i_;
        uint256 k  = 1;

        i_ += 1;
        s_ = values[i_];

        uint256 scaled;
        while (j & k != 0) {
            scaled = scaling[j];
            s_ = scaled != 0 ? s_ - Maths.wmul(scaled, values[j]) : s_ - values[j];
            j  = j - k;
            k  = k << 1;
        }
        while (i_ <= SIZE) {
            scaled = scaling[i_];
            if (scaled != 0) s_ = Maths.wmul(scaled, s_);
            i_ += _lsb(i_);
        }
    }

    // TODO: rename this to findIndexOfSum
    // TODO: should this revert if failed to find a value past a given index instead of SIZE?
    function _findSum(uint256 x_) internal view returns (uint256 m_) {
        uint256 i     = 4096; // 1 << (_numBits - 1) = 1 << (13 - 1) = 4096
        uint256 ss    = 0;
        uint256 sc    = Maths.WAD;
        uint256 index = 4096;

        uint256 scaledM;
        uint256 scaledMInc;
        uint256 ssCond;

        while (i > 0) {
            scaledMInc = scaling[index];
            ssCond = scaledMInc != 0 ? ss + Maths.wmul(Maths.wmul(sc, scaledMInc), values[index]) : ss + Maths.wmul(sc, values[index]);
            if (ssCond < x_) {
                m_ += i;
                scaledM = scaling[m_];
                ss = scaledM != 0 ? ss + Maths.wmul(Maths.wmul(sc, scaledM), values[m_]) : ss + Maths.wmul(sc, values[m_]);
            } else {
                if (scaledMInc != 0) sc = Maths.wmul(sc, scaledMInc);
            }
            i = i >> 1;
            index = m_ + i;
        }
    }

    // Least significant bit
    function _lsb(uint256 i_) internal pure returns (uint256 lsb_) {
        if (i_ != 0) {
            // "i & (-i)"
            lsb_ = i_ & ((i_ ^ 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff) + 1);
        }
    }

    function _treeSum() internal view returns (uint256) {
        return values[SIZE];
    }
}
