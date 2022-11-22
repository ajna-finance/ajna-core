// SPDX-License-Identifier: MIT
pragma solidity 0.8.14;

import '../base/Pool.sol';
import './Maths.sol';
import './BucketMath.sol';

library PoolUtils {
    uint256 internal constant WAD_WEEKS_PER_YEAR  = 52 * 10**18;
    uint256 internal constant MINUTE_HALF_LIFE    = 0.988514020352896135_356867505 * 1e27;  // 0.5^(1/60)

    // minimum fee that can be applied for early withdraw penalty
    uint256 internal constant MIN_FEE = 0.0005 * 10**18;

    function auctionPrice(
        uint256 referencePrice,
        uint256 kickTime_
    ) internal view returns (uint256) {
        return BucketMath.auctionPrice(referencePrice, kickTime_);
    }

    function claimableReserves(
        uint256 debt_,
        uint256 poolSize_,
        uint256 totalBondEscrowed_,
        uint256 reserveAuctionUnclaimed_,
        uint256 quoteTokenBalance_
    ) internal pure returns (uint256 claimable_) {
        claimable_ = Maths.wmul(0.995 * 1e18, debt_) + quoteTokenBalance_;
        claimable_ -= Maths.min(claimable_, poolSize_ + totalBondEscrowed_ + reserveAuctionUnclaimed_);
    }

    function encumberance(
        uint256 debt_,
        uint256 price_
    ) internal pure returns (uint256 encumberance_) {
        return price_ != 0 && debt_ != 0 ? Maths.wdiv(debt_, price_) : 0;
    }

    function collateralization(
        uint256 debt_,
        uint256 collateral_,
        uint256 price_
    ) internal pure returns (uint256) {
        uint256 encumbered = encumberance(debt_, price_);
        return encumbered != 0 ? Maths.wdiv(collateral_, encumbered) : Maths.WAD;
    }

    function poolTargetUtilization(
        uint256 debtEma_,
        uint256 lupColEma_
    ) internal pure returns (uint256) {
        return (debtEma_ != 0 && lupColEma_ != 0) ? Maths.wdiv(debtEma_, lupColEma_) : Maths.WAD;
    }

    function feeRate(
        uint256 interestRate_
    ) internal pure returns (uint256) {
        // greater of the current annualized interest rate divided by 52 (one week of interest) or 5 bps
        return Maths.max(Maths.wdiv(interestRate_, WAD_WEEKS_PER_YEAR), MIN_FEE);
    }

    function pendingInterestFactor(
        uint256 interestRate_,
        uint256 elapsed_
    ) internal pure returns (uint256) {
        return BucketMath.pendingInterestFactor(interestRate_, elapsed_);
    }

    function pendingInflator(
        uint256 inflatorSnapshot_,
        uint256 lastInflatorSnapshotUpdate_,
        uint256 interestRate_
    ) internal view returns (uint256) {
        return BucketMath.pendingInflator(inflatorSnapshot_, lastInflatorSnapshotUpdate_, interestRate_);
    }

    function minDebtAmount(
        uint256 debt_,
        uint256 loansCount_
    ) internal pure returns (uint256 minDebtAmount_) {
        if (loansCount_ != 0) {
            minDebtAmount_ = Maths.wdiv(Maths.wdiv(debt_, Maths.wad(loansCount_)), 10**19);
        }
    }

    function reserveAuctionPrice(
        uint256 reserveAuctionKicked_
    ) internal view returns (uint256 _price) {
        if (reserveAuctionKicked_ != 0) {
            uint256 secondsElapsed = block.timestamp - reserveAuctionKicked_;
            uint256 hoursComponent = 1e27 >> secondsElapsed / 3600;
            uint256 minutesComponent = Maths.rpow(MINUTE_HALF_LIFE, secondsElapsed % 3600 / 60);
            _price = Maths.rayToWad(1_000_000_000 * Maths.rmul(hoursComponent, minutesComponent));
        }
    }

    /**
     *  @notice Returns amount plus calculated early withdrawal penalty (if case).
     *  @param  poolState_         Struct containing pool state details.
     *  @param  depositTime_       Time when deposit happened.
     *  @param  fromIndex_         Index of the bucket from where liquidity is removed or moved.
     *  @param  toIndex_           Index of the bucket where liquidity is moved. 0 in case of withdrawing.
     *  @param  amount_            Amount to calculate early withdrawal penalty for.
     *  @return amountWithPenalty_ The amount plus applied early withdrawal penalty. Same amount if not subject of penalty.
     */
    function applyEarlyWithdrawalPenalty(
        Pool.PoolState memory poolState_,
        uint256 depositTime_,
        uint256 fromIndex_,
        uint256 toIndex_,
        uint256 amount_
    ) internal view returns (uint256 amountWithPenalty_){
        amountWithPenalty_ = amount_;
        if (depositTime_ != 0 && block.timestamp - depositTime_ < 1 days) {
            uint256 ptp = poolState_.collateral != 0 ? Maths.wdiv(poolState_.accruedDebt, poolState_.collateral) : 0;
            bool applyPenalty = indexToPrice(fromIndex_) > ptp; // apply penalty if withdrawal from above PTP
            if (toIndex_ != 0) {
                // move quote token between buckets scenario, apply penalty only if moved to below PTP
                applyPenalty = applyPenalty && indexToPrice(toIndex_) < ptp;
            }
            if (applyPenalty) amountWithPenalty_ = Maths.wmul(amountWithPenalty_, Maths.WAD - feeRate(poolState_.rate));
        }
    }

    function lenderInterestMargin(
        uint256 mau_
    ) internal pure returns (uint256) {
        return BucketMath.lenderInterestMargin(mau_);
    }

    /**
     *  @dev Fenwick index to bucket index conversion
     *          1.00      : bucket index 0,     fenwick index 4146: 7388-4156-3232=0
     *          MAX_PRICE : bucket index 4156,  fenwick index 0:    7388-0-3232=4156.
     *          MIN_PRICE : bucket index -3232, fenwick index 7388: 7388-7388-3232=-3232.
     */
    function indexToPrice(
        uint256 index_
    ) internal pure returns (uint256) {
        int256 bucketIndex = (index_ != 8191) ? 4156 - int256(index_) : BucketMath.MIN_PRICE_INDEX;
        return BucketMath.indexToPrice(bucketIndex);
    }

    function priceToIndex(
        uint256 price_
    ) internal pure returns (uint256) {
        return uint256(7388 - (BucketMath.priceToIndex(price_) + 3232));
    }

    /**
     *  @notice Calculates bond penalty factor.
     *  @dev Called in kick and take.
     *  @param debt_             Borrower debt.
     *  @param collateral_       Borrower collateral.
     *  @param neutralPrice_     NP of auction.
     *  @param bondFactor_       Factor used to determine bondSize.
     *  @param price_            Auction price at the time of call.
     *  @return bpf_             Factor used in determining bond Reward (positive) or penalty (negative).
     */
    function bpf(
        uint256 debt_,
        uint256 collateral_,
        uint256 neutralPrice_,
        uint256 bondFactor_,
        uint256 price_
    ) internal pure returns (int256) {
        return BucketMath.bpf(
            debt_,
            collateral_,
            neutralPrice_,
            bondFactor_,
            price_
        );
    }

}
