// SPDX-License-Identifier: MIT
pragma solidity 0.8.14;

import '../base/Pool.sol';
import './Maths.sol';
import './BucketMath.sol';

library PoolUtils {

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
            if (applyPenalty) amountWithPenalty_ = Maths.wmul(amountWithPenalty_, Maths.WAD - BucketMath.feeRate(poolState_.rate));
        }
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

}
