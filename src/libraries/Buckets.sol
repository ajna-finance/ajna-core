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

    /**
     *  @notice Updates LP balances for bucket and lender with the amount coresponding to quote token amount added.
     *  @param  deposit_               Current bucket deposit (quote tokens). Used to calculate bucket's exchange rate / LPs
     *  @param  quoteTokenAmountToAdd_ Additional quote tokens amount to add to bucket deposit.
     *  @param  index_                 Index of the bucket to add quote tokens to.
     *  @return addedLPs_              Amount of bucket LPs for the quote tokens amount added.
     */
    function addQuoteToken(
        mapping(uint256 => Bucket) storage self,
        uint256 deposit_,
        uint256 quoteTokenAmountToAdd_,
        uint256 index_
    ) internal returns (uint256 addedLPs_) {
        // calculate amount of LPs to be added for the amount of quote tokens added to bucket
        addedLPs_ = quoteTokensToLPs(
            self,
            deposit_,
            quoteTokenAmountToAdd_,
            index_
        );

        // update bucket LPs balance
        Bucket storage bucket = self[index_];
        bucket.lps += addedLPs_;
        // update lender LPs balance and deposit timestamp
        Lender storage lender = bucket.lenders[msg.sender];
        lender.lps += addedLPs_;
        lender.ts  = block.timestamp;
    }

    /**
     *  @notice Add collateral to a bucket and updates LPs for bucket and lender with the amount coresponding to collateral amount added.
     *  @param  deposit_               Current bucket deposit (quote tokens). Used to calculate bucket's exchange rate / LPs
     *  @param  collateralAmountToAdd_ Additional collateral amount to add to bucket.
     *  @param  index_                 Index of the bucket to add collateral to.
     *  @return addedLPs_              Amount of bucket LPs for the collateral amount added.
     */
    function addCollateral(
        mapping(uint256 => Bucket) storage self,
        uint256 deposit_,
        uint256 collateralAmountToAdd_,
        uint256 index_
    ) internal returns (uint256 addedLPs_) {
        // calculate amount of LPs to be added for the amount of collateral added to bucket
        (addedLPs_, ) = collateralToLPs(
            self,
            deposit_,
            collateralAmountToAdd_,
            index_
        );
        // update bucket LPs balance and collateral
        Bucket storage bucket = self[index_];
        bucket.lps += addedLPs_;
        bucket.collateral += collateralAmountToAdd_;
        // update lender LPs balance
        bucket.lenders[msg.sender].lps += addedLPs_;
    }

    /**
     *  @notice Moves LPs between buckets and updates lender balance accordingly.
     *  @param  fromLPsAmount_ The amount of LPs to move from origin bucket.
     *  @param  toLPsAmount_   The amount of LPs to move to destination bucket.
     *  @param  fromIndex_     Index of the origin bucket.
     *  @param  toIndex_       Index of the destination bucket.
     */
    function moveLPs(
        mapping(uint256 => Bucket) storage self,
        uint256 fromLPsAmount_,
        uint256 toLPsAmount_,
        uint256 fromIndex_,
        uint256 toIndex_
    ) internal {
        // update buckets LPs balance
        Bucket storage fromBucket = self[fromIndex_];
        Bucket storage toBucket   = self[toIndex_];
        fromBucket.lps -= fromLPsAmount_;
        toBucket.lps   += toLPsAmount_;
        // update lender LPs balance
        fromBucket.lenders[msg.sender].lps -= fromLPsAmount_;
        toBucket.lenders[msg.sender].lps   += toLPsAmount_;
    }

    /**
     *  @notice Removes collateral from a bucket and subtracts LPs (coresponding to collateral amount removed) from bucket and lender balances.
     *  @param  collateralAmountToRemove_ Collateral amount to be removed from bucket.
     *  @param  lpsAmountToRemove_        The amount of LPs to be removed from bucket.
     *  @param  index_                    Index of the bucket to remove collateral to.
     */
    function removeCollateral(
        mapping(uint256 => Bucket) storage self,
        uint256 collateralAmountToRemove_,
        uint256 lpsAmountToRemove_,
        uint256 index_
    ) internal {
        // update bucket collateral and LPs balance
        Bucket storage bucket = self[index_];
        bucket.lps        -= Maths.min(bucket.lps, lpsAmountToRemove_);
        bucket.collateral -= Maths.min(bucket.collateral, collateralAmountToRemove_);
        // update lender LPs balance
        bucket.lenders[msg.sender].lps -= lpsAmountToRemove_;
    }

    /**
     *  @notice Remove LPs from a bucket and from lender balance.
     *  @param  lpsAmountToRemove_ The amount of LPs to be removed from bucket.
     *  @param  index_             Index of the bucket.
     */
    function removeLPs(
        mapping(uint256 => Bucket) storage self,
        uint256 lpsAmountToRemove_,
        uint256 index_
    ) internal {
        // update bucket LPs balance
        self[index_].lps -= lpsAmountToRemove_;
        // update lender LPs balance
        self[index_].lenders[msg.sender].lps -= lpsAmountToRemove_;
    }

    /**
     *  @notice Transfer LPs from owner to an allowed address.
     *  @param  owner_     The current owner of LPs.
     *  @param  newOwner_  The new owner address.
     *  @param  lpsAmount_ The amount of LPs to transfer to new owner.
     */
    function transferLPs(
        mapping(uint256 => Bucket) storage self,
        address owner_,
        address newOwner_,
        uint256 lpsAmount_,
        uint256 index_,
        uint256 depositTime_
    ) internal {
        // move lp tokens to the new owner address
        Lender storage newOwner = self[index_].lenders[newOwner_];
        newOwner.lps += lpsAmount_;
        newOwner.ts  = Maths.max(depositTime_, newOwner.ts);
        // reset owner lp balance for this index
        delete self[index_].lenders[owner_];
    }


    /**********************/
    /*** View Functions ***/
    /**********************/

    /**
     *  @notice Returns the amount of bucket LPs calculated for the given amount of collateral.
     *  @param  deposit_    Current bucket deposit (quote tokens). Used to calculate bucket's exchange rate / LPs.
     *  @param  collateral_ The amount of collateral to calculate bucket LPs for.
     *  @param  index_      Index of the bucket.
     *  @return Amount of LPs calculated for the amount of collateral.
     *  @return Amount of collateral in bucket.
     */
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

    /**
     *  @notice Returns the exchange rate for a given bucket.
     *  @param  quoteToken_ The amount of quote tokens deposited in the given bucket.
     *  @param  index_      Bucket's index.
     *  @return Exchange rate of current bucket.
     *  @return Collateral deposited in current bucket.
     */
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

    /**
     *  @notice Returns the lender info for a given bucket.
     *  @param  index_  Index of the bucket.
     *  @param  lender_ Lender's address.
     *  @return LPs balance of lender in current bucket.
     *  @return Timestamp of last lender deposit in current bucket.
     */
    function getLenderInfo(
        mapping(uint256 => Bucket) storage self,
        uint256 index_,
        address lender_
    ) internal view returns (uint256, uint256) {
        return (self[index_].lenders[lender_].lps, self[index_].lenders[lender_].ts);
    }

    /**
     *  @notice Returns the amount of collateral calculated for the given amount of LPs.
     *  @param  deposit_          Current bucket deposit (quote tokens). Used to calculate bucket's exchange rate / LPs.
     *  @param  lenderLPsBalance_ The amount of LPs to calculate collateral for.
     *  @param  index_            Index of the bucket.
     *  @return collateralAmount_ Amount of collateral calculated for the given LPs amount.
     *  @return lenderLPs_        Amount of lender LPs corresponding for calculated collateral amount.
     */
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

    /**
     *  @notice Returns the amount of quote tokens calculated for the given amount of LPs.
     *  @param  deposit_          Current bucket deposit (quote tokens). Used to calculate bucket's exchange rate / LPs.
     *  @param  lenderLPsBalance_ The amount of LPs to calculate quote token amount for.
     *  @param  maxQuoteToken_    The max quote token amount to calculate LPs for.
     *  @param  index_            Index of the bucket.
     *  @return quoteTokenAmount_ Amount of quote tokens calculated for the given LPs amount.
     *  @return bucketLPs_        Amount of bucket LPs corresponding for calculated collateral amount.
     *  @return lenderLPs_        Lender LPs balance in current bucket.
     */
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

    /**
     *  @notice Returns the amount of LPs calculated for the given amount of quote tokens.
     *  @param  deposit_       Current bucket deposit (quote tokens). Used to calculate bucket's exchange rate / LPs.
     *  @param  quoteTokens_   The amount of quote tokens to calculate LPs amount for.
     *  @param  index_         Index of the bucket.
     *  @return The amount of LPs coresponding to the given quote tokens in current bucket.
     */
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