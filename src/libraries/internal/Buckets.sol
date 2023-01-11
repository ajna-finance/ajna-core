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
     *  @param  lender_      Address of the lender.
     *  @param  deposit_     Current bucket deposit (quote tokens). Used to calculate bucket's exchange rate / LPs
     *  @param  amount_      Additional collateral amount to add to bucket.
     *  @param  bucketPrice_ Bucket price.
     *  @return bucketLPs_   Amount of bucket LPs for the collateral amount added.
     */
    function addCollateral(
        Bucket storage bucket_,
        address        lender_,
        uint256        deposit_,
        uint256        amount_,
        uint256        bucketPrice_
    ) internal returns (
        uint256 bucketLPs_
    ) {
        uint256 bucketBankruptcyTime = bucket_.bankruptcyTime;

        // cannot deposit in the same block when bucket becomes insolvent
        if (bucketBankruptcyTime == block.timestamp) revert BucketBankruptcyBlock();

        // calculate amount of LPs to be added for the amount of collateral added to bucket
        bucketLPs_ = collateralToLPs(
            bucket_.collateral,
            bucket_.lps,
            deposit_,
            amount_,
            bucketPrice_
        );
        // update bucket LPs balance and collateral

        // update bucket collateral
        bucket_.collateral += amount_;
        // update bucket and lender LPs balance and deposit timestamp
        bucket_.lps += bucketLPs_;

        addLenderLPs(bucket_, bucketBankruptcyTime, lender_, bucketLPs_);
    }

    /**
     *  @notice Add amount of LPs for a given lender in a given bucket.
     *  @dev    Increments bucket.collateral and bucket.lps accumulator state.
     *  @param  bucket_         Bucket to record lender LPs.
     *  @param  bankruptcyTime_ Time when bucket become insolvent.
     *  @param  lender_         Lender address to add LPs for in the given bucket.
     *  @param  bucketLPs_      Amount of bucket LPs to be recorded for the given lender.
     */
    function addLenderLPs(
        Bucket storage bucket_,
        uint256        bankruptcyTime_,
        address        lender_,
        uint256        bucketLPs_
    ) internal {
        Lender storage lender = bucket_.lenders[lender_];

        if (bankruptcyTime_ >= lender.depositTime) lender.lps = bucketLPs_;
        else lender.lps += bucketLPs_;

        lender.depositTime = block.timestamp;
    }

    /**********************/
    /*** View Functions ***/
    /**********************/

    /**
     *  @notice Returns the amount of bucket LPs calculated for the given amount of collateral.
     *  @param  bucketCollateral_ Amount of collateral in bucket.
     *  @param  bucketLPs_        Amount of LPs in bucket.
     *  @param  bucketDeposit_    Current bucket deposit (quote tokens). Used to calculate bucket's exchange rate / LPs.
     *  @param  amount_           The amount of collateral to calculate bucket LPs for.
     *  @param  bucketPrice_      Price bucket.
     *  @return Amount of LPs calculated for the amount of collateral.
     */
    function collateralToLPs(
        uint256 bucketCollateral_,
        uint256 bucketLPs_,
        uint256 bucketDeposit_,
        uint256 amount_,
        uint256 bucketPrice_
    ) internal pure returns (uint256) {
        uint256 bucketRate = getExchangeRate(bucketCollateral_, bucketLPs_, bucketDeposit_, bucketPrice_);

        return (amount_ * bucketPrice_ * 1e18 + bucketRate / 2) / bucketRate;
    }

    /**
     *  @notice Returns the amount of LPs calculated for the given amount of quote tokens.
     *  @param  bucketCollateral_ Amount of collateral in bucket.
     *  @param  bucketLPs_        Amount of LPs in bucket.
     *  @param  bucketDeposit_    Current bucket deposit (quote tokens). Used to calculate bucket's exchange rate / LPs.
     *  @param  amount_           The amount of quote tokens to calculate LPs amount for.
     *  @param  bucketPrice_      Price bucket.
     *  @return The amount of LPs coresponding to the given quote tokens in current bucket.
     */
    function quoteTokensToLPs(
        uint256 bucketCollateral_,
        uint256 bucketLPs_,
        uint256 bucketDeposit_,
        uint256 amount_,
        uint256 bucketPrice_
    ) internal pure returns (uint256) {
        return Maths.rdiv(
            Maths.wadToRay(amount_),
            getExchangeRate(bucketCollateral_, bucketLPs_, bucketDeposit_, bucketPrice_)
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
