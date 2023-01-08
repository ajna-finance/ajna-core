// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.14;

import { Bucket, Lender } from '../../interfaces/pool/commons/IPoolState.sol';

import { Maths } from './Maths.sol';

/**
    @title  Buckets library
    @notice Internal library containing common logic for buckets management.
 */
library Buckets {

    /**************/
    /*** Events ***/
    /**************/

    // See `IPoolError` for descriptions
    error BucketBankruptcyBlock();

    /***********************************/
    /*** Bucket Management Functions ***/
    /***********************************/

    /**
     *  @notice Add collateral to a bucket and updates LPs for bucket and lender with the amount coresponding to collateral amount added.
     *  @dev    Increment bucket.collateral and bucket.lps accumulator
     *             - addLenderLPs:
     *               - increment lender.lps accumulator and lender.depositTime state
     *  @param  lender_                Address of the lender.
     *  @param  deposit_               Current bucket deposit (quote tokens). Used to calculate bucket's exchange rate / LPs
     *  @param  collateralAmountToAdd_ Additional collateral amount to add to bucket.
     *  @param  bucketPrice_           Bucket price.
     *  @return addedLPs_              Amount of bucket LPs for the collateral amount added.
     */
    function addCollateral(
        Bucket storage bucket_,
        address lender_,
        uint256 deposit_,
        uint256 collateralAmountToAdd_,
        uint256 bucketPrice_
    ) internal returns (uint256 addedLPs_) {
        // cannot deposit in the same block when bucket becomes insolvent
        uint256 bankruptcyTime = bucket_.bankruptcyTime;
        if (bankruptcyTime == block.timestamp) revert BucketBankruptcyBlock();

        // calculate amount of LPs to be added for the amount of collateral added to bucket
        addedLPs_ = collateralToLPs(
            bucket_.collateral,
            bucket_.lps,
            deposit_,
            collateralAmountToAdd_,
            bucketPrice_
        );
        // update bucket LPs balance and collateral

        // update bucket collateral
        bucket_.collateral += collateralAmountToAdd_;
        // update bucket and lender LPs balance and deposit timestamp
        bucket_.lps += addedLPs_;

        addLenderLPs(bucket_, bankruptcyTime, lender_, addedLPs_);
    }

    /**
     *  @notice Add amount of LPs for a given lender in a given bucket.
     *  @dev    Increments bucket.collateral and bucket.lps accumulator state.
     *  @param  bucket_         Bucket to record lender LPs.
     *  @param  bankruptcyTime_ Time when bucket become insolvent.
     *  @param  lender_         Lender address to add LPs for in the given bucket.
     *  @param  lpsAmount_      Amount of LPs to be recorded for the given lender.
     */
    function addLenderLPs(
        Bucket storage bucket_,
        uint256 bankruptcyTime_,
        address lender_,
        uint256 lpsAmount_
    ) internal {
        Lender storage lender = bucket_.lenders[lender_];

        if (bankruptcyTime_ >= lender.depositTime) lender.lps = lpsAmount_;
        else lender.lps += lpsAmount_;

        lender.depositTime = block.timestamp;
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

        lps_ = (collateral_ * bucketPrice_ * 1e18 + rate / 2) / rate;
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
        return bucketLPs_ == 0
            ? Maths.RAY
            : (bucketDeposit_ * 1e18 + bucketPrice_ * bucketCollateral_) * 1e18 / bucketLPs_;
            // 10^36 * 1e18 / 10^27 = 10^54 / 10^27 = 10^27
    }

    /**
     *  @notice Returns the unscaled exchange rate for a given bucket.
     *  @param  bucketCollateral_       Amount of collateral in bucket.
     *  @param  bucketLPs_              Amount of LPs in bucket.
     *  @param  bucketUnscaledDeposit_  The amount of unscaled Fenwick tree amount in bucket.
     *  @param  bucketScale_            Bucket scale factor
     *  @param  bucketPrice_            Bucket's price.
     */
    function getUnscaledExchangeRate(
        uint256 bucketCollateral_,
        uint256 bucketLPs_,
        uint256 bucketUnscaledDeposit_,
        uint256 bucketScale_,
        uint256 bucketPrice_
    ) internal pure returns (uint256) {
        return bucketLPs_ == 0
            ? Maths.RAY
            : (bucketUnscaledDeposit_ + bucketPrice_ * bucketCollateral_ / bucketScale_ ) * 10**36 / bucketLPs_;
            // 10^18 * 1e36 / 10^27 = 10^54 / 10^27 = 10^27
    }
}
