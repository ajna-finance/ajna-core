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
}