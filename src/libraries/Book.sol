// SPDX-License-Identifier: MIT
pragma solidity 0.8.14;

import './Maths.sol';
import './BucketMath.sol';

library Book {

    /***************/
    /*** Buckets ***/
    /***************/

    /**
     *  @notice struct holding bucket info
     *  @param lps        Bucket LP accumulator, RAY
     *  @param collateral Available collateral tokens deposited in the bucket, WAD
     */
    struct Bucket {
        uint256 lps;
        uint256 collateral;
    }

    function addLPs(
        mapping(uint256 => Bucket) storage self,
        uint256 index_,
        uint256 amount_
    ) internal {
        self[index_].lps += amount_;
    }

    function removeLPs(
        mapping(uint256 => Bucket) storage self,
        uint256 index_,
        uint256 amount_
    ) internal {
        self[index_].lps -= amount_;
    }

    function addCollateral(
        mapping(uint256 => Bucket) storage self,
        uint256 index_,
        uint256 lps_,
        uint256 collateral_
    ) internal {
        self[index_].lps += lps_;
        self[index_].collateral += collateral_;
    }

    function removeCollateral(
        mapping(uint256 => Bucket) storage self,
        uint256 index_,
        uint256 lps_,
        uint256 collateral_
    ) internal {
        Bucket storage bucket = self[index_];
        bucket.lps        -= Maths.min(bucket.lps, lps_);
        bucket.collateral -= Maths.min(bucket.collateral, collateral_);
    }

    function getExchangeRate(
        mapping(uint256 => Bucket) storage self,
        uint256 index_,
        uint256 quoteToken_
    ) internal view returns (uint256) {
        Bucket memory bucket = self[index_];
        if (bucket.lps == 0) return  Maths.RAY;
        uint256 bucketSize = quoteToken_ * 10**18 + indexToPrice(index_) * bucket.collateral;  // 10^36 + // 10^36
        return bucketSize * 10**18 / bucket.lps; // 10^27
    }

    function collateralToLPs(
        mapping(uint256 => Bucket) storage self,
        uint256 index_,
        uint256 deposit_,
        uint256 collateral_
    ) internal view returns (uint256) {
        uint256 rate  = getExchangeRate(self, index_, deposit_);
        return (collateral_ * indexToPrice(index_) * 1e18 + rate / 2) / rate;
    }

    function quoteTokensToLPs(
        mapping(uint256 => Bucket) storage self,
        uint256 index_,
        uint256 deposit_,
        uint256 quoteTokens_
    ) internal view returns (uint256) {
        uint256 rate  = getExchangeRate(self, index_, deposit_);
        return Maths.rdiv(Maths.wadToRay(quoteTokens_), rate);
    }

    function lpsToQuoteToken(
        mapping(uint256 => Bucket) storage self,
        uint256 index_,
        uint256 deposit_,
        uint256 lenderLPsBalance_,
        uint256 maxQuoteToken_
    ) internal view returns (uint256 quoteTokenAmount_, uint256 bucketLPs_, uint256 lenderLPs_) {
        lenderLPs_ = lenderLPsBalance_;
        uint256 rate  = getExchangeRate(self, index_, deposit_);
        quoteTokenAmount_ = Maths.rayToWad(Maths.rmul(lenderLPsBalance_, rate));
        if (quoteTokenAmount_ > deposit_) {
            quoteTokenAmount_ = deposit_;
            lenderLPs_        = Maths.wrdivr(quoteTokenAmount_, rate);
        }
        if (maxQuoteToken_ != quoteTokenAmount_) quoteTokenAmount_ = Maths.min(maxQuoteToken_,quoteTokenAmount_);
        bucketLPs_ = Maths.wrdivr(quoteTokenAmount_, rate);
    }

    function lpsToCollateral(
        mapping(uint256 => Bucket) storage self,
        uint256 index_,
        uint256 deposit_,
        uint256 lenderLPsBalance_,
        uint256 maxCollateral_
    ) internal view returns (uint256 collateralAmount_, uint256 lenderLPs_) {
        // max collateral to lps
        lenderLPs_        = lenderLPsBalance_;
        uint256 price      = Book.indexToPrice(index_);
        uint256 rate       = getExchangeRate(self, index_, deposit_);
        collateralAmount_ = Maths.rwdivw(Maths.rmul(lenderLPsBalance_, rate), price);
        if (collateralAmount_ > maxCollateral_) {
            // user is owed more collateral than is available in the bucket
            collateralAmount_ = maxCollateral_;
            lenderLPs_        = Maths.wrdivr(Maths.wmul(collateralAmount_, price), rate);
        }
    }

    function getCollateral(
        mapping(uint256 => Bucket) storage self,
        uint256 index_
    ) internal view returns (uint256) {
        return self[index_].collateral;
    }

    function indexToPrice(uint256 index_) internal pure returns (uint256) {
        return BucketMath.indexToPrice(indexToBucketIndex(index_));
    }

    /**
     *  @dev Fenwick index to bucket index conversion
     *          1.00      : bucket index 0,     fenwick index 4146: 7388-4156-3232=0
     *          MAX_PRICE : bucket index 4156,  fenwick index 0:    7388-0-3232=4156.
     *          MIN_PRICE : bucket index -3232, fenwick index 7388: 7388-7388-3232=-3232.
     */
    function indexToBucketIndex(uint256 index_) internal pure returns (int256 bucketIndex_) {
        bucketIndex_ = (index_ != 8191) ? 4156 - int256(index_) : BucketMath.MIN_PRICE_INDEX;
    }

    /***************/
    /*** Deposits ***/
    /***************/

    error InvalidIndex();
    error InvalidScalingFactor();

    struct Deposits {
        uint256[8193] values;  // Array of values in the FenwickTree.
        uint256[8193] scaling; // Array of values in the nested scaling FenwickTree.
    }

    /**
     *  @notice increase a value in the FenwickTree at an index.
     *  @dev    Starts at tree root and decrements through range parent nodes until index, i_, is reached.
     *  @param  i_  The index pointing to the value.
     *  @param  x_  amount to increase the value by.
    */    
    function add(
        Deposits storage self,
        uint256 i_,
        uint256 x_
    ) internal {
        if (i_ >= 8192) revert InvalidIndex();

        uint256 j     = 8192;       // Binary index, 1 << 13
        uint256 ii    = 0;          // Binary index offset
        uint256 sc    = Maths.WAD;
        uint256 index = 8192;

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
        Deposits storage self,
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
        Deposits storage self,
        uint256 i_,
        uint256 f_
    ) internal {
        if (i_ >= 8192) revert InvalidIndex();
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
            while ((lsbJ < lsb(i_)) || (i_ == 0 && j <= 8192)) {

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
        Deposits storage self,
        uint256 i_
    ) internal view returns (uint256 s_) {

        i_            += 1;              // Translate from 0 -> 1 indexed array
        uint256 sc    =  Maths.WAD;
        uint256 j     =  8192;           // Binary index, 1 << 13
        uint256 ii    =  0;              // Binary index offset
        uint256 index =  8192;

        uint256 scaled;
        
        while (j > 0 && index <= 8192) {

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
        Deposits storage self,
        uint256 i_,
        uint256 x_
    ) internal {
        if (i_ >= 8192) revert InvalidIndex();

        uint256 j     = 8192;       // Binary index, 1 << 13
        uint256 ii    = 0;          // Binary index offset
        uint256 sc    = Maths.WAD;
        uint256 index = 8192;

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
                self.values[index] -= Maths.wdiv(x_, sc);
            }

            j = j >> 1;
            index = ii + j;
        }
    }

    function scale(
        Deposits storage self,
        uint256 i_
    ) internal view returns (uint256 a_) {
        if (i_ >= 8192) revert InvalidIndex();

        a_ = Maths.WAD;
        uint256 scaled;
        while (i_ <= 8192) {
            scaled = self.scaling[i_];
            if (scaled != 0) a_ = Maths.wmul(a_, scaled);
            i_ += lsb(i_);
        }
    }

    function treeSum(
        Deposits storage self
    ) internal view returns (uint256) {
        return self.values[8192];
    }

    function valueAt(
        Deposits storage self,
        uint256 i_
    ) internal view returns (uint256 s_) {
        if (i_ >= 8192) revert InvalidIndex();

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
        while (i_ <= 8192) {
            scaled = self.scaling[i_];
            if (scaled != 0) s_ = Maths.wmul(scaled, s_);
            i_ += lsb(i_);
        }
    }
}