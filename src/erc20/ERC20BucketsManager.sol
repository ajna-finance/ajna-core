// SPDX-License-Identifier: MIT
pragma solidity 0.8.14;

import { BitMaps }       from "@openzeppelin/contracts/utils/structs/BitMaps.sol";
import { EnumerableSet } from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import { console } from "@std/console.sol";

import { BucketsManager } from "../base/BucketsManager.sol";

import "../libraries/Maths.sol";

abstract contract ERC20BucketsManager is BucketsManager {

    /**********************************/
    /*** Internal Utility Functions ***/
    /**********************************/

    /**
     *  @notice Called by a lender to claim accumulated collateral
     *  @param  price_        The price bucket from which collateral should be claimed
     *  @param  amount_       The amount of collateral tokens to be claimed, WAD
     *  @param  lpBalance_    The claimers current LP balance, RAY
     *  @return lpRedemption_ The amount of LP tokens that will be redeemed
     */
    function _claimCollateralFromBucket(
        uint256 price_, uint256 amount_, uint256 lpBalance_
    ) internal returns (uint256 lpRedemption_) {
        Bucket memory bucket = _buckets[price_];

        require(amount_ <= bucket.collateral, "B:CC:AMT_GT_COLLAT");

        lpRedemption_ = Maths.wrdivr(Maths.wmul(amount_, bucket.price), _exchangeRate(bucket));

        require(lpRedemption_ <= lpBalance_, "B:CC:INSUF_LP_BAL");

        // bucket accounting
        bucket.collateral    -= amount_;
        bucket.lpOutstanding -= lpRedemption_;

        // bucket management
        bool isEmpty = bucket.onDeposit == 0 && bucket.debt == 0;
        bool noClaim = bucket.lpOutstanding == 0 && bucket.collateral == 0;
        if (isEmpty && noClaim) {
            _deactivateBucket(bucket); // cleanup if bucket no longer used
        } else {
            _buckets[price_] = bucket; // save bucket to storage
        }
    }

    /**
     *  @notice Liquidate a given position's collateral
     *  @param  debt_               The amount of debt to cover, WAD
     *  @param  collateral_         The amount of collateral deposited, WAD
     *  @param  inflator_           The current pool inflator rate, RAY
     *  @return requiredCollateral_ The amount of collateral to be liquidated
     */
    function _liquidateAtBucket(
        uint256 debt_, uint256 collateral_, uint256 inflator_
    ) internal returns (uint256 requiredCollateral_) {
        uint256 curPrice = hpb;

        while (true) {
            Bucket storage bucket   = _buckets[curPrice];
            uint256 curDebt         = _accumulateBucketInterest(bucket.debt, bucket.inflatorSnapshot, inflator_);
            bucket.inflatorSnapshot = inflator_;

            uint256 bucketDebtToPurchase     = Maths.min(debt_, curDebt);
            uint256 bucketRequiredCollateral = Maths.min(Maths.wdiv(debt_, bucket.price), collateral_);

            debt_               -= bucketDebtToPurchase;
            collateral_         -= bucketRequiredCollateral;
            requiredCollateral_ += bucketRequiredCollateral;

            // bucket accounting
            curDebt           -= bucketDebtToPurchase;
            bucket.collateral += bucketRequiredCollateral;

            // forgive the debt when borrower has no remaining collateral but still has debt
            if (debt_ != 0 && collateral_ == 0) {
                bucket.debt = 0;
                break;
            }

            bucket.debt = curDebt;

            if (debt_ == 0) break; // stop if all debt reconciliated

            curPrice = bucket.down;
        }

        // HPB and LUP management
        uint256 newHpb = getHpb();
        if (hpb != newHpb) hpb = newHpb;
    }

    /**
     *  @notice Puchase a given amount of quote tokens for given collateral tokens
     *  @param  price_      The price bucket at which the exchange will occur, WAD
     *  @param  amount_     The amount of quote tokens to receive, WAD
     *  @param  collateral_ The amount of collateral to exchange, WAD
     *  @param  inflator_   The current pool inflator rate, RAY
     */
    function _purchaseBidFromBucket(
        uint256 price_, uint256 amount_, uint256 collateral_, uint256 inflator_
    ) internal {
        Bucket memory bucket    = _buckets[price_];
        bucket.debt             = _accumulateBucketInterest(bucket.debt, bucket.inflatorSnapshot, inflator_);
        bucket.inflatorSnapshot = inflator_;

        uint256 available = bucket.onDeposit + bucket.debt;

        require(amount_ <= available, "B:PB:INSUF_BUCKET_LIQ");

        // Exchange collateral for quote token on deposit
        uint256 purchaseFromDeposit = Maths.min(amount_, bucket.onDeposit);

        amount_          -= purchaseFromDeposit;
        // bucket accounting
        bucket.onDeposit -= purchaseFromDeposit;
        bucket.collateral += collateral_;

        // debt reallocation
        uint256 newLup = _reallocateDown(bucket, amount_, inflator_);

        _buckets[price_] = bucket;

        uint256 newHpb = (bucket.onDeposit == 0 && bucket.debt == 0) ? getHpb() : hpb;

        // HPB and LUP management
        if (lup != newLup) lup = newLup;
        if (hpb != newHpb) hpb = newHpb;

        pdAccumulator -= Maths.wmul(purchaseFromDeposit, bucket.price);
    }

}
