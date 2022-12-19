// SPDX-License-Identifier: MIT
pragma solidity 0.8.14;

import { DepositsState } from '../base/interfaces/IPool.sol';

import '../base/PoolHelper.sol';

library Deposits {

    uint256 internal constant SIZE = 8192;

    /**
     *  @notice increase a value in the FenwickTree at an index.
     *  @dev    Starts at leaf/target and moved up towards root
     *  @param  index_     The deposit index.
     *  @param  addAmount_ The amount to increase deposit by.
     */    
    function add(
        DepositsState storage deposits_,
        uint256 index_,
        uint256 addAmount_
    ) internal {
        ++index_;
        addAmount_ = Maths.wdiv(addAmount_, scale(deposits_, index_));

        while (index_ <= SIZE) {
            uint256 value    = deposits_.values[index_];
            uint256 scaling  = deposits_.scaling[index_];
            uint256 newValue = value + addAmount_;
            // Note: we can't just multiply addAmount_ by scaling[i_] due to rounding
            // We need to track the precice change in deposits_.values[i_] in order to ensure
            // obliterated indices remain zero after subsequent adding to related indices
            if (scaling != 0) addAmount_ = Maths.wmul(newValue, scaling) - Maths.wmul(value, scaling);
            deposits_.values[index_] = newValue;
            index_ += lsb(index_);
        }
    }

    /**
     *  @notice Finds index of passed sum
     *  @dev    Used in lup calculation
     *  @param  sum_      The sum to find index for.
     *  @return sumIndex_ Smallest index where prefixsum greater than the sum
     */    
    function findIndexOfSum(
        DepositsState storage deposits_,
        uint256 sum_
    ) internal view returns (uint256 sumIndex_) {
        // Avoid looking for a sum greater than the tree size
        if (treeSum(deposits_) < sum_) return MAX_FENWICK_INDEX;

        uint256 i     = 4096; // 1 << (_numBits - 1) = 1 << (13 - 1) = 4096
        uint256 ss    = 0;
        uint256 sc    = Maths.WAD;
        uint256 index = sumIndex_ + i;

        while (i > 0) {
            uint256 value       = deposits_.values[index];
            uint256 scaling     = deposits_.scaling[index];
            uint256 scaledValue = scaling != 0 ? ss + Maths.wmul(Maths.wmul(sc, scaling), value) : ss + Maths.wmul(sc, value);
            if (scaledValue  < sum_) {
                sumIndex_ += i;
                ss = scaledValue;
            } else {
                if (scaling != 0) sc = Maths.wmul(sc, scaling);
            }
            i = i >> 1;
            index = sumIndex_ + i;
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
     *  @param  index_  The index to start scaling from.
     *  @param  factor_  The factor to scale the values by.
     */    
    // TODO: add check to ensure scaling factor is at least a WAD? 
    function mult(
        DepositsState storage deposits_,
        uint256 index_,
        uint256 factor_
    ) internal {
        ++index_;

        uint256 sum;
        uint256 value;
        uint256 scaling;
        uint256 bit = lsb(index_);

        // Starting with the lSB of index, we iteratively move up towards the MSB of SIZE
        // Case 1:     the bit of index_ is set to 1.  In this case, the entire subtree below index_
        //             is scaled.  So, we include factor_ into scaleing[index_], and remember in sum how much
        //             we increased the subtree by, so that we can use it in case we encounter 0 bits (below).
        // Case 2:     The bit of index_ is set to 0.  In this case, consider the subtree below the node 
        //             index_+bit. The subtree below that is not entirely scaled, but it does contain the
        //             subtree what was scaled earlier.  Therefore: we need to increment it's stored value
        //             (in sum) which was set in a prior interation in case 1.
        while (bit <= SIZE) {
            if((bit & index_) != 0) {
                value   = deposits_.values[index_];
                scaling = deposits_.scaling[index_];
            
                // Calc sum, will only be stored in range parents of starting node, index_
                if (scaling != 0) {
                    // Note: we can't just multiply by factor_ - 1 in the following line, as rounding will
                    // cause obliterated indices to have nonzero values.  Need to track the actual
                    // precise delta in the value array
                    uint256 scaledFactor = Maths.wmul(factor_, scaling);
                    sum += Maths.wmul(scaledFactor, value) - Maths.wmul(scaling, value);
                    // Apply scaling to all range parents less then starting node, index_
                    deposits_.scaling[index_] = scaledFactor;
                } else {
                    sum += Maths.wmul(factor_, value) - value;
                    deposits_.scaling[index_] = factor_;
                }

                index_ -= bit;
            } else {
                uint256 superRangeIndex = index_ + bit;
                value = (deposits_.values[superRangeIndex] += sum);
                scaling = deposits_.scaling[superRangeIndex];
                // again, in following line, need to be careful due to rounding
                if (scaling != 0) sum = Maths.wmul(value, scaling) - Maths.wmul(value - sum, scaling);
            } 
            bit = bit << 1;
        }
    }

    /**
     *  @notice Get prefix sum of all indexes from provided index downwards.
     *  @dev    Starts at tree root and decrements through range parent nodes summing from index i_'s range to index 0.
     *  @param  sumIndex_  The index to receive the prefix sum.
     *  @param  sum_       The prefix sum from current index downwards.
     */    
    function prefixSum(
        DepositsState storage deposits_,
        uint256 sumIndex_
    ) internal view returns (uint256 sum_) {
        ++sumIndex_; // Translate from 0 -> 1 indexed array

        uint256 sc    = Maths.WAD;
        uint256 j     = SIZE;      // Binary index, 1 << 13
        uint256 ii    = 0;         // Binary index offset
        uint256 index = SIZE;
        
        while (j > 0 && index <= SIZE) {

            uint256 scaled = deposits_.scaling[index];
            uint256 value  = deposits_.values[index];

            // If requested node is in current range, compute sum with running multiplier.
            if (sumIndex_ & j != 0) {
                sum_ += scaled != 0 ? Maths.wmul(Maths.wmul(sc, scaled), value) : Maths.wmul(sc, value);
            } else {
                if (scaled != 0) sc = Maths.wmul(sc, scaled);
            }

            // Increase binary index offset to point next node in range.
            ii = ii + (sumIndex_ & j);
            j = j >> 1;
            index = ii + j;
        }
    }

    function remove(
        DepositsState storage deposits_,
        uint256 index_,
        uint256 removeAmount_,
	uint256 currentAmount_
    ) internal {
	if (removeAmount_ == currentAmount_) {
	    unscaledRemove(deposits_, index_, unscaledValueAt(deposits_,index_));
	} else {
	    unscaledRemove(deposits_, index_, Maths.wdiv(removeAmount_, scale(deposits_, index_)));
	}
    }

    
    /**
     *  @notice Decrease a node in the FenwickTree at an index.
     *  @dev    Starts at leaf/target and moved up towards root
     *  @param  index_             The deposit index.
     *  @param  unscaledRemoveAmount_   Unscaled amount to decrease deposit by.
     */    
    function unscaledRemove(
        DepositsState storage deposits_,
        uint256 index_,
        uint256 unscaledRemoveAmount_
    ) internal {
        ++index_;

        while (index_ <= SIZE) {
            uint256 value    = (deposits_.values[index_] -= unscaledRemoveAmount_);
            uint256 scaling  = deposits_.scaling[index_];
            // On the line below, it would be tempting to replace this with:
            // unscaledRemoveAmount_ = Maths.wmul(unscaledRemoveAmount, scaling).  This will introduce nonzero values up
            // the tree due to rounding.  It's important to compute the actual change in deposits_.values[index_]
            // and propogate that upwards.
            if (scaling != 0) unscaledRemoveAmount_ = Maths.wmul(value + unscaledRemoveAmount_, scaling) - Maths.wmul(value,  scaling);
            index_ += lsb(index_);
        }
    }

    /**
     *  @notice Scale tree starting from given index.
     *  @dev    Starts at leaf/target and moved up towards root
     *  @param  index_  The deposit index.
     *  @return scaled_ Scaled value.
     */   
    function scale(
        DepositsState storage deposits_,
        uint256 index_
    ) internal view returns (uint256 scaled_) {
	    ++index_;
        
        scaled_ = Maths.WAD;
        while (index_ <= SIZE) {
            uint256 scaling = deposits_.scaling[index_];
            if (scaling != 0) scaled_ = Maths.wmul(scaled_, scaling);
            index_ += lsb(index_);
        }
    }

    /**
     *  @notice Returns sum of all deposits.
     */ 
    function treeSum(
        DepositsState storage deposits_
    ) internal view returns (uint256) {
        uint256 scaling = deposits_.scaling[SIZE];
        if (scaling==0) scaling = Maths.WAD;
        return Maths.wmul(scaling,deposits_.values[SIZE]);
    }

    /**
     *  @notice Returns deposit value for a given deposit index.
     *  @param  index_        The deposit index.
     *  @return depositValue_ Value of the deposit.
     */  
    function valueAt(
        DepositsState storage deposits_,
        uint256 index_
    ) internal view returns (uint256 depositValue_) {
        depositValue_ = Maths.wmul(unscaledValueAt(deposits_, index_), scale(deposits_,index_));
    }

    function unscaledValueAt(
        DepositsState storage deposits_,
        uint256 index_
    ) internal view returns (uint256 unscaledDepositValue_) {
        ++index_;

        uint256 j = 1;

        unscaledDepositValue_ = deposits_.values[index_];
        while (j & index_ == 0) {
            uint256 value   = deposits_.values[index_ - j];
            uint256 scaling = deposits_.scaling[index_ - j];
            unscaledDepositValue_ -= scaling != 0 ? Maths.wmul(scaling, value) : value;
            j = j << 1;
        }
    }
}
