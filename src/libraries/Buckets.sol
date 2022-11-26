// SPDX-License-Identifier: MIT
pragma solidity 0.8.14;

import './Maths.sol';

library Buckets {

    struct Lender {
        uint256 lps;         // [RAY] Lender LP accumulator
        uint256 depositTime; // timestamp of last deposit
    }

    struct Bucket {
        uint256 lps;                        // [RAY] Bucket LP accumulator
        uint256 collateral;                 // [WAD] Available collateral tokens deposited in the bucket
        uint256 bankruptcyTime;             // Timestamp when bucket become insolvent, 0 if healthy
        mapping(address => Lender) lenders; // lender address to Lender struct mapping
    }

    /**
     *  @notice Operation cannot be executed in the same block when bucket becomes insolvent.
     */
    error BucketBankruptcyBlock();

    /***********************************/
    /*** Bucket Management Functions ***/
    /***********************************/

    /**
     *  @notice Updates LP balances for bucket and lender with the amount coresponding to quote token amount added.
     *  @param  deposit_               Current bucket deposit (quote tokens). Used to calculate bucket's exchange rate / LPs
     *  @param  quoteTokenAmountToAdd_ Additional quote tokens amount to add to bucket deposit.
     *  @param  bucketPrice_           Bucket price.
     *  @return addedLPs_              Amount of bucket LPs for the quote tokens amount added.
     */
    function addQuoteToken(
        Bucket storage bucket_,
        uint256 deposit_,
        uint256 quoteTokenAmountToAdd_,
        uint256 bucketPrice_
    ) internal returns (uint256 addedLPs_) {

        // calculate amount of LPs to be added for the amount of quote tokens added to bucket
        addedLPs_ = quoteTokensToLPs(
            bucket_.collateral,
            bucket_.lps,
            deposit_,
            quoteTokenAmountToAdd_,
            bucketPrice_
        );

        // update bucket LPs balance
        // cannot deposit in the same block when bucket becomes insolvent
        if (bucket_.bankruptcyTime == block.timestamp) revert BucketBankruptcyBlock();
        // update bucket and lender LPs balance and deposit timestamp
        addLPs(bucket_, msg.sender, addedLPs_);
    }

    /**
     *  @notice Add collateral to a bucket and updates LPs for bucket and lender with the amount coresponding to collateral amount added.
     *  @param  deposit_               Current bucket deposit (quote tokens). Used to calculate bucket's exchange rate / LPs
     *  @param  collateralAmountToAdd_ Additional collateral amount to add to bucket.
     *  @param  bucketPrice_           Bucket price.
     *  @return addedLPs_              Amount of bucket LPs for the collateral amount added.
     */
    function addCollateral(
        Bucket storage bucket_,
        uint256 deposit_,
        uint256 collateralAmountToAdd_,
        uint256 bucketPrice_
    ) internal returns (uint256 addedLPs_) {

        // calculate amount of LPs to be added for the amount of collateral added to bucket
        addedLPs_ = collateralToLPs(
            bucket_.collateral,
            bucket_.lps,
            deposit_,
            collateralAmountToAdd_,
            bucketPrice_
        );
        // update bucket LPs balance and collateral
        // cannot deposit in the same block when bucket becomes insolvent
        if (bucket_.bankruptcyTime == block.timestamp) revert BucketBankruptcyBlock();
        bucket_.collateral += collateralAmountToAdd_;
        // update bucket and lender LPs balance and deposit timestamp
        addLPs(bucket_, msg.sender, addedLPs_);
    }

    /**
     *  @notice Add amount of LPs for a given lender in a given bucket.
     *  @param  bucket_    Bucket to record lender LPs.
     *  @param  lender_    Lender address to add LPs for in the given bucket.
     *  @param  lpsAmount_ Amount of LPs to be recorded for the given lender.
     */
    function addLPs(
        Bucket storage bucket_,
        address lender_,
        uint256 lpsAmount_
    ) internal {
        bucket_.lps += lpsAmount_;

        Lender storage lender = bucket_.lenders[lender_];
        if (bucket_.bankruptcyTime >= lender.depositTime) lender.lps = lpsAmount_;
        else lender.lps += lpsAmount_;
        lender.depositTime = block.timestamp;
    }

    /**
     *  @notice Moves LPs between buckets and updates lender balance accordingly.
     *  @param  fromLPsAmount_ The amount of LPs to move from origin bucket.
     *  @param  toLPsAmount_   The amount of LPs to move to destination bucket.
     */
    function moveLPs(
        Bucket storage fromBucket_,
        Bucket storage toBucket_,
        uint256 fromLPsAmount_,
        uint256 toLPsAmount_
    ) internal {

        // cannot move in the same block when target bucket becomes insolvent
        if (toBucket_.bankruptcyTime == block.timestamp) revert BucketBankruptcyBlock();

        // update buckets LPs balance
        fromBucket_.lps -= fromLPsAmount_;
        toBucket_.lps   += toLPsAmount_;
        // update lender LPs balance in from bucket
        Lender storage fromLender = fromBucket_.lenders[msg.sender];
        fromLender.lps -= fromLPsAmount_;

        // update lender LPs balance and deposit time in target bucket
        Lender storage lender = toBucket_.lenders[msg.sender];
        if (toBucket_.bankruptcyTime >= lender.depositTime) lender.lps = toLPsAmount_;
        else lender.lps += toLPsAmount_;
        // set deposit time to the greater of the lender's from bucket and the target bucket's last bankruptcy timestamp + 1 so deposit won't get invalidated
        lender.depositTime = Maths.max(fromLender.depositTime, toBucket_.bankruptcyTime + 1);
    }

    /**
     *  @notice Removes collateral from a bucket and subtracts LPs (coresponding to collateral amount removed) from bucket and lender balances.
     *  @param  collateralAmountToRemove_ Collateral amount to be removed from bucket.
     *  @param  lpsAmountToRemove_        The amount of LPs to be removed from bucket.
     */
    function removeCollateral(
        Bucket storage bucket_,
        uint256 collateralAmountToRemove_,
        uint256 lpsAmountToRemove_
    ) internal {
        // update bucket collateral and LPs balance
        bucket_.lps        -= Maths.min(bucket_.lps, lpsAmountToRemove_);
        bucket_.collateral -= Maths.min(bucket_.collateral, collateralAmountToRemove_);
        // update lender LPs balance
        bucket_.lenders[msg.sender].lps -= lpsAmountToRemove_;
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
        newOwner.lps         += lpsAmount_;
        newOwner.depositTime = Maths.max(depositTime_, newOwner.depositTime);
        // reset owner lp balance for this index
        delete self[index_].lenders[owner_];
    }


    /**********************/
    /*** View Functions ***/
    /**********************/

    /**
     *  @notice Returns the amount of bucket LPs calculated for the given amount of collateral.
     *  @param  bucketCollateral_ Amount of collateral in bucket.
     *  @param  bucketLPs_        Amount of LPs in bucket.
     *  @param  deposit_     Current bucket deposit (quote tokens). Used to calculate bucket's exchange rate / LPs.
     *  @param  collateral_  The amount of collateral to calculate bucket LPs for.
     *  @param  bucketPrice_ Price bucket.
     *  @return lps_         Amount of LPs calculated for the amount of collateral.
     */
    function collateralToLPs(
        uint256 bucketCollateral_,
        uint256 bucketLPs_,
        uint256 deposit_,
        uint256 collateral_,
        uint256 bucketPrice_
    ) internal pure returns (uint256 lps_) {
        uint256 rate = getExchangeRate(bucketCollateral_, bucketLPs_, deposit_, bucketPrice_);
        lps_         = (collateral_ * bucketPrice_ * 1e18 + rate / 2) / rate;
    }

    /**
     *  @notice Returns the exchange rate for a given bucket.
     *  @param  bucketCollateral_ Amount of collateral in bucket.
     *  @param  bucketLPs_        Amount of LPs in bucket.
     *  @param  bucketDeposit_    The amount of quote tokens deposited in the given bucket.
     *  @param  bucketPrice_      Bucket's price.
     */
    function getExchangeRate(
        uint256 bucketCollateral_,
        uint256 bucketLPs_,
        uint256 bucketDeposit_,
        uint256 bucketPrice_
    ) internal pure returns (uint256) {
        return bucketLPs_ == 0 ? Maths.RAY :
            (bucketDeposit_ * 1e18 + bucketPrice_ * bucketCollateral_) * 1e18 / bucketLPs_;
            // 10^36 * 1e18 / 10^27 = 10^54 / 10^27 = 10^27
    }

    /**
     *  @notice Returns the lender info for a given bucket.
     *  @param  index_       Index of the bucket.
     *  @param  lender_      Lender's address.
     *  @return lpBalance_   LPs balance of lender in current bucket.
     *  @return depositTime_ Timestamp of last lender deposit in current bucket.
     */
    function getLenderInfo(
        mapping(uint256 => Bucket) storage self,
        uint256 index_,
        address lender_
    ) internal view returns (uint256 lpBalance_, uint256 depositTime_) {
        depositTime_ = self[index_].lenders[lender_].depositTime;
        if (self[index_].bankruptcyTime < depositTime_) lpBalance_ = self[index_].lenders[lender_].lps;
    }

    /**
     *  @notice Returns the amount of collateral calculated for the given amount of LPs.
     *  @param  bucketCollateral_ Amount of collateral in bucket.
     *  @param  bucketLPs_        Amount of LPs in bucket.
     *  @param  deposit_          Current bucket deposit (quote tokens). Used to calculate bucket's exchange rate / LPs.
     *  @param  lenderLPsBalance_ The amount of LPs to calculate collateral for.
     *  @param  bucketPrice_      Bucket price.
     *  @return collateralAmount_ Amount of collateral calculated for the given LPs amount.
     *  @return lenderLPs_        Amount of lender LPs corresponding for calculated collateral amount.
     */
    function lpsToCollateral(
        uint256 bucketCollateral_,
        uint256 bucketLPs_,
        uint256 deposit_,
        uint256 lenderLPsBalance_,
        uint256 bucketPrice_
    ) internal pure returns (uint256 collateralAmount_, uint256 lenderLPs_) {
        // max collateral to lps
        lenderLPs_  = lenderLPsBalance_;
        uint256 rate = getExchangeRate(bucketCollateral_, bucketLPs_, deposit_, bucketPrice_);

        collateralAmount_ = Maths.rwdivw(Maths.rmul(lenderLPsBalance_, rate), bucketPrice_);
        if (collateralAmount_ > bucketCollateral_) {
            // user is owed more collateral than is available in the bucket
            collateralAmount_ = bucketCollateral_;
            lenderLPs_        = Maths.wrdivr(Maths.wmul(collateralAmount_, bucketPrice_), rate);
        }
    }

    /**
     *  @notice Returns the amount of quote tokens calculated for the given amount of LPs.
     *  @param  bucketLPs_        Amount of LPs in bucket.
     *  @param  bucketCollateral_ Amount of collateral in bucket.
     *  @param  deposit_          Current bucket deposit (quote tokens). Used to calculate bucket's exchange rate / LPs.
     *  @param  lenderLPsBalance_ The amount of LPs to calculate quote token amount for.
     *  @param  maxQuoteToken_    The max quote token amount to calculate LPs for.
     *  @param  bucketPrice_      Bucket price.
     *  @return quoteTokenAmount_ Amount of quote tokens calculated for the given LPs amount.
     *  @return lps_              Amount of bucket LPs corresponding for calculated collateral amount.
     *  @return lenderLPs_        Lender LPs balance in current bucket.
     */
    function lpsToQuoteToken(
        uint256 bucketLPs_,
        uint256 bucketCollateral_,
        uint256 deposit_,
        uint256 lenderLPsBalance_,
        uint256 maxQuoteToken_,
        uint256 bucketPrice_
    ) internal pure returns (uint256 quoteTokenAmount_, uint256 lps_, uint256 lenderLPs_) {
        lenderLPs_   = lenderLPsBalance_;
        uint256 rate = getExchangeRate(bucketCollateral_, bucketLPs_, deposit_, bucketPrice_);
        quoteTokenAmount_ = Maths.rayToWad(Maths.rmul(lenderLPsBalance_, rate));
        if (quoteTokenAmount_ > deposit_) {
            quoteTokenAmount_ = deposit_;
            lenderLPs_        = Maths.wrdivr(quoteTokenAmount_, rate);
        }
        if (maxQuoteToken_ != quoteTokenAmount_) quoteTokenAmount_ = Maths.min(maxQuoteToken_,quoteTokenAmount_);
        lps_ = Maths.wrdivr(quoteTokenAmount_, rate);
    }

    /**
     *  @notice Returns the amount of LPs calculated for the given amount of quote tokens.
     *  @param  bucketCollateral_ Amount of collateral in bucket.
     *  @param  bucketLPs_        Amount of LPs in bucket.
     *  @param  deposit_     Current bucket deposit (quote tokens). Used to calculate bucket's exchange rate / LPs.
     *  @param  quoteTokens_ The amount of quote tokens to calculate LPs amount for.
     *  @param  bucketPrice_ Price bucket.
     *  @return The amount of LPs coresponding to the given quote tokens in current bucket.
     */
    function quoteTokensToLPs(
        uint256 bucketCollateral_,
        uint256 bucketLPs_,
        uint256 deposit_,
        uint256 quoteTokens_,
        uint256 bucketPrice_
    ) internal pure returns (uint256) {
        return Maths.rdiv(
            Maths.wadToRay(quoteTokens_),
            getExchangeRate(bucketCollateral_, bucketLPs_, deposit_, bucketPrice_)
        );
    }
}