// SPDX-License-Identifier: MIT

pragma solidity 0.8.14;

import { Maths } from "../libraries/Maths.sol";

abstract contract FenwickTree {
    /**
     *  @notice size of the FenwickTree.
     */
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
        require(i_ >= 0 && i_ < SIZE, "FW:S:INVALID_INDEX");

        a_ = Maths.WAD;
        uint256 scaled;
        while (i_ <= SIZE) {
            scaled = scaling[i_];
            if (scaled != 0) a_ = Maths.wmul(a_, scaled);
            i_ += _lsb(i_);
        }
    }
 
    /**
     *  @notice Scale values in the tree from the index provided, upwards.
     *  @dev    Starts at passed in node and increments through range parent nodes, and ends at 8192.
     *  @param  i_  The index to start scaling from.
     *  @param  f_  The factor to scale the values by.
    */    
    // TODO: add check to ensure scaling factor is at least a WAD? 
    function _mult(uint256 i_, uint256 f_) internal {
        require(i_ >= 0 && i_ < SIZE, "FW:M:INVALID_INDEX");
        require(f_ != 0, "FW:M:FACTOR_ZERO");

        i_ += 1;
        uint256 sum;
        uint256 j;
        uint256 df = f_ - Maths.WAD;    // difference factor

        uint256 scaledI;
        uint256 scaledJ;

        while (i_ > 0) {
            scaledI =  scaling[i_];
            
            // Calc sum and scale value of current node i.
            sum = scaledI != 0 ? sum + Maths.wmul(Maths.wmul(df, values[i_]), scaledI) : sum + Maths.wmul(df, values[i_]);
            scaling[i_] = scaledI != 0 ? Maths.wmul(f_, scaledI) : f_;

            // Increase j and decrement current node i by one binary index.
            j = i_ + _lsb(i_);
            i_ -= _lsb(i_); 

            // Execute while i is a range parent of j (zero is the highest parent).
            while ((_lsb(j) < _lsb(i_)) || (i_ == 0 && j <= SIZE)) {

                // Write sums to range parent .
                values[j] += sum;
                scaledJ = scaling[j];
                if (scaledJ != 0) sum = Maths.wmul(sum, scaledJ);

                // Increase j to point to next range parent.
                j += _lsb(j);
            }
        }
    }

    /**
     *  @notice increase a value in the FenwickTree at an index.
     *  @dev    Starts at tree root and decrements through range parent nodes until index, i_, is reached.
     *  @param  i_  The index pointing to the value.
     *  @param  x_  amount to increase the value by.
    */    
    function _add(uint256 i_, uint256 x_) internal {
        require(i_ >= 0 && i_ < SIZE, "FW:A:INVALID_INDEX");

        i_ += 1; // why does this exist if we minus in l 95?
        uint256 j = 8192;           // 1 << 13
        uint256 ii;                 // binary index offset
        uint256 sc = Maths.WAD;

        uint256 scaled;

        while (j > 0) {
            // If passed in node is in current range, updates are confined to range for remaining iterations.
            if (((i_ - 1) & j) != 0) {

                // Increase binary index offset to point next node in range.
                ii += j;
            
            // Update node effected by addition.
            } else {
                scaled = scaling[ii + j];
                if (scaled != 0) sc = Maths.wmul(sc, scaled);
                values[ii + j] += Maths.wdiv(x_, sc);
            }
            j = j >> 1;
        }
    }

    /**
     *  @notice Decrease a node in the FenwickTree at an index.
     *  @dev    Starts at tree root and decrements through range parent nodes until index, i_, is reached.
     *  @param  i_  The index pointing to the value
     *  @param  x_  Amount to decrease the value by.
    */    
    function _remove(uint256 i_, uint256 x_) internal {
        require(i_ >= 0 && i_ < SIZE, "FW:R:INVALID_INDEX");

        i_ += 1; // why does this exist if we minus in l 130?
        uint256 j = 8192;          // 1 << 13
        uint256 ii;                // Binary index offset
        uint256 sc = Maths.WAD;

        uint256 scaled;

        while (j > 0) {
            // if requested node is in current range, updates are confined to range for remaining iterations.
            if (((i_ - 1) & j) != 0) {  

                // Increase binary index offset to point next node in range.
                ii += j;
                
            // Update node effected by removal.
            } else {
                scaled = scaling[ii + j];
                if (scaled != 0) sc = Maths.wmul(sc, scaled);
                values[ii + j] -= Maths.wdiv(x_, sc);
            }

            j = j >> 1;
        }
    }

    /**
     *  @notice Get prefix sum of all indexes less than provided index.
     *  @dev    Starts at tree root and decrements through range parent nodes summing from index i_'s range to index 0.
     *  @param  i_  The index to receive the prefix sum
    */    
    function _prefixSum(uint256 i_) internal view returns (uint256 s_) {
        i_ += 1;                   // Translate from 0 -> 1 indexed array
        uint256 sc = Maths.WAD;
        uint256 j  = 8192;         // 1 << 13
        uint256 ii;                // Binary index offset

        uint256 scaled;
        // Unsure of what this conditional does - ii + j <= SIZE?
        // This only ever restricts us when we are at the highest bucket? 8192. Possibly cleaner with a require statement?
        while (j > 0 && ii + j <= SIZE) { 

            scaled = scaling[ii + j];

            // If requested node is in current range, compute sum with running multiplier.
            if (i_ & j != 0) {
                if (scaled != 0) {
                   s_ += Maths.wmul(Maths.wmul(sc, scaled), values[ii + j]);
                } else {
                   s_ += Maths.wmul(sc, values[ii + j]);
                }
            
            // Increase running multiplier with range multiplier.
            } else {
                if (scaled != 0) sc = Maths.wmul(sc, scaled);
            }

            // Increase binary index offset to point next node in range.
            ii = ii + (i_ & j);
            j = j >> 1;
        }
    }




    /**
     *  @notice Returns the sum of a given range.
     *  @param  start_  start of range to sum.
     *  @param  stop_   end of range to sum.
    */
    function _rangeSum(uint256 start_, uint256 stop_) internal view returns (uint256) {
        require(start_ >= 0 && start_ < SIZE,      "FW:R:INVALID_START");
        require(stop_ >= start_ && stop_ <= SIZE,  "FW:R:INVALID_STOP");
        return _prefixSum(stop_) - _prefixSum(start_ - 1);
    }

    // TODO: rename this to findIndexOfSum
    // TODO: should this revert if failed to find a value past a given index instead of SIZE?
    function _findSum(uint256 x_) internal view returns (uint256 m_) {
        uint256 i = 4096; // 1 << (_numBits - 1) = 1 << (13 - 1) = 4096
        uint256 ss;
        uint256 sc = Maths.WAD;

        uint256 scaledM;
        uint256 scaledMInc;
        uint256 ssCond;

        while (i > 0) {
            scaledMInc = scaling[m_ + i];
            ssCond = scaledMInc != 0 ? ss + Maths.wmul(Maths.wmul(sc, scaledMInc), values[m_ + i]) : ss + Maths.wmul(sc, values[m_ + i]);
            if (ssCond < x_) {
                m_ += i;
                scaledM = scaling[m_];
                ss = scaledM != 0 ? ss + Maths.wmul(Maths.wmul(sc, scaledM), values[m_]) : ss + Maths.wmul(sc, values[m_]);
            } else {
                if (scaledMInc != 0) sc = Maths.wmul(sc, scaledMInc);
            }
            i = i >> 1;
        }
    }

    /**
     *  @notice Get least significant bit (LSB) of intiger, i_.
     *  @dev    Used primarily to decrement the binary index in loops, iterating over range parents.
     *  @param  i_  The integer with which to return the LSB.
    */    
    function _lsb(uint256 i_) internal pure returns (uint256) {
        if (i_ == 0) return 0;
        // "i & (-i)"
        return
            i_ &
            ((i_ ^
                0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff) +
                1);
    }

    function _treeSum() internal view returns (uint256) {
        return values[SIZE];
    }
}
