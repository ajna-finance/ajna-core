// SPDX-License-Identifier: MIT
pragma solidity 0.8.14;

import './Maths.sol';
import './PoolUtils.sol';

library Deposits {

    uint256 internal constant SIZE = 8192;

    error InvalidIndex();
    error InvalidScalingFactor();

    struct Data {
        uint256[8193] values;  // Array of values in the FenwickTree.
        uint256[8193] scaling; // Array of values which scale (multiply) the FenwickTree accross indexes.
    }

    function isDepositIndex(
        uint256 index_
    ) public pure returns (bool) {
        return index_ <= SIZE;
    }

    function accrueInterest(
        Data storage self,
        uint256 debt_,
        uint256 collateral_,
        uint256 htp_,
        uint256 pendingInterestFactor_
    ) internal {
        uint256 htpIndex = (htp_ != 0) ? PoolUtils.priceToIndex(htp_) : 4_156; // if HTP is 0 then accrue interest at max index (min price)
        uint256 depositAboveHtp = prefixSum(self, htpIndex);

        if (depositAboveHtp != 0) {
            uint256 netInterestMargin = PoolUtils.lenderInterestMargin(utilization(self, debt_, collateral_));
            uint256 newInterest       = Maths.wmul(netInterestMargin, Maths.wmul(pendingInterestFactor_ - Maths.WAD, debt_));

            uint256 lenderFactor = Maths.wdiv(newInterest, depositAboveHtp) + Maths.WAD;
            mult(self, htpIndex, lenderFactor);
        }
    }

    function utilization(
        Data storage self,
        uint256 debt_,
        uint256 collateral_
    ) internal view returns (uint256 utilization_) {
        if (collateral_ != 0) {
            uint256 ptp = Maths.wdiv(debt_, collateral_);

            if (ptp != 0) {
                uint256 depositAbove = prefixSum(self, PoolUtils.priceToIndex(ptp));

                if (depositAbove != 0) utilization_ = Maths.wdiv(
                    debt_,
                    depositAbove
                );
            }
        }
    }

    function momp(
        Data storage self,
        uint256 curDebt_,
        uint256 numLoans_
    ) internal view returns (uint256 momp_) {
        if (numLoans_ != 0) momp_ = PoolUtils.indexToPrice(findIndexOfSum(self, Maths.wdiv(curDebt_, numLoans_ * 1e18)));
    }

    function mompFactor(
        Data storage self,
        uint256 inflator_,
        uint256 curDebt_,
        uint256 numLoans_
    ) internal view returns (uint256 factor_) {
        uint256 curMomp = momp(self, curDebt_, numLoans_);
        if (curMomp != 0) factor_ = Maths.wdiv(curMomp, inflator_);
    }

    /**
     *  @notice increase a value in the FenwickTree at an index.
     *  @dev    Starts at tree root and decrements through range parent nodes until index, i_, is reached.
     *  @param  i_  The index pointing to the value.
     *  @param  x_  amount to increase the value by.
    */    
    function add(
        Data storage self,
        uint256 i_,
        uint256 x_
    ) internal {
        if (i_ >= SIZE) revert InvalidIndex();

        uint256 j     = SIZE;       // Binary index, 1 << 13
        uint256 ii    = 0;          // Binary index offset
        uint256 sc    = Maths.WAD;
        uint256 index = SIZE;

        uint256 scaled;

        while (j > 0) {

            // If passed in node is in current range, updates are confined to range for remaining iterations.
            if ((i_ & j) != 0) {

                // Increase binary index offset to point next node in range.
                ii += j;
            
            // Update node effected by addition.
            } else {
                scaled = self.scaling[index];
                if (scaled != 0) sc = Maths.wmul(sc, scaled);
                self.values[index] += Maths.wdiv(x_, sc);
            }
            j = j >> 1;
            index = ii + j;
        }
    }

    // TODO: should this revert if failed to find a value past a given index instead of SIZE?
    /**
     *  @notice Finds index of passed sum
     *  @dev    Used in lup calculation
     *  @param  x_  The sum passed
     *  @return  m_  returns smallest index where prefixsum > x_
    */    
    function findIndexOfSum(
        Data storage self,
        uint256 x_
    ) internal view returns (uint256 m_) {
        uint256 i     = 4096; // 1 << (_numBits - 1) = 1 << (13 - 1) = 4096
        uint256 ss    = 0;
        uint256 sc    = Maths.WAD;
        uint256 index = 4096;

        uint256 scaledM;
        uint256 scaledMInc;
        uint256 ssCond;

        while (i > 0) {
            scaledMInc = self.scaling[index];
            ssCond = scaledMInc != 0 ? ss + Maths.wmul(Maths.wmul(sc, scaledMInc), self.values[index]) : ss + Maths.wmul(sc, self.values[index]);
            if (ssCond < x_) {
                m_ += i;
                scaledM = self.scaling[m_];
                ss = scaledM != 0 ? ss + Maths.wmul(Maths.wmul(sc, scaledM), self.values[m_]) : ss + Maths.wmul(sc, self.values[m_]);
            } else {
                if (scaledMInc != 0) sc = Maths.wmul(sc, scaledMInc);
            }
            i = i >> 1;
            index = m_ + i;
        }
    }

     /**
     *  @notice Get least significant bit (LSB) of intiger, i_.
     *  @dev    Used primarily to decrement the binary index in loops, iterating over range parents.
     *  @param  i_  The integer with which to return the LSB.
    */    
    function lsb(
        uint256 i_
    ) internal pure returns (uint256 lsb_) {
        if (i_ != 0) {
            // "i & (-i)"
            lsb_ = i_ & ((i_ ^ 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff) + 1);
        }
    }

    /**
     *  @notice Scale values in the tree from the index provided, upwards.
     *  @dev    Starts at passed in node and increments through range parent nodes, and ends at 8192.
     *  @param  i_  The index to start scaling from.
     *  @param  f_  The factor to scale the values by.
    */    
    // TODO: add check to ensure scaling factor is at least a WAD? 
    function mult(
        Data storage self,
        uint256 i_,
        uint256 f_
    ) internal {
        if (i_ >= SIZE) revert InvalidIndex();
        if (f_ == 0) revert InvalidScalingFactor();

        i_          += 1;
        uint256 sum = 0;
        uint256 j;                         // Tracks range parents of starting node, i_
        uint256 df  = f_ - Maths.WAD;    // Difference factor

        uint256 scaledI;
        uint256 scaledJ;

        while (i_ > 0) {
            scaledI =  self.scaling[i_];
            
            // Calc sum, will only be stored in range parents of starting node, i_
            sum = scaledI != 0 ? sum + Maths.wmul(Maths.wmul(df, self.values[i_]), scaledI) : sum + Maths.wmul(df, self.values[i_]);

            // Apply scaling to all range parents less then starting node, i_
            self.scaling[i_] = scaledI != 0 ? Maths.wmul(f_, scaledI) : f_;

            // Increase j and decrement current node i by one binary index.
            uint256 lsbI = lsb(i_);
            j = i_ + lsbI;
            i_ -= lsbI;
            uint256 lsbJ = lsb(j);

            // Execute while i is a range parent of j (zero is the highest parent).
            //slither-disable-next-line incorrect-equality
            while ((lsbJ < lsb(i_)) || (i_ == 0 && j <= SIZE)) {

                // Sum > 0 only when j is a range parent of starting node, i_.
                self.values[j] += sum;
                scaledJ = self.scaling[j];
                if (scaledJ != 0) sum = Maths.wmul(sum, scaledJ);
                j += lsbJ;
                lsbJ = lsb(j);
            }
        }
    }

    /**
     *  @notice Get prefix sum of all indexes less than provided index.
     *  @dev    Starts at tree root and decrements through range parent nodes summing from index i_'s range to index 0.
     *  @param  i_  The index to receive the prefix sum
    */    
    function prefixSum(
        Data storage self,
        uint256 i_
    ) internal view returns (uint256 s_) {

        i_            += 1;              // Translate from 0 -> 1 indexed array
        uint256 sc    =  Maths.WAD;
        uint256 j     =  SIZE;           // Binary index, 1 << 13
        uint256 ii    =  0;              // Binary index offset
        uint256 index =  SIZE;

        uint256 scaled;
        
        while (j > 0 && index <= SIZE) {

            scaled = self.scaling[index];

            // If requested node is in current range, compute sum with running multiplier.
            if (i_ & j != 0) {
                if (scaled != 0) {
                    s_ += Maths.wmul(Maths.wmul(sc, scaled), self.values[index]);
                } else {
                   s_ += Maths.wmul(sc, self.values[index]);
                }
            } else {
                if (scaled != 0) sc = Maths.wmul(sc, scaled);
            }

            // Increase binary index offset to point next node in range.
            ii = ii + (i_ & j);
            j = j >> 1;
            index = ii + j;
        }
    }

    /**
     *  @notice Decrease a node in the FenwickTree at an index.
     *  @dev    Starts at tree root and decrements through range parent nodes until index, i_, is reached.
     *  @param  i_  The index pointing to the value
     *  @param  x_  Amount to decrease the value by.
    */    
    function remove(
        Data storage self,
        uint256 i_,
        uint256 x_
    ) internal {
        if (i_ >= SIZE) revert InvalidIndex();

        uint256 j     = SIZE;       // Binary index, 1 << 13
        uint256 ii    = 0;          // Binary index offset
        uint256 sc    = Maths.WAD;
        uint256 index = SIZE;

        uint256 scaled;

        while (j > 0) {
            // if requested node is in current range, updates are confined to range for remaining iterations.
            if ((i_ & j) != 0) {  

                // Increase binary index offset to point next node in range.
                ii += j;
                
            // Update node effected by removal.
            } else {
                scaled = self.scaling[index];
                if (scaled != 0) sc = Maths.wmul(sc, scaled);
                self.values[index] -= Maths.min(self.values[index], Maths.wdiv(x_, sc));
            }

            j = j >> 1;
            index = ii + j;
        }
    }

    function scale(
        Data storage self,
        uint256 i_
    ) internal view returns (uint256 a_) {
        if (i_ >= SIZE) revert InvalidIndex();

        a_ = Maths.WAD;
        uint256 scaled;
        while (i_ <= SIZE) {
            scaled = self.scaling[i_];
            if (scaled != 0) a_ = Maths.wmul(a_, scaled);
            i_ += lsb(i_);
        }
    }

    function treeSum(
        Data storage self
    ) internal view returns (uint256) {
        return self.values[SIZE];
    }

    function valueAt(
        Data storage self,
        uint256 i_
    ) internal view returns (uint256 s_) {
        if (i_ >= SIZE) revert InvalidIndex();

        uint256 j  =  i_;
        uint256 k  =  1;

        i_         += 1;
        s_         =  self.values[i_];

        uint256 scaled;
        while (j & k != 0) {
            scaled = self.scaling[j];
            s_ = scaled != 0 ? s_ - Maths.wmul(scaled, self.values[j]) : s_ - self.values[j];
            j  = j - k;
            k  = k << 1;
        }
        while (i_ <= SIZE) {
            scaled = self.scaling[i_];
            if (scaled != 0) s_ = Maths.wmul(scaled, s_);
            i_ += lsb(i_);
        }
    }
}