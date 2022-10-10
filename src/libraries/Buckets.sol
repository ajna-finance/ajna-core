// SPDX-License-Identifier: MIT
pragma solidity 0.8.14;

import './Maths.sol';
import './PoolUtils.sol';

library Buckets {

    struct Lender {
        uint256 lps; // [RAY] Lender LP accumulator
        uint256 ts;  // timestamp of last deposit
    }

    struct Bucket {
        uint256 lps;                        // [RAY] Bucket LP accumulator
        uint256 collateral;                 // [WAD] Available collateral tokens deposited in the bucket
        mapping(address => Lender) lenders; // lender address to Lender struct mapping
    }

    /***********************************/
    /*** Bucket Management Functions ***/
    /***********************************/

    function addQuoteToken(
        mapping(uint256 => Bucket) storage self,
        uint256 deposit_,
        uint256 quoteTokenAmountToAdd_,
        uint256 index_
    ) internal returns (uint256 bucketLPs_) {
        bucketLPs_ = quoteTokensToLPs(
            self,
            deposit_,
            quoteTokenAmountToAdd_,
            index_
        );

        Bucket storage bucket = self[index_];
        bucket.lps += bucketLPs_;

        Lender storage lender = bucket.lenders[msg.sender];
        lender.lps += bucketLPs_;
        lender.ts  = block.timestamp;
    }

    function addCollateral(
        mapping(uint256 => Bucket) storage self,
        uint256 deposit_,
        uint256 collateral_,
        uint256 index_
    ) internal returns (uint256 bucketLPs_) {
        (bucketLPs_, ) = collateralToLPs(
            self,
            deposit_,
            collateral_,
            index_
        );
        Bucket storage bucket = self[index_];
        bucket.lps += bucketLPs_;
        bucket.collateral += collateral_;

        bucket.lenders[msg.sender].lps += bucketLPs_;
    }

    function moveLPs(
        mapping(uint256 => Bucket) storage self,
        uint256 fromAmount_,
        uint256 toAmount_,
        uint256 from_,
        uint256 to_
    ) internal {
        Bucket storage fromBucket = self[from_];
        Bucket storage toBucket   = self[to_];
        fromBucket.lps -= fromAmount_;
        toBucket.lps   += toAmount_;

        fromBucket.lenders[msg.sender].lps -= fromAmount_;
        toBucket.lenders[msg.sender].lps   += toAmount_;
    }

    function removeCollateral(
        mapping(uint256 => Bucket) storage self,
        uint256 collateral_,
        uint256 lps_,
        uint256 index_
    ) internal {
        Bucket storage bucket = self[index_];
        bucket.lps        -= Maths.min(bucket.lps, lps_);
        bucket.collateral -= Maths.min(bucket.collateral, collateral_);

        bucket.lenders[msg.sender].lps -= lps_;
    }

    function removeLPs(
        mapping(uint256 => Bucket) storage self,
        uint256 amount_,
        uint256 index_
    ) internal {
        self[index_].lps -= amount_;

        self[index_].lenders[msg.sender].lps -= amount_;
    }

    function transferLPs(
        mapping(uint256 => Bucket) storage self,
        address owner_,
        address newOwner_,
        uint256 amount_,
        uint256 index_,
        uint256 depositTime
    ) internal {
        // move lp tokens to the new owner address
        Lender storage newOwner = self[index_].lenders[newOwner_];
        newOwner.lps += amount_;
        newOwner.ts  = Maths.max(depositTime, newOwner.ts);

        // reset owner lp balance for this index
        delete self[index_].lenders[owner_];
    }


    /**********************/
    /*** View Functions ***/
    /**********************/

    function collateralToLPs(
        mapping(uint256 => Bucket) storage self,
        uint256 deposit_,
        uint256 collateral_,
        uint256 index_
    ) internal view returns (uint256, uint256) {
        (uint256 rate, uint256 bucketCollateral)  = getExchangeRate(self, deposit_, index_);
        uint256 lps = (collateral_ * PoolUtils.indexToPrice(index_) * 1e18 + rate / 2) / rate;
        return (lps, bucketCollateral);
    }

    function getExchangeRate(
        mapping(uint256 => Bucket) storage self,
        uint256 quoteToken_,
        uint256 index_
    ) internal view returns (uint256, uint256) {
        uint256 bucketCollateral = self[index_].collateral;
        uint256 bucketLPs        = self[index_].lps;
        if (bucketLPs == 0) {
            return  (Maths.RAY, bucketCollateral);
        }
        uint256 bucketSize = quoteToken_ * 10**18 + PoolUtils.indexToPrice(index_) * bucketCollateral;  // 10^36 + // 10^36
        return (bucketSize * 10**18 / bucketLPs, bucketCollateral); // 10^27
    }

    function getLenderInfo(
        mapping(uint256 => Bucket) storage self,
        uint256 index_,
        address lender_
    ) internal view returns (uint256, uint256) {
        return (self[index_].lenders[lender_].lps, self[index_].lenders[lender_].ts);
    }

    function lpsToCollateral(
        mapping(uint256 => Bucket) storage self,
        uint256 deposit_,
        uint256 lenderLPsBalance_,
        uint256 index_
    ) internal view returns (uint256 collateralAmount_, uint256 lenderLPs_) {
        // max collateral to lps
        lenderLPs_        = lenderLPsBalance_;
        uint256 price      = PoolUtils.indexToPrice(index_);
        (uint256 rate, uint256 bucketCollateral) = getExchangeRate(self, deposit_, index_);
        collateralAmount_ = Maths.rwdivw(Maths.rmul(lenderLPsBalance_, rate), price);
        if (collateralAmount_ > bucketCollateral) {
            // user is owed more collateral than is available in the bucket
            collateralAmount_ = bucketCollateral;
            lenderLPs_        = Maths.wrdivr(Maths.wmul(collateralAmount_, price), rate);
        }
    }

    function lpsToQuoteToken(
        mapping(uint256 => Bucket) storage self,
        uint256 deposit_,
        uint256 lenderLPsBalance_,
        uint256 maxQuoteToken_,
        uint256 index_
    ) internal view returns (uint256 quoteTokenAmount_, uint256 bucketLPs_, uint256 lenderLPs_) {
        lenderLPs_ = lenderLPsBalance_;
        (uint256 rate, )  = getExchangeRate(self, deposit_, index_);
        quoteTokenAmount_ = Maths.rayToWad(Maths.rmul(lenderLPsBalance_, rate));
        if (quoteTokenAmount_ > deposit_) {
            quoteTokenAmount_ = deposit_;
            lenderLPs_        = Maths.wrdivr(quoteTokenAmount_, rate);
        }
        if (maxQuoteToken_ != quoteTokenAmount_) quoteTokenAmount_ = Maths.min(maxQuoteToken_,quoteTokenAmount_);
        bucketLPs_ = Maths.wrdivr(quoteTokenAmount_, rate);
    }

    function quoteTokensToLPs(
        mapping(uint256 => Bucket) storage self,
        uint256 deposit_,
        uint256 quoteTokens_,
        uint256 index_
    ) internal view returns (uint256) {
        (uint256 rate, )  = getExchangeRate(self, deposit_, index_);
        return Maths.rdiv(Maths.wadToRay(quoteTokens_), rate);
    }
}